import Foundation

/// 注入确定性生成器验证标签交互，不依赖 Apple Intelligence 的可用性或输出随机性。
@main
struct TagChecks {
    @MainActor static func main() async throws {
        precondition(TagRules.unique([" #旅行 ", "旅行", "ＡＩ", "ai", " "]) == ["旅行", "ＡＩ"])
        // 以可控结果验证三项上限与默认勾选，不对真实生成内容做脆弱的字面断言。
        let draft = TagDraft(existing: ["保留标签"])
        let input = TagInput(title: "相机", body: "周五到新宿购买镜头")
        draft.prepare(for: input)
        await draft.generate(for: input) { _ in ["新宿", "相机", "购物", "额外"] }
        precondition(draft.suggestions.count == 3)
        precondition(draft.selected == ["保留标签", "新宿", "相机", "购物"])
        draft.toggle("购物")
        precondition(!draft.selected.contains("购物"))
        draft.prepare(for: input)
        await draft.generate(for: input) { _ in ["新宿", "购物"] }
        precondition(!draft.selected.contains("购物"), "Explicit deselection must survive regeneration")
        draft.pending = "手动追加"; precondition(draft.commitPending())
        draft.pending = "手动追加"; precondition(draft.commitPending())
        precondition(draft.selected.filter { $0 == "手动追加" }.count == 1)
        draft.pending = String(repeating: "字", count: 33)
        precondition(!draft.commitPending() && draft.inputError != nil)
        draft.pending = ""
        draft.remove("保留标签")
        precondition(!draft.selected.contains("保留标签"))
        precondition(draft.selected(for: TagInput(title: "已变更", body: "新内容")) == draft.manual)
        // 重新建立编辑会话，模拟保存后再打开，明确拒选不应被默认重新加入。
        let restored = TagDraft(existing: draft.selected, rejectedKeys: draft.excluded.sorted())
        restored.prepare(for: input)
        await restored.generate(for: input) { _ in ["购物", "保留标签", "新标签"] }
        precondition(!restored.selected.contains("购物") && !restored.selected.contains("保留标签"))
        precondition(restored.selected.contains("新标签"))
        // 人工延迟旧请求并先完成新请求，确定性复现乱序回调。
        let stale = TagDraft()
        var continuation: CheckedContinuation<[String], Never>?
        let oldTask = Task { await stale.generate(for: input) { _ in await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        let newer = TagInput(title: "新内容", body: "新正文")
        stale.prepare(for: newer)
        await stale.generate(for: newer) { _ in ["新结果"] }
        continuation?.resume(returning: ["旧结果"])
        await oldTask.value
        precondition(stale.selected == ["新结果"], "Late result must not overwrite current content")
        // 即使生成器不主动响应取消，令牌和 Task 状态也必须阻止迟到结果发布。
        var cancelledContinuation: CheckedContinuation<[String], Never>?
        let cancelled = Task { await stale.generate(for: newer) { _ in await withCheckedContinuation { cancelledContinuation = $0 } } }
        while cancelledContinuation == nil { await Task.yield() }
        cancelled.cancel(); stale.cancel()
        cancelledContinuation?.resume(returning: ["取消后的结果"])
        await cancelled.value
        precondition(!stale.selected.contains("取消后的结果"))
        stale.reset()
        precondition(stale.selected.isEmpty && !stale.isGenerating)
        print("PASS: max 3 AI tags, defaults selected, manual add/remove/dedup, validation, deselection persistence, stale results and cancellation")
    }
}
