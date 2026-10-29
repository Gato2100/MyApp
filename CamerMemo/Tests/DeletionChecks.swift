import Foundation

@main
struct DeletionChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("vaultFolder")
        let moved = root.appendingPathComponent("savedVaultFolder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = EncryptedVault(url: folder.appendingPathComponent("vault.cmemo"))
        let store = MemoStore(vault: vault)
        let password = "delete-check-123456789"
        try await store.unlock(password: password)
        var first = Memo(title: "选中一", body: "需要删除的记录一")
        first.tags = ["待删除标签"]; first.imageData = Data([1, 2, 3])
        var second = Memo(title: "选中二", body: "需要删除的记录二")
        second.tags = ["共享标签"]; second.imageData = Data([4, 5, 6])
        var remaining = Memo(title: "保留", body: "未选中的记录")
        remaining.tags = ["共享标签"]; remaining.imageData = Data([7, 8, 9])
        try store.save(first); try store.save(second); try store.save(remaining)
        remaining = store.memos.first { $0.id == remaining.id }!
        let before = store.memos
        let beforeFile = try Data(contentsOf: vault.url)
        var selection = MemoSelection()
        selection.toggle(first.id)
        precondition(selection.ids.isEmpty)
        selection.start(); selection.toggle(first.id); selection.toggle(second.id)
        precondition(selection.ids.count == 2)
        selection.retainVisible([first.id, remaining.id])
        precondition(selection.ids == [first.id], "Hidden search results must be deselected")
        selection.selectAll([first.id, remaining.id])
        precondition(selection.ids == [first.id, remaining.id])
        selection.selectAll([first.id, remaining.id]); precondition(selection.ids.isEmpty)
        selection.finish(); precondition(!selection.isSelecting && selection.ids.isEmpty)
        // Merely selecting/cancelling does not write or delete anything.
        precondition(store.memos == before)
        let afterCancel = try Data(contentsOf: vault.url)
        precondition(afterCancel == beforeFile)
        try store.delete(ids: [])
        try store.delete(ids: [UUID()])
        let afterNoOp = try Data(contentsOf: vault.url)
        precondition(afterNoOp == beforeFile)
        // Replace the parent with a regular test file to force a deterministic write failure.
        try FileManager.default.moveItem(at: folder, to: moved)
        try Data("test write blocker".utf8).write(to: folder)
        do { try store.delete(ids: [first.id, second.id]); fatalError("Write unexpectedly succeeded") } catch {}
        precondition(store.memos == before, "Failed deletion must preserve memory")
        let preserved = try Data(contentsOf: moved.appendingPathComponent("vault.cmemo"))
        precondition(preserved == beforeFile, "Failed deletion must preserve the previous vault")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: moved, to: folder)
        try store.delete(ids: [first.id, second.id])
        precondition(store.memos == [remaining])
        precondition(Memo.search(store.memos, query: "待删除标签", scope: .tags).isEmpty)
        precondition(Memo.search(store.memos, query: "共享标签", scope: .tags) == [remaining])
        let reopened = try vault.open(password: password).1
        precondition(reopened == [remaining], "Batch deletion must persist with the remaining attachment intact")
        store.lock()
        do { try store.delete(ids: [remaining.id]); fatalError("Locked store allowed deletion") } catch {}
        try await store.unlock(password: password)
        precondition(store.memos == [remaining])
        try store.delete(ids: [remaining.id])
        store.lock(); try await store.unlock(password: password)
        precondition(store.memos.isEmpty)
        print("PASS: multi-selection, hidden-result pruning, cancel/no-op, failed-write rollback, encrypted batch deletion, shared tags, attachment retention, locked guard and empty-vault reopen")
    }
}
