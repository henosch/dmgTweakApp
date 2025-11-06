import Foundation

// ======================================================================

// MARK: - Mount Management

// ======================================================================

struct HdiutilMountedEntry {
    let imagePath: String
    let deviceEntries: [String]
    let mountPoints: [String]
}

func normalizedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
}

func readMountedEntries() async -> [HdiutilMountedEntry] {
    let info = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: ["info", "-plist"])
    guard let plistData = info?.stdOut.data(using: .utf8), plistData.count > 0 else { return [] }

    let conversion = try? await runProcess(
        launchPath: "/usr/bin/plutil",
        arguments: ["-convert", "json", "-o", "-", "-"],
        stdinData: plistData
    )
    guard let jsonData = conversion?.stdOut.data(using: .utf8), jsonData.count > 0 else { return [] }
    guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let images = root["images"] as? [[String: Any]] else { return [] }

    var result: [HdiutilMountedEntry] = []
    for image in images {
        guard let imagePath = (image["image-path"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty else { continue }
        var devices: [String] = []
        var mounts: [String] = []
        if let entities = image["system-entities"] as? [[String: Any]] {
            for entity in entities {
                if let device = entity["dev-entry"] as? String, device.hasPrefix("/dev/") {
                    devices.append(device)
                }
                if let mount = entity["mount-point"] as? String, mount.hasPrefix("/") {
                    mounts.append(mount)
                }
            }
        }
        result.append(HdiutilMountedEntry(imagePath: imagePath, deviceEntries: devices, mountPoints: mounts))
    }
    return result
}

func findMountedEntries(for image: URL) async -> HdiutilMountedEntry? {
    let wanted = normalizedPath(image)
    return await readMountedEntries().first { entry in
        entry.imagePath.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

@discardableResult
func detachAll(devices: [String], mounts: [String], force: Bool = false) async -> Bool {
    for mountPoint in mounts {
        let args = force ? ["detach", "-force", mountPoint] : ["detach", mountPoint]
        _ = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: args)
    }
    for device in devices.reversed() {
        let args = force ? ["detach", "-force", device] : ["detach", device]
        _ = try? await runProcess(launchPath: "/usr/bin/hdiutil", arguments: args)
    }
    let remaining = await readMountedEntries().flatMap(\.deviceEntries)
    return !devices.allSatisfy { !remaining.contains($0) }
}

@discardableResult
func ensureDetached(image: URL, logger: @escaping (String) -> Void) async -> Bool {
    let maxAttempts = 3
    for attempt in 1 ... maxAttempts {
        if let entry = await findMountedEntries(for: image),
           !entry.deviceEntries.isEmpty || !entry.mountPoints.isEmpty
        {
            logger("Aushängen (Versuch \(attempt)/\(maxAttempts)) …")
            let success = await detachAll(
                devices: entry.deviceEntries,
                mounts: entry.mountPoints,
                force: attempt == maxAttempts
            )
            if success {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if await findMountedEntries(for: image) == nil {
                    logger("Erfolgreich ausgehängt.")
                    return true
                }
            }
        } else {
            return true
        }
    }
    logger("Konnte nicht vollständig aushängen.")
    return false
}

func parseFirstMountPoint(from stdout: String) -> String? {
    let lines = stdout.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n")
    for line in lines {
        if let range = line.range(of: "/Volumes/") {
            return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}
