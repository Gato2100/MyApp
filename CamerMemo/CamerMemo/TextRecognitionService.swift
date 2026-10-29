import Foundation
import Vision
import ImageIO
import CoreGraphics

enum PhotoImportError: LocalizedError {
    case imageUnreadable, noText, recognitionFailed, cameraDenied, cameraUnavailable
    var errorDescription: String? {
        switch self {
        case .imageUnreadable: L10n.text(.imageUnreadable)
        case .noText: L10n.text(.noRecognizedText)
        case .recognitionFailed: L10n.text(.recognitionFailed)
        case .cameraDenied: L10n.text(.cameraDenied)
        case .cameraUnavailable: L10n.text(.cameraUnavailable)
        }
    }
}

enum RecognitionLanguage: String, CaseIterable, Identifiable {
    case automatic, chinese, japanese, english
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: L10n.text(.languageAutomatic)
        case .chinese: L10n.text(.languageChinese)
        case .japanese: L10n.text(.languageJapanese)
        case .english: L10n.text(.languageEnglish)
        }
    }
    var codes: [String] {
        switch self {
        case .automatic: ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
        case .chinese: ["zh-Hans", "zh-Hant", "en-US"]
        case .japanese: ["ja-JP", "en-US"]
        case .english: ["en-US"]
        }
    }
}

/// Only in-memory ImageIO/Vision processing. No file writes or network requests.
enum TextRecognitionService {
    static func prepare(_ data: Data) async throws -> CGImage {
        try Task.checkCancellation()
        let image = try await Task.detached(priority: .userInitiated) {
            // Bound compressed input and decoded pixels; apply EXIF rotation/mirroring.
            guard data.count <= 40 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3200,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw PhotoImportError.imageUnreadable }
            return image
        }.value
        try Task.checkCancellation()
        return image
    }

    static func recognize(_ image: CGImage, language: RecognitionLanguage) async throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language == .automatic
        let result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                do {
                    let supported = try request.supportedRecognitionLanguages()
                    request.recognitionLanguages = language.codes.filter { supported.contains($0) }
                    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                    // Preserve observation order and line breaks; complex layouts need review.
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw PhotoImportError.noText }
                    return text
                } catch let error as PhotoImportError { throw error }
                catch { throw PhotoImportError.recognitionFailed }
            }.value
        } onCancel: { request.cancel() }
        try Task.checkCancellation()
        return result
    }
}
