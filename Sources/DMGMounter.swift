import Foundation

// ======================================================================

// MARK: - DMG Mounter

// ======================================================================

actor DMGMounter {
    func attachDMG(_ dmgURL: URL?, password: String, logger: @escaping (String) -> Void) async {
        guard let url = dmgURL else {
            logger("❌ FEHLER: Keine DMG-Datei ausgewählt")
            return
        }

        var arguments = ["attach", url.path, "-nobrowse"]
        if !password.isEmpty { arguments += ["-stdinpass"] }

        let stdin = password.isEmpty ? nil : (password.data(using: .utf8) ?? Data())
        logger("$ hdiutil " + printableArguments(arguments))

        do {
            let result = try await runProcess(launchPath: "/usr/bin/hdiutil", arguments: arguments, stdinData: stdin)
            logger(result.stdOut.trimmingCharacters(in: .whitespacesAndNewlines))
            if !result.stdErr.isEmpty { logger(result.stdErr) }
            if let mountPoint = parseFirstMountPoint(from: result.stdOut) {
                logger("Gemountet: \(mountPoint)")
                _ = try? runProcessSync(launchPath: "/usr/bin/open", arguments: ["-R", mountPoint])
            }
        } catch {
            logger("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    private func printableArguments(_ arguments: [String]) -> String {
        arguments.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}
