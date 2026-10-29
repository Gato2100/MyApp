import Foundation

@main
struct LocalizationChecks {
    static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Pass the built .app path")
        let appPath = CommandLine.arguments[1]
        let expected = ["zh-Hans": "保存", "en": "Save", "ja": "保存"]
        for language in ["zh-Hans", "en", "ja"] {
            let bundle = Bundle(path: appPath + "/" + language + ".lproj")!
            for key in L10n.Key.allCases {
                let result = L10n.text(key, bundle: bundle)
                precondition(!result.isEmpty && result != key.rawValue, "Missing \(language): \(key)")
            }
            precondition(bundle.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist") != "NSCameraUsageDescription")
            precondition(L10n.text(.save, bundle: bundle) == expected[language])
            let formatted = L10n.format(.saveFailed, "TEST_DETAIL", bundle: bundle)
            precondition(formatted.contains("TEST_DETAIL") && !formatted.contains("%@"))
            precondition(bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist") == "CamerMemo")
        }
        let app = Bundle(path: appPath)!
        precondition(app.developmentLocalization == "zh-Hans")
        let fallback = Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["fr", "zh-Hans"])
        precondition(fallback.first == "zh-Hans")
        print("PASS: All keys in zh-Hans/en/ja, formatted errors, display name and language fallback")
    }
}
