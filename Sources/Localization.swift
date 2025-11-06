import Foundation

enum Localizer {
    static func t(_ key: String) -> String {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle.main
        #endif
        return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: "")
    }
}
