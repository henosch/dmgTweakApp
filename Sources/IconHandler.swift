import Foundation

// ======================================================================

// MARK: - Icon Handler

// ======================================================================

actor IconHandler {
    func setDMGIconFromApp(_ appURL: URL, dmgURL: URL, logger: @escaping (String) -> Void) async {
        guard let iconFile = await findIconFileInApp(appURL) else {
            logger("Keine .icns Datei in der .app gefunden")
            return
        }

        logger("Verwende Icon: \(iconFile.lastPathComponent)")
        await logIconFileInfo(iconFile, logger: logger)
        await setSipsIcon(iconFile: iconFile, dmgURL: dmgURL, logger: logger)
    }

    private func logIconFileInfo(_ iconFile: URL, logger: @escaping (String) -> Void) async {
        do {
            let fileInfo = try await runProcess(launchPath: "/usr/bin/file", arguments: [iconFile.path])
            logger("Icon-Datei-Info: \(fileInfo.stdOut.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            logger("Warnung: Konnte Icon-Datei nicht analysieren")
        }
    }

    private func setSipsIcon(iconFile: URL, dmgURL: URL, logger: @escaping (String) -> Void) async {
        // Zuerst .icns-Datei validieren
        do {
            let validateResult = try await runProcess(
                launchPath: "/usr/bin/sips",
                arguments: ["--getProperty", "pixelWidth", iconFile.path]
            )

            if validateResult.terminationStatus != 0 {
                logger("Icon-Datei nicht sips-kompatibel, verwende Resource Fork-Methode...")
                await tryResourceForkMethod(iconFile: iconFile, dmgURL: dmgURL, logger: logger)
                return
            }
            logger("Icon-Datei validiert: \(validateResult.stdOut.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            logger("Icon-Validierung fehlgeschlagen, verwende Resource Fork-Methode...")
            await tryResourceForkMethod(iconFile: iconFile, dmgURL: dmgURL, logger: logger)
            return
        }

        // Versuche sips-Methode
        do {
            let sipsResult = try await runProcess(
                launchPath: "/usr/bin/sips",
                arguments: ["-i", iconFile.path, dmgURL.path]
            )

            if sipsResult.terminationStatus == 0 {
                logger("DMG-Icon gesetzt (sips-Methode)")
                // Finder zum Aktualisieren zwingen
                _ = try? await runProcess(launchPath: "/usr/bin/touch", arguments: [dmgURL.path])
            } else {
                logger("sips nicht kompatibel, verwende Resource Fork-Methode...")
                await tryResourceForkMethod(iconFile: iconFile, dmgURL: dmgURL, logger: logger)
            }
        } catch {
            logger("sips-Methode fehlgeschlagen: \(error.localizedDescription)")
            await tryResourceForkMethod(iconFile: iconFile, dmgURL: dmgURL, logger: logger)
        }
    }

    private func tryResourceForkMethod(iconFile: URL, dmgURL: URL, logger: @escaping (String) -> Void) async {
        // Methode: Versuche SetFile und Resource Forks (ältere Methode)
        do {
            // Zuerst den Resource Fork kopieren
            let copyResult = try await runProcess(
                launchPath: "/bin/cp",
                arguments: [iconFile.path + "/..namedfork/rsrc", dmgURL.path + "/..namedfork/rsrc"]
            )

            if copyResult.terminationStatus == 0 {
                logger("Resource Fork kopiert")

                // Setze das Custom Icon Bit mit SetFile
                let setFileResult = try await runProcess(
                    launchPath: "/usr/bin/SetFile",
                    arguments: ["-a", "C", dmgURL.path]
                )

                if setFileResult.terminationStatus == 0 {
                    logger("Custom Icon Bit gesetzt")

                    // Finder zum Aktualisieren zwingen
                    _ = try? await runProcess(launchPath: "/usr/bin/touch", arguments: [dmgURL.path])

                    // Teste ob das Icon wirklich gesetzt wurde
                    let testResult = try await runProcess(
                        launchPath: "/usr/bin/GetFileInfo",
                        arguments: [dmgURL.path]
                    )

                    if testResult.stdOut.contains("hasCustomIcon: 1") {
                        logger("DMG-Icon erfolgreich gesetzt (Resource Fork-Methode)")
                    } else {
                        logger("DMG-Icon setzen fehlgeschlagen - Custom Icon Bit nicht erkannt")
                    }
                } else {
                    let errorMsg = setFileResult.stdErr.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger("SetFile fehlgeschlagen: \(errorMsg)")
                }
            } else {
                let errorMsg = copyResult.stdErr.trimmingCharacters(in: .whitespacesAndNewlines)
                logger("Resource Fork kopieren fehlgeschlagen: \(errorMsg)")
            }
        } catch {
            logger("Resource Fork-Methode fehlgeschlagen: \(error.localizedDescription)")
        }

        logger("Alle Icon-Methoden versucht.")
    }

    func setVolumeIconOnRWDMG(_ appURL: URL, dmgURL: URL, password: String, logger: @escaping (String) -> Void) async {
        guard let iconFile = await findIconFileInApp(appURL) else {
            logger("Kein Icon für Volume gefunden")
            return
        }

        let mountPoint = await mountRWDMG(dmgURL, password: password, logger: logger)
        guard let mountPoint else { return }

        await setVolumeIcon(iconFile: iconFile, mountPoint: mountPoint, logger: logger)
        await unmountRWDMG(mountPoint, logger: logger)
    }

    private func mountRWDMG(_ dmgURL: URL, password: String, logger: @escaping (String) -> Void) async -> String? {
        var mountArgs = ["attach", dmgURL.path, "-nobrowse", "-noautoopen"]
        if !password.isEmpty { mountArgs += ["-stdinpass"] }

        let stdin = password.isEmpty ? nil : (password.data(using: .utf8) ?? Data())

        do {
            let mountResult = try await runProcess(
                launchPath: "/usr/bin/hdiutil",
                arguments: mountArgs,
                stdinData: stdin
            )

            if let mountPoint = parseFirstMountPoint(from: mountResult.stdOut) {
                logger("RW-DMG gemountet: \(mountPoint)")
                return mountPoint
            } else {
                logger("Kein Mount-Point gefunden in: \(mountResult.stdOut)")
                return nil
            }
        } catch {
            logger("Volume-Icon Mount fehlgeschlagen: \(error.localizedDescription)")
            return nil
        }
    }

    private func setVolumeIcon(iconFile: URL, mountPoint: String, logger: @escaping (String) -> Void) async {
        let volumeIconPath = URL(fileURLWithPath: mountPoint).appendingPathComponent(".VolumeIcon.icns")

        do {
            try FileManager.default.copyItem(at: iconFile, to: volumeIconPath)
            logger("Icon kopiert nach: \(volumeIconPath.path)")

            await setCustomIconBits(volumeIconPath: volumeIconPath, mountPoint: mountPoint, logger: logger)
            await setInvisibleBit(volumeIconPath: volumeIconPath, logger: logger)
        } catch {
            logger("Volume-Icon setzen fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func setCustomIconBits(volumeIconPath: URL, mountPoint: String, logger: @escaping (String) -> Void) async {
        let setFileResult = try? await runProcess(
            launchPath: "/usr/bin/SetFile",
            arguments: ["-a", "C", volumeIconPath.path]
        )
        if setFileResult?.terminationStatus == 0 {
            logger("Custom Icon Bit auf Volume-Icon gesetzt")
        } else {
            logger("SetFile auf Volume-Icon fehlgeschlagen: \(setFileResult?.stdErr ?? "")")
        }

        let setVolumeDirResult = try? await runProcess(
            launchPath: "/usr/bin/SetFile",
            arguments: ["-a", "C", mountPoint]
        )
        if setVolumeDirResult?.terminationStatus == 0 {
            logger("Custom Icon Bit auf Volume-Verzeichnis gesetzt")
        } else {
            logger("SetFile auf Volume-Verzeichnis fehlgeschlagen: \(setVolumeDirResult?.stdErr ?? "")")
        }
    }

    private func setInvisibleBit(volumeIconPath: URL, logger: @escaping (String) -> Void) async {
        let invisibleResult = try? await runProcess(
            launchPath: "/usr/bin/SetFile",
            arguments: ["-a", "V", volumeIconPath.path]
        )
        if invisibleResult?.terminationStatus == 0 {
            logger("Volume-Icon auf unsichtbar gesetzt")
        }
    }

    private func unmountRWDMG(_ mountPoint: String, logger: @escaping (String) -> Void) async {
        let detachResult = try? await runProcess(
            launchPath: "/usr/bin/hdiutil",
            arguments: ["detach", mountPoint]
        )
        if detachResult?.terminationStatus == 0 {
            logger("RW-DMG erfolgreich ausgehängt")
        } else {
            logger("Warnung: RW-DMG aushängen hatte Probleme: \(detachResult?.stdErr ?? "")")
        }
    }

    private func findIconFileInApp(_ appURL: URL) async -> URL? {
        let possibleIconPaths = [
            appURL.appendingPathComponent("Contents/Resources"),
            appURL.appendingPathComponent("Resources"),
            appURL.appendingPathComponent("Contents"),
        ]

        // Versuche Icon-Name aus Info.plist zu lesen
        let infoPlistPath = appURL.appendingPathComponent("Contents/Info.plist")
        if FileManager.default.fileExists(atPath: infoPlistPath.path) {
            do {
                let plistData = try Data(contentsOf: infoPlistPath)
                if let plist = try PropertyListSerialization.propertyList(
                    from: plistData, format: nil
                ) as? [String: Any],
                    let iconFileName = plist["CFBundleIconFile"] as? String
                {
                    for basePath in possibleIconPaths where FileManager.default.fileExists(atPath: basePath.path) {
                        let iconWithExt = basePath.appendingPathComponent(
                            iconFileName.hasSuffix(".icns") ? iconFileName : "\(iconFileName).icns"
                        )
                        if FileManager.default.fileExists(atPath: iconWithExt.path) {
                            return iconWithExt
                        }
                    }
                }
            } catch {}
        }

        // Fallback: Suche nach beliebiger .icns-Datei
        for iconPath in possibleIconPaths {
            guard FileManager.default.fileExists(atPath: iconPath.path) else { continue }
            do {
                let iconFiles = try FileManager.default.contentsOfDirectory(
                    at: iconPath,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                return iconFiles.first { $0.pathExtension.lowercased() == "icns" }
            } catch {}
        }

        return nil
    }

    func findAppInMountedDMG(_ mountPoint: String) async -> URL? {
        let fileManager = FileManager.default
        let mountURL = URL(fileURLWithPath: mountPoint)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: mountURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )

            for item in contents where item.pathExtension.lowercased() == "app" {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    return item
                }
            }
        } catch {
            // Error handling kann über logger success werden wenn nötig
        }

        return nil
    }
}
