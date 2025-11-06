import Foundation

// ======================================================================

// MARK: - DMG Operations

// ======================================================================

enum DMGDirection: String, CaseIterable, Identifiable {
    case rwToRo = "RW → RO"
    case roToRw = "RO → RW"
    var id: String { rawValue }
}

enum DMGCreateMode: String, CaseIterable, Identifiable {
    case fromFolder = "Aus Ordner"
    case empty = "Leeres Image"
    var id: String { rawValue }
}

enum DMGFileSystem: String, CaseIterable, Identifiable {
    case apfs = "APFS"
    case hfsj = "HFS+J"
    var id: String { rawValue }
    var argument: String {
        self == .apfs ? "APFS" : "HFS+J"
    }
}

enum DMGAccess: String, CaseIterable, Identifiable {
    case readOnly = "RO (UDZO)"
    case readWrite = "RW (UDRW)"
    var id: String { rawValue }
    var format: String {
        self == .readOnly ? "UDZO" : "UDRW"
    }
}

actor DMGOperations {
    private let iconHandler = IconHandler()
    private let iconOperations = DMGIconOperations()

    struct CreateDMGOptions {
        let mode: DMGCreateMode
        let sourceFolder: URL?
        let emptySize: String
        let volumeName: String
        let fileSystem: DMGFileSystem
        let access: DMGAccess
        let outputURL: URL
        let password: String
        let logger: (String) -> Void
    }

    private struct StandardConversionOptions {
        let arguments: [String]
        let destinationURL: URL
        let appIconURL: URL?
        let tempMountPoint: String?
        let password: String
        let logger: (String) -> Void
    }

    func createDMG(options: CreateDMGOptions) async {
        var arguments: [String]

        switch options.mode {
        case .fromFolder:
            guard let source = options.sourceFolder else {
                options.logger("❌ FEHLER: Quellordner nicht ausgewählt")
                return
            }
            arguments = [
                "create", "-volname", options.volumeName, "-fs", options.fileSystem.argument,
                "-format", options.access.format, "-srcfolder", source.path, options.outputURL.path,
            ]
        case .empty:
            let sizeText = options.emptySize.trimmingCharacters(in: .whitespacesAndNewlines)
            let sizePattern = #"^\d+(\.\d+)?\s*[kmgtKMGT]?$"#
            guard sizeText.range(of: sizePattern, options: .regularExpression) != nil else {
                options.logger("❌ FEHLER: Ungültige Größe (Beispiele: 200m, 1g)")
                return
            }
            arguments = [
                "create", "-size", sizeText, "-fs", options.fileSystem.argument,
                "-volname", options.volumeName, options.outputURL.path,
            ]
        }

        if !options.password.isEmpty { arguments += ["-stdinpass"] }

        // Ensure output file doesn't exist (should be handled by UI, but double-check)
        if FileManager.default.fileExists(atPath: options.outputURL.path) {
            do {
                try FileManager.default.removeItem(at: options.outputURL)
                options.logger("Existierende Datei entfernt: \(options.outputURL.path)")
            } catch {
                options.logger("❌ FEHLER: Konnte existierende Datei nicht entfernen: \(error.localizedDescription)")
                return
            }
        }

        let stdin = options.password.isEmpty ? nil : (options.password.data(using: .utf8) ?? Data())
        options.logger("$ hdiutil " + printableArguments(arguments))

        do {
            let result = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: arguments, stdinData: stdin)
            if !result.stdOut.isEmpty { options.logger(result.stdOut) }
            if !result.stdErr.isEmpty { options.logger(result.stdErr) }

            let statusMessage = result.terminationStatus == 0
                ? "✅ FERTIG: \(options.outputURL.path)"
                : "❌ FEHLER: Fehlercode \(result.terminationStatus)"
            options.logger(statusMessage)
        } catch {
            options.logger("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    struct ConvertDMGOptions {
        let sourceURL: URL
        let destinationURL: URL
        let direction: DMGDirection
        let useAppIcon: Bool
        let password: String
        let logger: (String) -> Void
    }

    func convertDMG(options: ConvertDMGOptions) async {
        // Prüfe Mounts für Quelle
        options.logger("Prüfe Mounts für: \(options.sourceURL.path)")
        let detached = await ensureDetached(image: options.sourceURL) { message in
            Task { @MainActor in options.logger(message) }
        }
        if !detached {
            options.logger("❌ FEHLER: Quelle belegt. Abbruch.")
            return
        }

        // Handle destination file if exists
        if FileManager.default.fileExists(atPath: options.destinationURL.path) {
            _ = await ensureDetached(image: options.destinationURL) { message in
                Task { @MainActor in options.logger(message) }
            }
            try? FileManager.default.removeItem(at: options.destinationURL)
        }

        // App Icon vorbereiten falls nötig
        let (appIconURL, tempMountPoint) = options.direction == .rwToRo && options.useAppIcon
            ? await prepareAppIcon(from: options.sourceURL, password: options.password, logger: options.logger)
            : (nil, nil)

        // Spezielle Behandlung für RW→RO mit App-Icon
        if options.direction == .rwToRo, options.useAppIcon, appIconURL != nil {
            await iconOperations.performRWToROWithIcon(options: DMGIconOperations.RWToROConversionOptions(
                sourceURL: options.sourceURL,
                destinationURL: options.destinationURL,
                appIconURL: appIconURL!,
                tempMountPoint: tempMountPoint,
                password: options.password,
                logger: options.logger
            ))
            return
        }

        // Standard-Konvertierung
        if options.direction == .rwToRo {
            // Erst verkleinern, dann komprimieren
            await performRWToROConversion(
                sourceURL: options.sourceURL,
                destinationURL: options.destinationURL,
                appIconURL: appIconURL,
                tempMountPoint: tempMountPoint,
                password: options.password,
                logger: options.logger
            )
        } else {
            // RO → RW mit extra Speicherplatz
            await performROToRWConversion(
                sourceURL: options.sourceURL,
                destinationURL: options.destinationURL,
                appIconURL: appIconURL,
                tempMountPoint: tempMountPoint,
                password: options.password,
                logger: options.logger
            )
        }
    }

    private func prepareAppIcon(
        from sourceURL: URL,
        password: String,
        logger: @escaping (String) -> Void
    ) async -> (URL?, String?) {
        logger("Suche nach .app-Dateien für Icon...")

        var tempMountArgs = ["attach", sourceURL.path, "-readonly", "-nobrowse", "-noautoopen"]
        if !password.isEmpty { tempMountArgs += ["-stdinpass"] }

        do {
            let stdin = password.isEmpty ? nil : (password.data(using: .utf8) ?? Data())
            let tempMountResult = try await runProcess(
                launchPath: "/usr/bin/hdiutil",
                arguments: tempMountArgs,
                stdinData: stdin
            )
            if let mountPoint = parseFirstMountPoint(from: tempMountResult.stdOut) {
                logger("Temporär gemountet: \(mountPoint)")

                if FileManager.default.fileExists(atPath: mountPoint) {
                    if let foundApp = await iconHandler.findAppInMountedDMG(mountPoint) {
                        logger(".app gefunden: \(foundApp.lastPathComponent)")

                        let tempAppPath = NSTemporaryDirectory() + "temp_app_for_icon_\(UUID().uuidString)"
                        try? FileManager.default.removeItem(atPath: tempAppPath)
                        try FileManager.default.copyItem(at: foundApp, to: URL(fileURLWithPath: tempAppPath))
                        let appIconURL = URL(fileURLWithPath: tempAppPath)
                        logger(".app temporär kopiert nach: \(tempAppPath)")
                        return (appIconURL, mountPoint)
                    } else {
                        logger("Keine .app-Datei im DMG gefunden")
                    }
                } else {
                    logger("Mount-Point nicht verfügbar: \(mountPoint)")
                }
                return (nil, mountPoint)
            }
        } catch {
            logger("Fehler beim temporären Mounten: \(error.localizedDescription)")
        }
        return (nil, nil)
    }

    private func performStandardConversion(options: StandardConversionOptions) async {
        let stdin = options.password.isEmpty ? nil : (options.password.data(using: .utf8) ?? Data())
        var convertArgs = options.arguments
        if !options.password.isEmpty { convertArgs += ["-stdinpass"] }

        options.logger("$ hdiutil " + printableArguments(convertArgs))
        do {
            let result = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: convertArgs, stdinData: stdin)
            if !result.stdOut.isEmpty { options.logger(result.stdOut) }
            if !result.stdErr.isEmpty { options.logger(result.stdErr) }

            if result.terminationStatus == 0 {
                let message = "Konvertierung abgeschlossen: \(options.destinationURL.path)"
                options.logger(message)

                if let iconURL = options.appIconURL {
                    options.logger("Setze DMG-Icon...")
                    await iconHandler.setDMGIconFromApp(iconURL, dmgURL: options.destinationURL, logger: options.logger)

                    try? FileManager.default.removeItem(at: iconURL)
                    options.logger("Temporäre .app-Kopie gelöscht")
                }
            } else {
                options.logger("❌ FEHLER: Fehlercode \(result.terminationStatus)")
            }

            if let mountPoint = options.tempMountPoint {
                let detachResult = try? await runProcess(
                    launchPath: "/usr/bin/hdiutil",
                    arguments: ["detach", "-force", mountPoint]
                )
                if detachResult?.terminationStatus == 0 {
                    options.logger("Temporärer Mount erfolgreich entfernt")
                } else {
                    options.logger("Warnung: Temporärer Mount-Entfernung hatte Probleme")
                }
            }

            if let iconPath = options.appIconURL, FileManager.default.fileExists(atPath: iconPath.path) {
                try? FileManager.default.removeItem(at: iconPath)
                options.logger("Verbleibende temporäre Datei gelöscht")
            }
        } catch {
            options.logger("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    private func performROToRWConversion(
        sourceURL: URL,
        destinationURL: URL,
        appIconURL: URL?,
        tempMountPoint: String?,
        password: String,
        logger: @escaping (String) -> Void
    ) async {
        let stdin = password.isEmpty ? nil : (password.data(using: .utf8) ?? Data())

        // Schritt 1: Zu RW konvertieren
        var convertArgs = ["convert", sourceURL.path, "-format", "UDRW", "-o", destinationURL.path]
        if !password.isEmpty { convertArgs += ["-stdinpass"] }

        logger("$ hdiutil " + printableArguments(convertArgs))

        do {
            let convertResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: convertArgs, stdinData: stdin)
            if !convertResult.stdOut.isEmpty { logger(convertResult.stdOut) }
            if !convertResult.stdErr.isEmpty { logger(convertResult.stdErr) }

            guard convertResult.terminationStatus == 0 else {
                logger("❌ FEHLER: Konvertierung zu RW fehlgeschlagen")
                return
            }

            // Schritt 2: Vergrößern um 1GB
            logger("Vergrößere um 1GB für Bearbeitungen...")
            let resizeResult = try await runProcess(
                launchPath: "/usr/bin/hdiutil",
                arguments: ["resize", "-size", "+1g", destinationURL.path]
            )
            if !resizeResult.stdOut.isEmpty { logger(resizeResult.stdOut) }
            if !resizeResult.stdErr.isEmpty { logger(resizeResult.stdErr) }

            if resizeResult.terminationStatus == 0 {
                logger("Konvertierung abgeschlossen: \(destinationURL.path)")

                if let iconURL = appIconURL {
                    logger("Setze DMG-Icon...")
                    await iconHandler.setDMGIconFromApp(iconURL, dmgURL: destinationURL, logger: logger)
                    try? FileManager.default.removeItem(at: iconURL)
                    logger("Temporäre .app-Kopie gelöscht")
                }
            } else {
                logger("⚠️ Warnung: Resize fehlgeschlagen, aber Konvertierung erfolgreich")
            }

            if let mountPoint = tempMountPoint {
                let detachResult = try? await runProcess(
                    launchPath: "/usr/bin/hdiutil",
                    arguments: ["detach", "-force", mountPoint]
                )
                if detachResult?.terminationStatus == 0 {
                    logger("Temporärer Mount erfolgreich entfernt")
                } else {
                    logger("Warnung: Temporärer Mount-Entfernung hatte Probleme")
                }
            }

            if let iconPath = appIconURL, FileManager.default.fileExists(atPath: iconPath.path) {
                try? FileManager.default.removeItem(at: iconPath)
                logger("Verbleibende temporäre Datei gelöscht")
            }
        } catch {
            logger("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    private func performRWToROConversion(
        sourceURL: URL,
        destinationURL: URL,
        appIconURL: URL?,
        tempMountPoint: String?,
        password: String,
        logger: @escaping (String) -> Void
    ) async {
        let stdin = password.isEmpty ? nil : (password.data(using: .utf8) ?? Data())

        // Schritt 1: RW-DMG mounten
        logger("Mounte RW-DMG um Inhalt zu kopieren...")
        var mountArgs = ["attach", sourceURL.path, "-readonly", "-nobrowse", "-noautoopen"]
        if !password.isEmpty { mountArgs += ["-stdinpass"] }

        do {
            let mountResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: mountArgs, stdinData: stdin)
            if !mountResult.stdOut.isEmpty { logger(mountResult.stdOut) }

            guard mountResult.terminationStatus == 0,
                  let mountedPath = parseFirstMountPoint(from: mountResult.stdOut) else {
                logger("❌ FEHLER: Konnte RW-DMG nicht mounten")
                await performDirectCompression(sourceURL: sourceURL, destinationURL: destinationURL, appIconURL: appIconURL, tempMountPoint: tempMountPoint, password: password, logger: logger, stdin: stdin)
                return
            }

            logger("Gemountet bei: \(mountedPath)")

            // Schritt 2: Volumen-Name ermitteln
            let volumeName = URL(fileURLWithPath: mountedPath).lastPathComponent

            // Schritt 2.5: Prüfe ob .VolumeIcon.icns vorhanden ist
            let volumeIconPath = mountedPath + "/.VolumeIcon.icns"
            let hasVolumeIcon = FileManager.default.fileExists(atPath: volumeIconPath)
            var tempVolumeIconPath: String?

            if hasVolumeIcon {
                logger("Volume-Icon gefunden, sichere es...")
                tempVolumeIconPath = NSTemporaryDirectory() + "temp_volumeicon_\(UUID().uuidString).icns"
                try? FileManager.default.copyItem(atPath: volumeIconPath, toPath: tempVolumeIconPath!)
            }

            // Schritt 3: Neues DMG direkt vom gemounteten Inhalt erstellen
            logger("Erstelle optimiertes RO-DMG vom Inhalt...")
            var createArgs = ["create", "-srcfolder", mountedPath, "-volname", volumeName,
                             "-format", "UDRW", "-o", NSTemporaryDirectory() + "temp_new_\(UUID().uuidString).dmg"]
            if !password.isEmpty { createArgs += ["-stdinpass"] }

            logger("$ hdiutil " + printableArguments(createArgs))

            let createResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: createArgs, stdinData: stdin)
            if !createResult.stdOut.isEmpty { logger(createResult.stdOut) }
            if !createResult.stdErr.isEmpty { logger(createResult.stdErr) }

            guard createResult.terminationStatus == 0,
                  let createdDMG = createArgs.last else {
                logger("❌ FEHLER: Konnte neues DMG nicht erstellen")
                _ = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: ["detach", "-force", mountedPath])
                return
            }

            let tempNewDMG = URL(fileURLWithPath: createdDMG)

            // Schritt 4: Unmount altes RW-DMG
            _ = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: ["detach", "-force", mountedPath])
            logger("RW-DMG unmountet")

            // Schritt 5: Volume-Icon wiederherstellen falls vorhanden
            if let tempIcon = tempVolumeIconPath {
                logger("Setze Volume-Icon auf neues DMG...")
                var mountNewArgs = ["attach", createdDMG, "-nobrowse", "-noautoopen"]
                if !password.isEmpty { mountNewArgs += ["-stdinpass"] }

                let mountNewResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: mountNewArgs, stdinData: stdin)
                if let newMountPath = parseFirstMountPoint(from: mountNewResult.stdOut) {
                    let newVolumeIconPath = newMountPath + "/.VolumeIcon.icns"
                    try? FileManager.default.copyItem(atPath: tempIcon, toPath: newVolumeIconPath)

                    // SetFile -a C um das Icon zu aktivieren
                    _ = try? await runProcess(launchPath: "/usr/bin/SetFile", arguments: ["-a", "C", newMountPath])

                    _ = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: ["detach", "-force", newMountPath])
                    logger("Volume-Icon wiederhergestellt")
                }
                try? FileManager.default.removeItem(atPath: tempIcon)
            }

            // Schritt 6: Zu UDZO komprimieren
            logger("Komprimiere finales DMG...")
            var compressArgs = ["convert", createdDMG, "-format", "UDZO", "-o", destinationURL.path, "-imagekey", "zlib-level=9"]
            if !password.isEmpty { compressArgs += ["-stdinpass"] }

            let compressResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: compressArgs, stdinData: stdin)
            if !compressResult.stdOut.isEmpty { logger(compressResult.stdOut) }
            if !compressResult.stdErr.isEmpty { logger(compressResult.stdErr) }

            // Cleanup
            try? FileManager.default.removeItem(at: tempNewDMG)

            if compressResult.terminationStatus == 0 {
                logger("Konvertierung abgeschlossen: \(destinationURL.path)")

                if let iconURL = appIconURL {
                    logger("Setze DMG-Icon...")
                    await iconHandler.setDMGIconFromApp(iconURL, dmgURL: destinationURL, logger: logger)
                    try? FileManager.default.removeItem(at: iconURL)
                    logger("Temporäre .app-Kopie gelöscht")
                }
            } else {
                logger("❌ FEHLER: Fehlercode \(compressResult.terminationStatus)")
            }

            if let mountPoint = tempMountPoint {
                let detachResult = try? await runProcess(
                    launchPath: "/usr/bin/hdiutil",
                    arguments: ["detach", "-force", mountPoint]
                )
                if detachResult?.terminationStatus == 0 {
                    logger("Temporärer Mount erfolgreich entfernt")
                } else {
                    logger("Warnung: Temporärer Mount-Entfernung hatte Probleme")
                }
            }

            if let iconPath = appIconURL, FileManager.default.fileExists(atPath: iconPath.path) {
                try? FileManager.default.removeItem(at: iconPath)
                logger("Verbleibende temporäre Datei gelöscht")
            }
        } catch {
            logger("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    private func performDirectCompression(
        sourceURL: URL,
        destinationURL: URL,
        appIconURL: URL?,
        tempMountPoint: String?,
        password: String,
        logger: @escaping (String) -> Void,
        stdin: Data?
    ) async {
        logger("Komprimiere zu RO (ohne Resize)...")
        var finalArgs = ["convert", sourceURL.path, "-format", "UDZO", "-o", destinationURL.path, "-imagekey", "zlib-level=9"]
        if !password.isEmpty { finalArgs += ["-stdinpass"] }

        logger("$ hdiutil " + printableArguments(finalArgs))

        do {
            let finalResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: finalArgs, stdinData: stdin)
            if !finalResult.stdOut.isEmpty { logger(finalResult.stdOut) }
            if !finalResult.stdErr.isEmpty { logger(finalResult.stdErr) }

            if finalResult.terminationStatus == 0 {
                logger("Konvertierung abgeschlossen: \(destinationURL.path)")

                if let iconURL = appIconURL {
                    logger("Setze DMG-Icon...")
                    await iconHandler.setDMGIconFromApp(iconURL, dmgURL: destinationURL, logger: logger)
                    try? FileManager.default.removeItem(at: iconURL)
                    logger("Temporäre .app-Kopie gelöscht")
                }
            } else {
                logger("❌ FEHLER: Fehlercode \(finalResult.terminationStatus)")
            }

            if let mountPoint = tempMountPoint {
                let detachResult = try? await runProcess(
                    launchPath: "/usr/bin/hdiutil",
                    arguments: ["detach", "-force", mountPoint]
                )
                if detachResult?.terminationStatus == 0 {
                    logger("Temporärer Mount erfolgreich entfernt")
                } else {
                    logger("Warnung: Temporärer Mount-Entfernung hatte Probleme")
                }
            }

            if let iconPath = appIconURL, FileManager.default.fileExists(atPath: iconPath.path) {
                try? FileManager.default.removeItem(at: iconPath)
                logger("Verbleibende temporäre Datei gelöscht")
            }
        } catch {
            logger("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    private func printableArguments(_ arguments: [String]) -> String {
        arguments.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}
