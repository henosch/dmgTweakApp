import Foundation

// ======================================================================

// MARK: - DMG Icon Operations

// ======================================================================

actor DMGIconOperations {
    private let iconHandler = IconHandler()

    struct RWToROConversionOptions {
        let sourceURL: URL
        let destinationURL: URL
        let appIconURL: URL
        let tempMountPoint: String?
        let password: String
        let logger: (String) -> Void
    }

    func performRWToROWithIcon(options: RWToROConversionOptions) async {
        let tempRwURL = await createTemporaryRWDMG(options: options)
        guard let tempRwURL else { return }

        await processRWDMGWithIcon(tempRwURL: tempRwURL, options: options)
    }

    private func createTemporaryRWDMG(options: RWToROConversionOptions) async -> URL? {
        let stdin = options.password.isEmpty ? nil : (options.password.data(using: .utf8) ?? Data())
        options.logger("Erstelle temporäres RW-DMG für Volume-Icon...")

        let tempRwPath = NSTemporaryDirectory() + "temp_rw_\(UUID().uuidString).dmg"
        let tempRwURL = URL(fileURLWithPath: tempRwPath)

        var tempArgs = ["convert", options.sourceURL.path, "-format", "UDRW", "-o", tempRwPath]
        if !options.password.isEmpty { tempArgs += ["-stdinpass"] }

        do {
            let tempResult = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: tempArgs, stdinData: stdin)
            if tempResult.terminationStatus != 0 {
                options.logger("❌ FEHLER: Temporäres RW-DMG fehlgeschlagen: \(tempResult.stdErr)")
                try? FileManager.default.removeItem(at: tempRwURL)
                return nil
            }
            return tempRwURL
        } catch {
            options.logger("❌ FEHLER: Temporäres RW-DMG: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempRwURL)
            return nil
        }
    }

    private func processRWDMGWithIcon(tempRwURL: URL, options: RWToROConversionOptions) async {
        let stdin = options.password.isEmpty ? nil : (options.password.data(using: .utf8) ?? Data())

        options.logger("Setze Volume-Icon auf temporärem RW-DMG...")
        await iconHandler.setVolumeIconOnRWDMG(
            options.appIconURL,
            dmgURL: tempRwURL,
            password: options.password,
            logger: options.logger
        )

        await convertRWToROWithIcon(tempRwURL: tempRwURL, options: options, stdin: stdin)

        if let mountPoint = options.tempMountPoint {
            _ = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: ["detach", mountPoint])
            options.logger("Temporärer Mount entfernt")
        }

        try? FileManager.default.removeItem(at: tempRwURL)
    }

    private func convertRWToROWithIcon(tempRwURL: URL, options: RWToROConversionOptions, stdin: Data?) async {
        let finalArgs = [
            "convert", tempRwURL.path, "-format", "UDZO", "-o", options.destinationURL.path, "-imagekey", "zlib-level=9"
        ]

        options.logger("$ hdiutil " + printableArguments(finalArgs))

        do {
            let finalResult = try await runProcess(
                launchPath: "/usr/bin/hdiutil",
                arguments: finalArgs,
                stdinData: stdin
            )

            if !finalResult.stdOut.isEmpty { options.logger(finalResult.stdOut) }
            if !finalResult.stdErr.isEmpty { options.logger(finalResult.stdErr) }

            try? FileManager.default.removeItem(at: tempRwURL)
            options.logger("Temporäre RW-Datei gelöscht")

            if finalResult.terminationStatus == 0 {
                await finalizeDMGWithIcons(options: options)
            } else {
                options.logger("❌ FEHLER: Finale Konvertierung fehlgeschlagen (Code: \(finalResult.terminationStatus))")
            }
        } catch {
            options.logger("❌ FEHLER: Finale Konvertierung: \(error.localizedDescription)")
        }
    }

    private func finalizeDMGWithIcons(options: RWToROConversionOptions) async {
        options.logger("Konvertierung mit Volume-Icon abgeschlossen: \(options.destinationURL.path)")

        options.logger("Setze DMG-Icon...")
        await iconHandler.setDMGIconFromApp(
            options.appIconURL,
            dmgURL: options.destinationURL,
            logger: options.logger
        )

        if FileManager.default.fileExists(atPath: options.appIconURL.path) {
            try? FileManager.default.removeItem(at: options.appIconURL)
            options.logger("Temporäre .app-Kopie gelöscht: \(options.appIconURL.lastPathComponent)")
        }

        options.logger("✅ FERTIG: DMG mit Volume-Icon und DMG-Icon erstellt")
    }

    private func printableArguments(_ arguments: [String]) -> String {
        arguments.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}
