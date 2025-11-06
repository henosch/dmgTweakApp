import SwiftUI

// ======================================================================

// MARK: - UI Components

// ======================================================================

struct HeaderCard: View {
    @Binding var category: ContentView.Category
    @Binding var password: String
    @Binding var passwordConfirm: String
    @FocusState var focusedField: ContentView.FocusTag?

    private var passwordStatusIcon: some View {
        Group {
            if password.isEmpty {
                Image(systemName: "lock.open")
                    .foregroundStyle(.orange)
                    .font(.title2)
            } else if passwordConfirm.isEmpty {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .foregroundStyle(.yellow)
                    .font(.title2)
            } else if password == passwordConfirm {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
            }
        }
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.row) {
            // Tabs
            HStack(spacing: 4) {
                ForEach(ContentView.Category.allCases) { cat in
                    ModernTab(
                        title: Localizer.t(cat.rawValue),
                        isActive: category == cat,
                        action: { category = cat }
                    )
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            // Passwort-Sektion
            VStack(alignment: .leading, spacing: 6) {
                Text(Localizer.t("Verschlüsselung"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SecureField(Localizer.t("Passwort (optional)"), text: $password)
                        .textFieldStyle(CompactTextFieldStyle())
                        .focused($focusedField, equals: .password)
                        .frame(maxWidth: .infinity)

                    SecureField(Localizer.t("Bestätigen"), text: $passwordConfirm)
                        .textFieldStyle(CompactTextFieldStyle())
                        .focused($focusedField, equals: .passwordConfirm)
                        .frame(maxWidth: .infinity)
                        .disabled(password.isEmpty)
                        .opacity(password.isEmpty ? 0.5 : 1.0)

                    passwordStatusIcon
                }
            }
        }
        .padding(UIConstants.Spacing.card)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
    }
}

struct ModernTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: title == Localizer.t("Erstellen") ? "plus.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .primary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [UIConstants.Colors.accent, UIConstants.Colors.accent.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isActive)
    }
}

struct ContentCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: UIConstants.Width.cardContent)
            .frame(minHeight: 380)
            .padding(UIConstants.Spacing.card)
            .background(UIConstants.Colors.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct FooterCard: View {
    let logText: String
    @Binding var logExpanded: Bool

    struct StatusMessage {
        let text: String
        let color: Color
        let icon: String
    }

    private var statusMessage: StatusMessage {
        let lower = logText.lowercased()
        if logText.isEmpty {
            return StatusMessage(text: Localizer.t("Bereit"), color: .secondary, icon: "checkmark.circle")
        } else if logText.contains("❌") || lower.contains("fehler") || lower.contains("error") ||
            (lower.contains("failed") && !lower.contains("volume-icon"))
        {
            return StatusMessage(text: Localizer.t("Fehler aufgetreten"), color: .red, icon: "exclamationmark.triangle.fill")
        } else if logText.contains("✅") || lower.contains("fertig") || lower.contains("done") ||
            lower.contains("abgeschlossen") || lower.contains("completed") || lower.contains("created:")
        {
            return StatusMessage(text: Localizer.t("Erfolgreich abgeschlossen"), color: .green, icon: "checkmark.circle.fill")
        } else if logText.contains("$") || lower.contains("erstelle") || lower.contains("creating") || lower.contains("konvertiere") || lower.contains("converting") {
            return StatusMessage(text: Localizer.t("Verarbeitung läuft..."), color: .blue, icon: "gear")
        } else {
            return StatusMessage(text: Localizer.t("Status unbekannt"), color: .orange, icon: "questionmark.circle")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusMessage.icon)
                .foregroundStyle(statusMessage.color)
                .font(.system(size: 14, weight: .medium))

            Text(statusMessage.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusMessage.color)

            Spacer()

            if statusMessage.color == .red {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        logExpanded = true
                    }
                } label: {
                    Label("Details anzeigen", systemImage: "info.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, UIConstants.Spacing.card)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .popover(isPresented: $logExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            LogViewer(logText: logText)
        }
    }
}

struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.rowTight) {
            HStack {
                Image(systemName: iconForSection(title))
                    .foregroundStyle(colorForSection(title))
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            content
                .padding(.leading, 4)
        }
        .padding(UIConstants.Spacing.row)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorForSection(title).opacity(0.2), lineWidth: 0.5)
        )
    }

    private func iconForSection(_ title: String) -> String {
        switch title {
        case Localizer.t("Modus"): "gear"
        case Localizer.t("Quelle"), Localizer.t("Konfiguration"): "folder"
        case Localizer.t("Einstellungen"): "slider.horizontal.3"
        case Localizer.t("Konvertierung"): "arrow.triangle.2.circlepath"
        case Localizer.t("Dateien"): "doc"
        case Localizer.t("Optionen"): "paintbrush"
        default: "info.circle"
        }
    }

    private func colorForSection(_ title: String) -> Color {
        switch title {
        case Localizer.t("Modus"): .blue
        case Localizer.t("Quelle"), Localizer.t("Konfiguration"): .green
        case Localizer.t("Einstellungen"): .orange
        case Localizer.t("Konvertierung"): .purple
        case Localizer.t("Dateien"): .red
        case Localizer.t("Optionen"): .pink
        default: .gray
        }
    }
}

struct FilePickerRow: View {
    let label: String
    let path: String?
    let buttonTitle: String
    let action: () -> Void
    struct AdditionalButton {
        let title: String
        let action: () -> Void
        let isEnabled: Bool
    }

    let additionalButton: AdditionalButton?

    init(label: String, path: String?, buttonTitle: String, action: @escaping () -> Void,
         additionalButton: AdditionalButton? = nil)
    {
        self.label = label
        self.path = path
        self.buttonTitle = buttonTitle
        self.action = action
        self.additionalButton = additionalButton
    }

    var body: some View {
        HStack(spacing: UIConstants.Spacing.rowTight) {
            Text(label)
                .frame(width: UIConstants.Width.label, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(path ?? Localizer.t("— nicht gewählt —"))
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.callout)
                .foregroundStyle(path != nil ? .primary : .secondary)
                .frame(width: UIConstants.Width.value, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Spacer()

            HStack(spacing: 8) {
                Button(buttonTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())

                if let button = additionalButton {
                    Button(button.title, action: button.action)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!button.isEnabled)
                }
            }
        }
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: UIConstants.Spacing.rowTight) {
            Text(label)
                .frame(width: UIConstants.Width.label, alignment: .leading)
                .foregroundStyle(.secondary)
            content
            Spacer()
        }
    }
}

struct InfoHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LogViewer: View {
    let logText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Localizer.t("Ausgabe"), systemImage: "terminal")
                    .font(.headline)
                Spacer()
            }

            ScrollView {
                ScrollViewReader { proxy in
                    Text(logText.isEmpty ? "— Keine Ausgabe —" : logText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logBottom")
                        .onChange(of: logText) { _ in
                            withAnimation {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                }
            }
            .frame(minHeight: UIConstants.Popup.minHeight,
                   idealHeight: UIConstants.Popup.idealHeight,
                   maxHeight: UIConstants.Popup.maxHeight)
            .frame(minWidth: UIConstants.Popup.minWidth,
                   idealWidth: UIConstants.Popup.idealWidth,
                   maxWidth: UIConstants.Popup.maxWidth)
        }
        .padding(UIConstants.Spacing.card)
    }
}
