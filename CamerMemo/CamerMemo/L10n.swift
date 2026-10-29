import Foundation

/// All app-authored display text lives in Localizable.xcstrings.
/// Bundle resolution follows the system's preferred app language, falling back to zh-Hans.
enum L10n {
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

    static func text(_ key: Key, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key.rawValue, value: nil, table: "Localizable")
    }

    static func format(_ key: Key, _ argument: String, bundle: Bundle = .main) -> String {
        String(format: text(key, bundle: bundle), locale: Locale.current, argument)
    }

    static func errorDescription(_ error: Error) -> String {
        // Framework-generated errors may contain file paths and have inconsistent language.
        // Present app-owned localized copy; do not expose internal diagnostics as UI text.
        if let error = error as? VaultError {
            return error.errorDescription ?? text(.storageFailure)
        }
        if let error = error as? PhotoImportError {
            return error.errorDescription ?? text(.recognitionFailed)
        }
        return text(.storageFailure)
    }
}
