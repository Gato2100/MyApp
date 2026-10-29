import Foundation
import Observation

@MainActor @Observable
final class MemoStore {
    private(set) var memos: [Memo] = []
    private(set) var isUnlocked = false
    private(set) var isBusy = false
    private(set) var exists = false
    private(set) var initializationError: String?
    var notice: String?
    private var vault: EncryptedVault?
    private var session: EncryptedVault.Session?
    private var generation = UUID()
    private let clock: () -> Date
    init(vault suppliedVault: EncryptedVault? = nil, clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        do {
            let vault = try suppliedVault ?? EncryptedVault.applicationVault()
            self.vault = vault
            exists = FileManager.default.fileExists(atPath: vault.url.path)
        } catch { initializationError = L10n.errorDescription(error) }
    }
    func unlock(password: String) async throws {
        guard let vault, !isBusy else { return }
        isBusy = true
        let token = generation
        let creating = !exists
        defer { isBusy = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                if creating { return (try vault.create(password: password), [Memo]()) }
                return try vault.open(password: password)
            }.value
            exists = true
            guard token == generation else { return }
            session = result.0; memos = result.1; isUnlocked = true
        } catch {
            exists = FileManager.default.fileExists(atPath: vault.url.path)
            throw error
        }
    }
    func save(_ memo: Memo) throws {
        guard let vault, let session, isUnlocked else { throw VaultError.cannotUnlock }
        guard !memo.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaultError.invalidContent }
        var next = memos
        if let index = next.firstIndex(where: { $0.id == memo.id }) {
            let previous = next[index]
            guard !memo.hasSameContent(as: previous) else { return }
            next[index] = memo.preparingForLocalSave(previous: previous, at: clock())
        } else {
            next.append(memo.preparingForLocalSave(previous: nil, at: clock()))
        }
        // Publish only after the encrypted atomic write succeeds.
        try vault.save(next, session: session)
        memos = next
    }
    func delete(ids: Set<UUID>) throws {
        guard let vault, let session, isUnlocked else { throw VaultError.cannotUnlock }
        guard !ids.isEmpty else { return }
        let next = memos.filter { !ids.contains($0.id) }
        guard next.count != memos.count else { return }
        // Attachments and tags are embedded in each memo. Commit the entire batch atomically.
        try vault.save(next, session: session)
        memos = next
    }
    func lock() {
        generation = UUID(); isUnlocked = false; session = nil; memos = []
    }
}
