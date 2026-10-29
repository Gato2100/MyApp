import Foundation
import Observation

@MainActor @Observable
final class TagDraft {
    private(set) var manual: [String]
    private(set) var suggestions: [String] = []
    private(set) var excluded = Set<String>()
    private(set) var isGenerating = false
    private(set) var message: String?
    var pending = ""
    var inputError: String?
    private var input: TagInput?
    private var generation = UUID()

    init(existing: [String] = [], rejectedKeys: [String] = []) {
        manual = TagRules.unique(existing); excluded = Set(rejectedKeys)
    }
    var selected: [String] {
        TagRules.unique(manual + suggestions.filter { !excluded.contains(TagRules.key($0)) })
    }
    func selected(for current: TagInput) -> [String] {
        current == input ? selected : manual
    }
    @discardableResult func commitPending() -> Bool {
        let tag = TagRules.clean(pending)
        guard !tag.isEmpty else { pending = ""; inputError = nil; return true }
        guard tag.count <= TagRules.maximumLength else { inputError = L10n.text(.tagTooLong); return false }
        manual = TagRules.unique(manual + [tag])
        excluded.remove(TagRules.key(tag)); pending = ""; inputError = nil
        return true
    }
    func remove(_ tag: String) {
        manual.removeAll { TagRules.key($0) == TagRules.key(tag) }
        excluded.insert(TagRules.key(tag))
    }
    func isSelected(_ tag: String) -> Bool { !excluded.contains(TagRules.key(tag)) }
    func toggle(_ tag: String) {
        let key = TagRules.key(tag)
        if excluded.contains(key) { excluded.remove(key) } else { excluded.insert(key) }
    }
    func prepare(for input: TagInput) {
        cancel(); self.input = input; suggestions = []; message = nil
        isGenerating = !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func generate(for input: TagInput, generator: (TagInput) async throws -> [String] = TagGenerationService.suggest) async {
        let token = UUID(); generation = token; self.input = input
        isGenerating = true; message = nil
        defer { if generation == token { isGenerating = false } }
        do {
            let tags = try await generator(input)
            try Task.checkCancellation()
            guard generation == token, self.input == input else { return }
            suggestions = Array(TagRules.unique(tags).prefix(TagRules.maximumSuggestions))
            if suggestions.isEmpty { message = L10n.text(.tagNoSuggestions) }
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            message = (error as? TagGenerationError)?.errorDescription ?? L10n.text(.tagGenerationFailed)
        }
    }
    func cancel() { generation = UUID(); isGenerating = false }
    func reset() {
        cancel(); manual = []; suggestions = []; excluded = []; pending = ""; inputError = nil; input = nil; message = nil
    }
}
