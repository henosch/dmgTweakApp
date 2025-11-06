import AppKit
import UniformTypeIdentifiers

// ======================================================================

// MARK: - File Picker Manager

// ======================================================================

enum FilePickerManager {
    static func pickSourceFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = Localizer.t("Quellordner für DMG auswählen")
        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    static func pickOutputDMG(suggestedName: String? = nil, initialDirectory: URL? = nil) -> URL? {
        let savePanel = NSSavePanel()
        if let dmg = UTType(filenameExtension: "dmg") {
            savePanel.allowedContentTypes = [dmg]
        } else {
            savePanel.allowedContentTypes = [UTType.diskImage]
        }
        savePanel.canCreateDirectories = true
        if let dir = initialDirectory {
            savePanel.directoryURL = dir
        }
        if let name = suggestedName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let finalName = name.lowercased().hasSuffix(".dmg") ? name : name + ".dmg"
            savePanel.nameFieldStringValue = finalName
        } else {
            savePanel.nameFieldStringValue = "Image.dmg"
        }
        savePanel.title = Localizer.t("DMG speichern als")
        // Disable the automatic "file exists" dialog completely
        savePanel.prompt = "Speichern"

        return savePanel.runModal() == .OK ? savePanel.url : nil
    }

    static func pickConvertSource() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [UTType.diskImage]
        openPanel.title = Localizer.t("Quell-DMG auswählen")
        return openPanel.runModal() == .OK ? openPanel.urls.first : nil
    }

    static func pickConvertDest(direction: DMGDirection) -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.diskImage]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = (direction == .rwToRo) ? "Compressed.dmg" : "ReadWrite.dmg"
        savePanel.title = Localizer.t("Ziel-DMG speichern als")
        return savePanel.runModal() == .OK ? savePanel.url : nil
    }

    static func displayPath(_ path: String?) -> String? {
        guard let fullPath = path, !fullPath.isEmpty else { return path }
        let homeDirectory = NSHomeDirectory()
        if fullPath.hasPrefix(homeDirectory) {
            return "~" + fullPath.dropFirst(homeDirectory.count)
        }
        return path
    }
}
