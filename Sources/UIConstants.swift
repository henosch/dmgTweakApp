import SwiftUI

// ======================================================================

// MARK: - UI Konstanten

// ======================================================================

enum UIConstants {
    enum Width {
        static let label: CGFloat = 90
        static let value: CGFloat = 250
        static let pickerWide: CGFloat = 260
        static let pickerFS: CGFloat = 160
        static let pickerAccess: CGFloat = 220
        static let fieldShort: CGFloat = 220
        static let cardContent: CGFloat = 650
    }

    enum Spacing {
        static let row: CGFloat = 8
        static let rowTight: CGFloat = 6
        static let section: CGFloat = 12
        static let card: CGFloat = 12
        static let outer: CGFloat = 16
    }

    enum Popup {
        static let minHeight: CGFloat = 150
        static let idealHeight: CGFloat = 250
        static let maxHeight: CGFloat = 350
        static let minWidth: CGFloat = 500
        static let idealWidth: CGFloat = 600
        static let maxWidth: CGFloat = 800
    }

    enum Height {
        static let formBoxMin: CGFloat = 300
        static let overlayPadding: CGFloat = 24
    }

    enum Colors {
        static let cardBackground = Color(.controlBackgroundColor)
        static let sectionBackground = Color(.textBackgroundColor)
        static let accent = Color(.controlAccentColor)
        static let tabBackground = Color(.controlAccentColor)
        static let tabText = Color.white
        static let success = Color.green.opacity(0.8)
        static let warning = Color.orange.opacity(0.8)
        static let error = Color.red.opacity(0.8)
        static let info = Color.blue.opacity(0.7)
    }
}
