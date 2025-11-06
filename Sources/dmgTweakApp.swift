import AppKit
import SwiftUI
import UniformTypeIdentifiers

// ======================================================================

// MARK: - App

// ======================================================================
@main
struct EncryptedDMGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 680, idealWidth: 680, maxWidth: 680,
                       minHeight: 620, idealHeight: 620, maxHeight: 620)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(Localizer.t("Über dmgTweak")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(replacing: .help) {
                Button(Localizer.t("Über dmgTweak")) {
                    // About dialog could be shown here
                }
                .keyboardShortcut("?")
            }
            CommandGroup(replacing: .appTermination) {
                Button(Localizer.t("dmgTweak beenden")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

// ======================================================================

// MARK: - ContentView

// ======================================================================
struct ContentView: View {
    enum Category: String, CaseIterable, Identifiable {
        case create = "Erstellen"
        case convert = "Konvertieren"
        var id: String { rawValue }
    }

    enum FocusTag: Hashable {
        case password, passwordConfirm
    }

    // Global State
    @State private var category: Category = .create
    @State private var password = "" {
        didSet {
            // Clear confirmation when password is cleared
            if password.isEmpty {
                passwordConfirm = ""
            }
        }
    }

    @State private var passwordConfirm = ""
    @FocusState private var focusedField: FocusTag?
    @State private var logText: String = ""
    @State private var logExpanded = false
    @State private var isBusy = false
    @State private var showConvertOverwriteAlert = false
    // ----- Erstellen -----
    @State private var createMode: DMGCreateMode = .fromFolder
    @State private var sourceFolder: URL?
    @State private var emptySize = "100m"
    @State private var volumeName = "Image"
    @State private var fileSystem: DMGFileSystem = .apfs
    @State private var access: DMGAccess = .readOnly
    @State private var outDMG: URL?
    private var outDMGExists: Bool {
        guard let url = outDMG else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func clearCreateSettings() {
        sourceFolder = nil
        outDMG = nil
        emptySize = "100m"
        volumeName = "Untitled"
        fileSystem = .apfs
        access = .readOnly
    }

    // ----- Konvertieren -----
    @State private var direction: DMGDirection = .rwToRo

    @State private var convertSrc: URL?
    @State private var convertDst: URL?
    @State private var useAppIcon = false
    private var convertDstExists: Bool {
        guard let url = convertDst else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var passwordsMatch: Bool {
        password.isEmpty || (password == passwordConfirm && !passwordConfirm.isEmpty)
    }

    // DMG Operations Actor
    private let dmgOperations = DMGOperations()
    private let dmgMounter = DMGMounter()
    var body: some View {
        VStack(spacing: UIConstants.Spacing.outer) {
            HeaderCard(
                category: $category,
                password: $password,
                passwordConfirm: $passwordConfirm,
                focusedField: _focusedField
            )
            ContentCard {
                if category == .create {
                    createView
                } else {
                    convertView
                }
            }
            FooterCard(
                logText: logText,
                logExpanded: $logExpanded
            )
        }
        // Beim Wechsel zwischen "Aus Ordner" und "Leeres Image" Eingaben leeren
        .onChange(of: createMode) { newMode in
            outDMG = nil
            sourceFolder = nil
            volumeName = "Image"
            if newMode == .empty { emptySize = "100m" }
        }
        // Beim Wechsel zwischen RW→RO und RO→RW Eingaben leeren
        .onChange(of: direction) { _ in
            convertSrc = nil
            convertDst = nil
        }
        .padding(UIConstants.Spacing.outer)
        .background(Color(.windowBackgroundColor))
        .alert(Localizer.t("Zieldatei bereits vorhanden"), isPresented: $showConvertOverwriteAlert) {
            Button(Localizer.t("Abbrechen"), role: .cancel) {}
            Button(Localizer.t("Überschreiben"), role: .destructive) {
                Task {
                    if let src = convertSrc, let dst = convertDst {
                        try? FileManager.default.removeItem(at: dst)
                        await performConversion(src: src, dst: dst)
                    }
                }
            }
        } message: {
            Text(Localizer.t("Die Zieldatei existiert bereits. Möchten Sie sie überschreiben?"))
        }
    }

    // MARK: - Views

    private var createView: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.section) {
            FormSection(Localizer.t("Modus")) {
                HStack(alignment: .top, spacing: UIConstants.Spacing.row) {
                    Picker("", selection: $createMode) {
                        ForEach(DMGCreateMode.allCases) {
                            Label(Localizer.t($0.rawValue), systemImage: $0 == .fromFolder ? "folder" : "doc.badge.plus").tag($0)
                        }
                    }.pickerStyle(.segmented).frame(width: UIConstants.Width.pickerWide)
                    InfoHint(createMode == .fromFolder ? Localizer.t("Erstellt DMG aus Ordner") : Localizer.t("Erstellt leeres DMG"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            FormSection(createMode == .fromFolder ? Localizer.t("Quelle") : Localizer.t("Konfiguration")) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.row) {
                    if createMode == .fromFolder {
                        FilePickerRow(
                            label: Localizer.t("Ordner:"),
                            path: displayPath(sourceFolder?.path),
                            buttonTitle: Localizer.t("Ordner wählen"),
                            action: pickSourceFolder
                        )
                    } else {
                        HStack(spacing: UIConstants.Spacing.rowTight) {
                            Text(Localizer.t("Größe:"))
                                .frame(width: UIConstants.Width.label, alignment: .leading)
                                .foregroundStyle(.secondary)
                            TextField("200m, 1g, etc.", text: $emptySize)
                                .textFieldStyle(ModernTextFieldStyle())
                                .frame(width: UIConstants.Width.value)
                        }
                        InfoHint(Localizer.t("Beispiele: 200m = 200 MB, 1g = 1 GB"))
                    }
                    HStack(spacing: UIConstants.Spacing.rowTight) {
                        Text(Localizer.t("Volume:"))
                            .frame(width: UIConstants.Width.label, alignment: .leading)
                            .foregroundStyle(.secondary)
                        TextField(Localizer.t("Volume Name"), text: $volumeName)
                            .textFieldStyle(ModernTextFieldStyle())
                            .frame(width: UIConstants.Width.fieldShort)
                    }
                }
            }
            FormSection(Localizer.t("Einstellungen")) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.rowTight) {
                    HStack(alignment: .top, spacing: UIConstants.Spacing.row) {
                        SettingRow(label: Localizer.t("Dateisystem:")) {
                            Picker("", selection: $fileSystem) {
                                ForEach(DMGFileSystem.allCases) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: UIConstants.Width.pickerFS)
                        }
                        InfoHint(fileSystem == .apfs ? Localizer.t("APFS: Moderner Standard") : Localizer.t("HFS+J: Kompatibilität"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if createMode == .fromFolder {
                        HStack(alignment: .top, spacing: UIConstants.Spacing.row) {
                            SettingRow(label: Localizer.t("Modus:")) {
                                Picker("", selection: $access) {
                                    ForEach(DMGAccess.allCases) {
                                        Text($0.rawValue).tag($0)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: UIConstants.Width.pickerAccess)
                            }
                            InfoHint(access == .readWrite ? Localizer.t("RW: Beschreibbar") : Localizer.t("RO: Komprimiert"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Spacer()
            HStack {
                Spacer()
                HStack(spacing: UIConstants.Spacing.row) {
                    Button { Task { await createDMG() } } label: {
                        Label(isBusy ? Localizer.t("Erstelle…") : Localizer.t("DMG erstellen"), systemImage: isBusy ? "gear" : "plus.circle.fill")
                    }.buttonStyle(PrimaryButtonStyle()).disabled(isBusy)
                    if outDMGExists {
                        Button { Task { await attachSelected(outDMG) } } label: {
                            Label(Localizer.t("Mounten"), systemImage: "externaldrive.badge.plus")
                        }.buttonStyle(SecondaryButtonStyle()).disabled(isBusy)
                    }
                    Button { withAnimation(.easeInOut(duration: 0.3)) { logExpanded.toggle() } } label: {
                        Label(Localizer.t("Ausgabe anzeigen"), systemImage: "terminal")
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }.padding(.top, UIConstants.Spacing.row)
        }
    }

    // Kein eigener Überschreiben-Dialog beim Erstellen (SavePanel übernimmt Bestätigung)

    private var convertView: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.section) {
            FormSection(Localizer.t("Konvertierung")) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.row) {
                    Picker("", selection: $direction) {
                        ForEach(DMGDirection.allCases) {
                            Label(
                                $0.rawValue,
                                systemImage: $0 == .rwToRo ? "arrow.down.circle" : "arrow.up.circle"
                            ).tag($0)
                        }
                    }.pickerStyle(.segmented).frame(width: UIConstants.Width.pickerWide)
                    InfoHint(
                        direction == .rwToRo
                            ? Localizer.t("Konvertiert zu schreibgeschützt & komprimiert")
                            : Localizer.t("Konvertiert zu beschreibbar")
                    )
                }
            }
            FormSection(Localizer.t("Dateien")) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.row) {
                    FilePickerRow(
                        label: Localizer.t("Quelle:"),
                        path: displayPath(convertSrc?.path),
                        buttonTitle: Localizer.t("DMG wählen"),
                        action: pickConvertSource,
                        additionalButton: .init(
                            title: Localizer.t("Mounten"),
                            action: { Task { await attachSelected(convertSrc) } },
                            isEnabled: convertSrc != nil && !isBusy
                        )
                    )
                    FilePickerRow(
                        label: Localizer.t("Ziel:"),
                        path: displayPath(convertDst?.path),
                        buttonTitle: Localizer.t("Speichern als"),
                        action: pickConvertDest,
                        additionalButton: .init(
                            title: Localizer.t("Mounten"),
                            action: { Task { await attachSelected(convertDst) } },
                            isEnabled: convertDstExists && !isBusy
                        )
                    )
                }
            }
            if direction == .rwToRo {
                FormSection(Localizer.t("Optionen")) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.row) {
                        Toggle(isOn: $useAppIcon) { Label(Localizer.t(".app als DMG-Icon verwenden"), systemImage: "app.badge") }
                            .toggleStyle(ModernToggleStyle())
                        InfoHint(Localizer.t("Sucht automatisch nach .app-Dateien und verwendet deren Icon"))
                    }
                }
            }
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: UIConstants.Spacing.row) {
                    Button { Task { await doConversion() } } label: {
                        let text = isBusy
                            ? Localizer.t("Konvertiere…")
                            : (direction == .rwToRo ? Localizer.t("In RO konvertieren") : Localizer.t("In RW konvertieren"))
                        let icon = isBusy ? "gear" : "arrow.triangle.2.circlepath"
                        Label(text, systemImage: icon)
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!(convertSrc != nil && convertDst != nil) || isBusy)
                    Button { withAnimation(.easeInOut(duration: 0.3)) { logExpanded.toggle() } } label: {
                        Label(Localizer.t("Ausgabe anzeigen"), systemImage: "terminal")
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }.padding(.top, UIConstants.Spacing.row)
        }
    }

    // MARK: - Actions

    private func validateConversionInputs() -> Bool {
        if !password.isEmpty, !passwordsMatch {
            logText = ""
            append("Fehler: Passwörter stimmen nicht überein")
            return false
        }
        return true
    }

    func createDMG() async {
        // Validate inputs
        guard validateConversionInputs() else { return }
        // Immer via SavePanel Ziel wählen (mit Volume-Namen als Vorschlag)
        // Standard-Verzeichnis: Downloads (für beide Modi)
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        outDMG = FilePickerManager.pickOutputDMG(suggestedName: volumeName, initialDirectory: downloadsDir)
        guard let output = outDMG else { return }
        // NSSavePanel already handled file replacement confirmation
        // Just delete if exists since user already confirmed via SavePanel
        if FileManager.default.fileExists(atPath: output.path) {
            try? FileManager.default.removeItem(at: output)
        }
        // Create DMG
        isBusy = true
        logText = ""
        openLog()
        defer { isBusy = false }
        // Use the volume name from the UI text field
        await createDMGWithHdiutil(output: output, volumeName: volumeName)
    }

    private func createDMGWithHdiutil(output: URL, volumeName: String) async {
        var args: [String] = []
        switch createMode {
        case .fromFolder:
            guard let source = sourceFolder else {
                append("❌ FEHLER: Quellordner nicht ausgewählt")
                return
            }
            args = [
                "create", "-volname", volumeName,
                "-fs", fileSystem.argument,
                "-format", access.format,
                "-srcfolder", source.path,
                output.path,
            ]
        case .empty:
            let size = emptySize.trimmingCharacters(in: .whitespacesAndNewlines)
            // Simple size validation
            let sizeRegex = #"^\d+(\.\d+)?[kmgtKMGT]?$"#
            guard size.range(of: sizeRegex, options: .regularExpression) != nil else {
                append("❌ FEHLER: Ungültige Größe (Beispiele: 200m, 1g)")
                return
            }
            args = [
                "create", "-size", size,
                "-fs", fileSystem.argument,
                "-volname", volumeName,
                output.path,
            ]
        }
        // Add encryption if password is set
        if !password.isEmpty {
            args.insert("-encryption", at: 1)
            args.insert("AES-256", at: 2)
            args.insert("-stdinpass", at: 3)
        }

        // Log command
        let printableArgs = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        append("$ hdiutil \(printableArgs)")

        do {
            let stdin = password.isEmpty ? nil : password.data(using: .utf8)
            let result = try await runProcess(
                launchPath: "/usr/bin/hdiutil",
                arguments: args,
                stdinData: stdin
            )

            if !result.stdOut.isEmpty {
                append(result.stdOut)
            }
            if !result.stdErr.isEmpty {
                append(result.stdErr)
            }

            if result.terminationStatus == 0 {
                append("✅ FERTIG: \(output.path)")
                outDMG = nil
                if createMode == .fromFolder { sourceFolder = nil }
            } else {
                append("❌ FEHLER: Fehlercode \(result.terminationStatus)")
            }
        } catch {
            append("❌ FEHLER: \(error.localizedDescription)")
        }
    }

    func attachSelected(_ dmgURL: URL?) async {
        await dmgMounter.attachDMG(dmgURL, password: password, logger: { message in
            Task { @MainActor in append(message) }
        })
    }

    func doConversion() async {
        guard validateConversionInputs() else { return }
        guard let src = convertSrc, let dst = convertDst else { return }

        if FileManager.default.fileExists(atPath: dst.path) {
            showConvertOverwriteAlert = true
            return
        }

        await performConversion(src: src, dst: dst)
    }

    private func performConversion(src: URL, dst: URL) async {
        isBusy = true; logText = ""; openLog(); defer { isBusy = false }
        await dmgOperations.convertDMG(options: .init(
            sourceURL: src,
            destinationURL: dst,
            direction: direction,
            useAppIcon: useAppIcon,
            password: password,
            logger: { message in
                Task { @MainActor in
                    append(message)
                    if message.contains("✅ FERTIG") {
                        resetConvertPaths()
                    }
                }
            }
        ))
    }

    private func pickSourceFolder() { sourceFolder = FilePickerManager.pickSourceFolder() }
    private func pickOutputDMG() -> URL? { FilePickerManager.pickOutputDMG() }
    private func pickConvertSource() {
        convertSrc = FilePickerManager.pickConvertSource()
        if let source = convertSrc, convertDst == nil {
            let baseName = source.deletingPathExtension()
            convertDst = direction == .rwToRo
                ? baseName.appendingPathExtension("udzo.dmg")
                : baseName.appendingPathExtension("udrw.dmg")
        }
    }

    private func pickConvertDest() { convertDst = FilePickerManager.pickConvertDest(direction: direction) }
    private func displayPath(_ path: String?) -> String? { FilePickerManager.displayPath(path) }
    private func resetConvertPaths() { convertSrc = nil; convertDst = nil }
    @MainActor private func append(_ message: String) {
        let localized = localizeLogIfNeeded(message)
        logText += (logText.isEmpty ? "" : "\n") + localized
        withAnimation { logExpanded = true }
    }

    private func openLog() { withAnimation { logExpanded = true } }

    private func localizeLogIfNeeded(_ message: String) -> String {
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        let prefersEN = (langs?.first?.hasPrefix("en") ?? false) || Bundle.main.preferredLocalizations.first == "en"
        guard prefersEN else { return message }
        var s = message
        let map: [(String, String)] = [
            ("✅ FERTIG:", "✅ DONE:"),
            ("❌ FEHLER:", "❌ ERROR:"),
            ("Konvertierung abgeschlossen:", "Conversion completed:"),
            ("Erstelle", "Creating"),
            ("Konvertiere", "Converting"),
            ("Existierende Datei entfernt:", "Removed existing file:"),
            ("Prüfe Mounts für:", "Checking mounts for:"),
            ("Quelle belegt", "Source busy"),
            ("Temporär gemountet:", "Temporarily mounted:"),
            ("Mount-Point nicht verfügbar:", "Mount point not available:"),
            ("Warnung:", "Warning:"),
            ("Temporärer Mount erfolgreich entfernt", "Temporary mount removed"),
            ("Verbleibende temporäre Datei gelöscht", "Deleted remaining temp file"),
            ("Ungültige Größe", "Invalid size"),
            ("Quellordner nicht ausgewählt", "Source folder not selected"),
            ("Konnte existierende Datei nicht entfernen:", "Could not remove existing file:"),
            ("Fehlercode", "Exit code"),
            ("Fehler beim temporären Mounten:", "Error while temporary mounting:"),
            ("Keine .app-Datei im DMG gefunden", "No .app file found in DMG"),
            ("Setze DMG-Icon", "Setting DMG icon"),
        ]
        for (de, en) in map {
            s = s.replacingOccurrences(of: de, with: en)
        }
        return s
    }
}
