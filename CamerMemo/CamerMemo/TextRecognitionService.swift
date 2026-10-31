import Foundation
import Vision
import ImageIO
import CoreGraphics

/// 图片读取、识别和设备能力错误，统一映射到本地化资源文案。
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

/// 用户可选的识别语言策略；实际提交前还会与设备支持的语言取交集。
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
    /// 指定语言优先，并保留常见英文混排；自动模式同时启用 Vision 自动语言检测。
    var codes: [String] {
        switch self {
        case .automatic: ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
        case .chinese: ["zh-Hans", "zh-Hant", "en-US"]
        case .japanese: ["ja-JP", "en-US"]
        case .english: ["en-US"]
        }
    }
}

/// 本机图片解码与 OCR 服务；不执行网络请求，也不把中间图写入文件。
enum TextRecognitionService {
    /// 为 OCR 生成有界尺寸的副本并应用 EXIF 方向；附件仍由调用端保留完整文件数据。
    static func prepare(_ data: Data) async throws -> CGImage {
        try Task.checkCancellation()
        // 解码可能占用 CPU，移出主 actor；返回后再次检查取消，避免更新已离开的页面。
        let image = try await Task.detached(priority: .userInitiated) {
            // 同时限制压缩文件大小和解码尺寸，并应用 EXIF 的旋转/镜像信息。
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

    /// 高精度识别并保留观察结果的行顺序；多栏、竖排或手写排版仍需人工校对。
    static func recognize(_ image: CGImage, language: RecognitionLanguage) async throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language == .automatic
        // Swift 任务取消时同时通知 Vision；完成后再检查取消，不让迟到结果进入界面。
        let result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                do {
                    let supported = try request.supportedRecognitionLanguages()
                    // 不直接假定所有 OS/模型版本都支持预设的语言代码。
                    request.recognitionLanguages = language.codes.filter { supported.contains($0) }
                    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                    // 保留观察结果顺序与换行，不假设复杂版面的阅读顺序已完全正确。
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    // 空结果是可恢复错误，不能自动保存成一条空备忘录。
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
