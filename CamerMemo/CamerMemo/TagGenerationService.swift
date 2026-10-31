import Foundation
import FoundationModels

/// AI 提示与分段参数集中配置；不属于翻译后的界面文案，也不从用户文档执行指令。
private struct TagAIConfiguration: Decodable {
    let instructions: String
    let mergeInstructions: String
    let documentPrefix: String
    let documentSuffix: String
    let chunkCharacters: Int
    /// 从应用资源加载并限制分段大小，防止错误配置让单次输入超过预期上下文预算。
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "TagAIConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Self.self, from: data),
              (100...1800).contains(config.chunkCharacters) else { throw TagGenerationError.failed }
        return config
    }
}

/// 区分系统能力不可用与生成失败，二者都允许继续手动添加标签。
enum TagGenerationError: LocalizedError {
    case unavailable(String), failed
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .failed: L10n.text(.tagGenerationFailed)
        }
    }
}

/// 结构化生成约束是第一道限制；模型输出随后仍会在应用侧清洗、去重和限量。
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct SuggestedTags {
    @Guide(description: "Short topic tags in the same language as the document", .count(0...3))
    var tags: [String]
}

/// 只使用 Apple 的设备端模型，不上传标题/正文，也不自动回退到云端模型。
enum TagGenerationService {
    /// 可用性必须运行时检查，不能仅凭系统版本或硬编码机型判断模型是否就绪。
    static var unavailableMessage: String? {
        guard #available(iOS 26.0, macOS 26.0, *) else { return L10n.text(.tagAIRequiresSystem) }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return L10n.text(.tagAIDeviceUnsupported)
            case .appleIntelligenceNotEnabled: return L10n.text(.tagAINotEnabled)
            case .modelNotReady: return L10n.text(.tagAIModelNotReady)
            @unknown default: return L10n.text(.tagAIUnavailable)
            }
        }
    }

    /// 对全文分段生成候选，再分层归并为最多三个标签；不静默截取正文前半部分。
    /// 整个流程响应调用任务取消，生成内容不写日志或资料库。
    static func suggest(for input: TagInput) async throws -> [String] {
        try Task.checkCancellation()
        if let reason = unavailableMessage { throw TagGenerationError.unavailable(reason) }
        guard #available(iOS 26.0, macOS 26.0, *) else { throw TagGenerationError.unavailable(L10n.text(.tagAIRequiresSystem)) }
        let config = try TagAIConfiguration.load()
        do {
            var candidates: [String] = []
            var remaining = input.document[...]
            while !remaining.isEmpty {
                try Task.checkCancellation()
                let end = remaining.index(remaining.startIndex, offsetBy: config.chunkCharacters, limitedBy: remaining.endIndex) ?? remaining.endIndex
                let chunk = String(remaining[..<end])
                remaining = remaining[end...]
                // 每段使用独立会话，避免多轮 transcript 累积挤占模型上下文。
                let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: config.instructions)
                let response = try await session.respond(to: config.documentPrefix + chunk + config.documentSuffix,
                    generating: SuggestedTags.self, options: GenerationOptions(temperature: 0, maximumResponseTokens: 256))
                try Task.checkCancellation()
                candidates = TagRules.unique(candidates + Array(response.content.tags.prefix(TagRules.maximumSuggestions)))
            }
            // 每组最多 12 项、输出最多 3 项，使候选集合有界缩小；空结果是合法结果。
            while candidates.count > TagRules.maximumSuggestions {
                var reduced: [String] = []
                for start in stride(from: 0, to: candidates.count, by: 12) {
                    try Task.checkCancellation()
                    let group = Array(candidates[start..<min(start + 12, candidates.count)])
                    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: config.mergeInstructions)
                    let response = try await session.respond(to: try String(data: JSONEncoder().encode(group), encoding: .utf8)!,
                        generating: SuggestedTags.self, options: GenerationOptions(temperature: 0, maximumResponseTokens: 256))
                    reduced += Array(response.content.tags.prefix(TagRules.maximumSuggestions))
                }
                candidates = TagRules.unique(reduced)
            }
            try Task.checkCancellation()
            return candidates
        // 取消与失败分开，让用户停止或离开界面时不出现失败提示。
        } catch is CancellationError { throw CancellationError() }
        catch { throw TagGenerationError.failed }
    }
}
