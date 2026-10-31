import AppKit
import ImageIO

/// 在内存绘制合成样本并调用真实 Vision，验证英中日识别、空图、无效数据与取消。
@main
struct OCRChecks {
    @MainActor static func main() async throws {
        // 样本由程序绘制，无需照片库或相机权限，也不接触真实照片。
        let context = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("CAMERMEMO 12345" as NSString).draw(at: CGPoint(x: 100, y: 550), withAttributes: [
            .font: NSFont.systemFont(ofSize: 90), .foregroundColor: NSColor.black
        ])
        ("PHOTO TEXT RECOGNITION" as NSString).draw(at: CGPoint(x: 100, y: 350), withAttributes: [
            .font: NSFont.systemFont(ofSize: 70), .foregroundColor: NSColor.black
        ])
        NSGraphicsContext.restoreGraphicsState()
        let sample = context.makeImage()!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, sample, nil)
        precondition(CGImageDestinationFinalize(destination))
        let prepared = try await TextRecognitionService.prepare(encoded as Data)
        let text = try await TextRecognitionService.recognize(prepared, language: .english)
        precondition(text.contains("CAMERMEMO") && text.contains("12345"), "OCR missed test text")
        precondition(text.contains("PHOTO TEXT RECOGNITION"), "OCR missed second line")
        do { _ = try await TextRecognitionService.prepare(Data("invalid".utf8)); fatalError("Invalid image accepted") }
        catch PhotoImportError.imageUnreadable {}
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        do { _ = try await TextRecognitionService.recognize(context.makeImage()!, language: .english); fatalError("Blank image produced text") }
        catch PhotoImportError.noText {}
        // 显式语言分别验证中文与日文模型；仅检查关键片段，避免依赖微小标点差异。
        for (sampleText, language, required) in [
            ("相机 文字备忘录", RecognitionLanguage.chinese, "文字"),
            ("新宿で写真を撮影", RecognitionLanguage.japanese, "写真")
        ] {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (sampleText as NSString).draw(at: CGPoint(x: 100, y: 550), withAttributes: [
                .font: NSFont.systemFont(ofSize: 90), .foregroundColor: NSColor.black
            ])
            NSGraphicsContext.restoreGraphicsState()
            let result = try await TextRecognitionService.recognize(context.makeImage()!, language: language)
            precondition(result.contains(required), "CJK OCR missed expected text")
        }
        let cancelled = Task {
            return try await TextRecognitionService.recognize(prepared, language: .english)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        print("PASS: actual English/Chinese/Japanese Vision OCR, image decode, blank image, invalid data, cancellation")
    }
}
