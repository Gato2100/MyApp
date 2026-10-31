import Foundation

/// 读取构建产物中的语言资源，检查所有 key、格式化占位符、权限文案和回退语言。
@main
struct LocalizationChecks {
    static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Pass the built .app path")
        // 参数必须指向已构建的 App；检查编译后的 .lproj，而不是只检查源 JSON。
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
        // 首选法语不可用时，确认后续的简体中文偏好可以作为资源回退。
        let fallback = Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["fr", "zh-Hans"])
        precondition(fallback.first == "zh-Hans")
        print("PASS: All keys in zh-Hans/en/ja, formatted errors, display name and language fallback")
    }
}
