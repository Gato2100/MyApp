import Foundation
import Observation

/// 界面共享的解锁会话与本地写入入口；主 actor 保证状态发布及写入操作顺序一致。
/// 昂贵的密码派生在后台运行，保存仍是串行的整库加密写入。
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
    // 每次锁定更换令牌，使先前启动但尚未完成的解锁结果失效。
    private var generation = UUID()
    // 注入时钟与文件位置，便于独立验证时钟回拨、失败写入，而不接触真实资料库。
    private let clock: () -> Date
    /// 初始化只定位资料库；不能因为读取或初始化失败就把已有文件视为空库重建。
    init(vault suppliedVault: EncryptedVault? = nil, clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        do {
            let vault = try suppliedVault ?? EncryptedVault.applicationVault()
            self.vault = vault
            exists = FileManager.default.fileExists(atPath: vault.url.path)
        } catch { initializationError = L10n.errorDescription(error) }
    }
    /// 同一时刻只运行一次解锁；创建/解密成功且令牌仍有效后才发布明文。
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
            // 解锁期间即使发生锁定，首次创建的文件也可能已落盘；仅丢弃迟到的会话结果。
            exists = true
            guard token == generation else { return }
            session = result.0; memos = result.1; isUnlocked = true
        } catch {
            exists = FileManager.default.fileExists(atPath: vault.url.path)
            throw error
        }
    }
    /// 先验证会话与正文，再统一维护时间戳；内容相同则不写盘、不推进更新时间。
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
        // 先写后发布：失败时列表、附件和时间戳都维持最后成功状态。
        try vault.save(next, session: session)
        memos = next
    }
    /// 将一批文档作为一次快照删除，避免循环写入出现半批成功、半批失败。
    /// 本层不呈现确认框，调用者必须在用户确认后再调用。
    func delete(ids: Set<UUID>) throws {
        guard let vault, let session, isUnlocked else { throw VaultError.cannotUnlock }
        guard !ids.isEmpty else { return }
        let next = memos.filter { !ids.contains($0.id) }
        guard next.count != memos.count else { return }
        // 图片与标签内嵌于文档，随同一次快照移除；共享标签不会从其他文档中删除。
        try vault.save(next, session: session)
        memos = next
    }
    /// 清空可访问的明文与会话引用，并作废未完成的解锁；已保存密文不受影响。
    func lock() {
        generation = UUID(); isUnlocked = false; session = nil; memos = []
    }
}
