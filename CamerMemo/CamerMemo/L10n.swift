import Foundation

/// 资源遵循系统的 App 首选语言，未匹配时回退到开发语言简体中文。
/// 本地化访问入口；翻译正文统一维护在 Localizable.xcstrings，技术标识不参与翻译。
enum L10n {
    /// 用枚举约束资源 key；新增界面文案时需同步补齐资源文件中的各语言条目。
    enum Key: String, CaseIterable {
        case createdTime
        case updatedTime
        case selectMemos
        case finishSelection
        case selectAllMemos
        case deselectAllMemos
        case selectedMemoCount
        case deleteSelectedMemos
        case confirmDeleteMemos
        case deleteMemos
        case deleteMemosWarning
        case deleteMemosFailed
        case dismissDeleteError
        case tagsTitle
        case tagInputPlaceholder
        case addTag
        case removeTag
        case tagTooLong
        case tagSuggestionHelp
        case tagGenerating
        case tagSelected
        case tagNotSelected
        case regenerateTags
        case cancelTagGeneration
        case tagGenerationFailed
        case tagNoSuggestions
        case tagAIRequiresSystem
        case tagAIDeviceUnsupported
        case tagAINotEnabled
        case tagAIModelNotReady
        case tagAIUnavailable
        case tagSearchPrompt
        case searchAll
        case searchTagsOnly
        case appName
        case privacyCovered
        case unlockHeading
        case createHeading
        case password
        case confirmPassword
        case unlock
        case createVault
        case verifying
        case unlockHelp
        case createHelp
        case passwordTooShort
        case passwordMismatch
        case emptyMemos
        case noResults
        case emptyHelp
        case searchHelp
        case memos
        case searchPrompt
        case lock
        case newText
        case edit
        case titlePlaceholder
        case titleAccessibility
        case body
        case saveHelp
        case editMemo
        case newMemo
        case cancel
        case save
        case discardQuestion
        case discard
        case keepEditing
        case emptyChangesNotice
        case saveFailed
        case backgroundSaveFailed
        case untitled
        case invalidFile
        case cannotUnlock
        case cryptoFailure
        case invalidContent
        case storageFailure
        case enterPhotoTextManually
        case attachmentTitle
        case viewFullImage
        case closeImage
        case imageZoomHelp
        case photoMemoTitle
        case takePhoto
        case choosePhoto
        case photoPrivacyHelp
        case chooseAnotherPhoto
        case recognitionLanguage
        case languageAutomatic
        case languageChinese
        case languageJapanese
        case languageEnglish
        case selectedPhoto
        case recognizingText
        case loadingPhoto
        case cancelRecognition
        case retryRecognition
        case reviewRecognizedText
        case reviewHelp
        case imageUnreadable
        case noRecognizedText
        case recognitionFailed
        case cameraDenied
        case cameraUnavailable
        case openSettings
        case photoReviewNotSaved
        case sourceManual
        case sourceCamera
        case sourcePhoto
    }

    /// 默认使用 App 首选语言；可注入语言 bundle，供验证程序检查实际打包的翻译。
    static func text(_ key: Key, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key.rawValue, value: nil, table: "Localizable")
    }

    /// 目前模板仅接收一个字符串参数，数量在调用端先格式化；译文需保留 %@ 占位符。
    static func format(_ key: Key, _ argument: String, bundle: Bundle = .main) -> String {
        String(format: text(key, bundle: bundle), locale: Locale.current, argument)
    }

    /// 仅展示应用可控的错误文案，不直接向界面暴露带内部路径的系统错误。
    static func errorDescription(_ error: Error) -> String {
        if let error = error as? VaultError {
            return error.errorDescription ?? text(.storageFailure)
        }
        if let error = error as? PhotoImportError {
            return error.errorDescription ?? text(.recognitionFailed)
        }
        return text(.storageFailure)
    }
}
