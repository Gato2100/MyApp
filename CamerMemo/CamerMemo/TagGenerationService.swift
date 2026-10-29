import Foundation
import FoundationModels

private struct TagAIConfiguration: Decodable {
    let instructions: String
    let mergeInstructions: String
    let documentPrefix: String
    let documentSuffix: String
    let chunkCharacters: Int
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "TagAIConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Self.self, from: data),
              (100...1800).contains(config.chunkCharacters) else { throw TagGenerationError.failed }
        return config
    }
}

enum TagGenerationError: LocalizedError {
    case unavailable(String), failed
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .failed: L10n.text(.tagGenerationFailed)
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct SuggestedTags {
    @Guide(description: "Short topic tags in the same language as the document", .count(0...3))
    var tags: [String]
}

enum TagGenerationService {
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

    static func suggest(for input: TagInput) async throws -> [String] {
        try Task.checkCancellation()
        if let reason = unavailableMessage { throw TagGenerationError.unavailable(reason) }
        guard #available(iOS 26.0, macOS 26.0, *) else { throw TagGenerationError.unavailable(L10n.text(.tagAIRequiresSystem)) }
        let config = try TagAIConfiguration.load()
        do {
            // Fresh on-device session per chunk; never silently truncate long memos.
            var candidates: [String] = []
            var remaining = input.document[...]
            while !remaining.isEmpty {
                try Task.checkCancellation()
                let end = remaining.index(remaining.startIndex, offsetBy: config.chunkCharacters, limitedBy: remaining.endIndex) ?? remaining.endIndex
                let chunk = String(remaining[..<end])
                remaining = remaining[end...]
                let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: config.instructions)
                let response = try await session.respond(to: config.documentPrefix + chunk + config.documentSuffix,
                    generating: SuggestedTags.self, options: GenerationOptions(temperature: 0, maximumResponseTokens: 256))
                try Task.checkCancellation()
                candidates = TagRules.unique(candidates + Array(response.content.tags.prefix(TagRules.maximumSuggestions)))
            }
            // Reduce large candidate sets in bounded groups; include every chunk's candidates.
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
        } catch is CancellationError { throw CancellationError() }
        catch { throw TagGenerationError.failed }
    }
}
