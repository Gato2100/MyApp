import Foundation

@main
struct TimestampChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = EncryptedVault(url: root.appendingPathComponent("vault.cmemo"))
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoStore(vault: vault, clock: { now })
        let password = "timestamp-check-123456789"
        try await store.unlock(password: password)
        let drafted = Memo(title: "时间验证", body: "正文", createdAt: now.addingTimeInterval(-3600))
        precondition(drafted.createdAt == drafted.updatedAt)
        try store.save(drafted)
        let first = store.memos[0]
        precondition(first.createdAt == now && first.updatedAt == now, "Creation means first successful save, not editor opening")
        let firstFile = try Data(contentsOf: vault.url)
        now = now.addingTimeInterval(120)
        try store.save(first)
        precondition(store.memos[0] == first, "Unchanged save must not refresh timestamps")
        let afterNoOp = try Data(contentsOf: vault.url)
        precondition(afterNoOp == firstFile)
        var edit = first; edit.body = "修改正文"
        try store.save(edit)
        let bodyEdit = store.memos[0]
        precondition(bodyEdit.createdAt == first.createdAt && bodyEdit.updatedAt == now)
        now = now.addingTimeInterval(120)
        edit = bodyEdit; edit.tags = ["新标签"]
        try store.save(edit)
        precondition(store.memos[0].updatedAt == now)
        now = now.addingTimeInterval(120)
        edit = store.memos[0]; edit.imageData = Data([1, 2, 3])
        try store.save(edit)
        precondition(store.memos[0].updatedAt == now)
        let beforeClockRollback = store.memos[0]
        now = now.addingTimeInterval(-1000)
        edit = beforeClockRollback; edit.title = "回拨后编辑"
        try store.save(edit)
        let afterRollback = store.memos[0]
        precondition(afterRollback.createdAt == first.createdAt && afterRollback.updatedAt > beforeClockRollback.updatedAt)
        // Incoming stale editor timestamps cannot replace original creation metadata.
        var stale = drafted; stale.title = "旧编辑器提交"; stale.tags = ["另一个标签"]
        try store.save(stale)
        precondition(store.memos[0].createdAt == first.createdAt)
        let beforeFailure = store.memos[0]
        let savedFile = root.appendingPathComponent("saved.cmemo")
        try FileManager.default.moveItem(at: vault.url, to: savedFile)
        try FileManager.default.createDirectory(at: vault.url, withIntermediateDirectories: false)
        edit = beforeFailure; edit.body = "不应写入的变更"
        do { try store.save(edit); fatalError("Expected write failure") } catch {}
        precondition(store.memos[0] == beforeFailure, "Failed write must not publish new timestamps")
        try FileManager.default.removeItem(at: vault.url)
        try FileManager.default.moveItem(at: savedFile, to: vault.url)
        store.lock(); try await store.unlock(password: password)
        precondition(store.memos[0] == beforeFailure, "Encrypted reopen must preserve timestamps")
        precondition(store.memos[0].createdAt.timeIntervalSince1970 == first.createdAt.timeIntervalSince1970)
        // Existing v1 dates retain their exact encoding and values; no migration or duplicate fields.
        let legacy = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(Memo.self, from: legacy)
        precondition(decoded.createdAt == first.createdAt && decoded.updatedAt == first.updatedAt)
        print("PASS: first-save timestamps, no-op save, body/tag/attachment edits, immutable creation time, clock rollback, failed-write safety and encrypted/legacy roundtrip")
    }
}
