import Foundation
import Observation

/// 标签编辑会话，区分已有/手动标签、AI 候选和明确拒选的等价 key。
/// 本对象只管理草稿，最终标签由文档保存流程提交至加密资料库。
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
    // 即使底层模型忽略取消，也可用令牌拒绝过期响应；不依赖返回顺序。
    private var generation = UUID()

    /// 已保存标签作为稳定基础；拒选 key 一并恢复，避免重开编辑页后又自动选中。
    init(existing: [String] = [], rejectedKeys: [String] = []) {
        manual = TagRules.unique(existing); excluded = Set(rejectedKeys)
    }
    /// 新 AI 候选默认选中，只有明确拒选项被排除；最终合并时再去重。
    var selected: [String] {
        TagRules.unique(manual + suggestions.filter { !excluded.contains(TagRules.key($0)) })
    }
    /// 保存时复核正文快照；若界面变化尚未触发刷新，不保存上一份正文的 AI 候选。
    func selected(for current: TagInput) -> [String] {
        current == input ? selected : manual
    }
    /// 点击添加、键盘提交和文档保存共用入口；无效输入留在框内供用户修正。
    @discardableResult func commitPending() -> Bool {
        let tag = TagRules.clean(pending)
        guard !tag.isEmpty else { pending = ""; inputError = nil; return true }
        guard tag.count <= TagRules.maximumLength else { inputError = L10n.text(.tagTooLong); return false }
        manual = TagRules.unique(manual + [tag])
        excluded.remove(TagRules.key(tag)); pending = ""; inputError = nil
        return true
    }
    /// 移除手动/已有标签也记入拒选集合，避免同次或下次生成又将它默认加回。
    func remove(_ tag: String) {
        manual.removeAll { TagRules.key($0) == TagRules.key(tag) }
        excluded.insert(TagRules.key(tag))
    }
    func isSelected(_ tag: String) -> Bool { !excluded.contains(TagRules.key(tag)) }
    func toggle(_ tag: String) {
        let key = TagRules.key(tag)
        if excluded.contains(key) { excluded.remove(key) } else { excluded.insert(key) }
    }
    /// 内容或重试条件变化时先作废旧请求；保留手动标签与拒选，丢弃旧正文候选。
    func prepare(for input: TagInput) {
        cancel(); self.input = input; suggestions = []; message = nil
        isGenerating = !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// 可注入生成器进行确定性验证；生产默认调用本机模型。请求、内容、取消状态均需有效。
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
    /// 使进行中的回调失效；实际 Swift 任务取消由持有 .task 的编辑器负责。
    func cancel() { generation = UUID(); isGenerating = false }
    /// 重选图片或结束未保存会话时清理全部标签状态，不能把旧文档标签带入新文档。
    func reset() {
        cancel(); manual = []; suggestions = []; excluded = []; pending = ""; inputError = nil; input = nil; message = nil
    }
}
