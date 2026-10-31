import Foundation
import CryptoKit
import CommonCrypto
import Security

/// 应用可展示的资料库错误；界面通过资源文件获取本地化说明。
enum VaultError: LocalizedError {
    case invalidFile, cannotUnlock, cryptoFailure, invalidContent
    var errorDescription: String? {
        switch self {
        case .invalidFile: L10n.text(.invalidFile)
        case .cannotUnlock: L10n.text(.cannotUnlock)
        case .cryptoFailure: L10n.text(.cryptoFailure)
        case .invalidContent: L10n.text(.invalidContent)
        }
    }
}
/// 文件层信封加密：密码派生 KEK 包装随机 DEK，DEK 加密整个 JSON 文档快照。
/// 只向磁盘写入密文；文件头和包装密钥通过附加认证数据与内容绑定。
struct EncryptedVault {
    // KDF 参数属于 v1 文件格式。修改时必须同时设计旧文件读取与格式迁移。
    private static let rounds = 600_000
    // 域分离标识参与认证，不是界面文案；更改会导致现有容器无法验证。
    private static let context = Data("CamerMemo.JSONVault.v1".utf8)
    /// 明文头只携带解密所需参数，不包含标题、标签、文档数量等内容元数据。
    private struct Header: Codable {
        let format: String
        let version: Int
        let rounds: Int
        let salt: Data
    }
    /// 两层密文均使用 GCM combined 格式，内部包含 nonce、密文和认证标签。
    private struct Container: Codable {
        let header: Data
        let wrappedKey: Data
        let payload: Data
    }
    /// 内层数据版本独立于容器版本；当前沿用默认 Date Codable 编码以兼容旧库。
    private struct Payload: Codable { let version: Int; let memos: [Memo] }
    /// 仅供已解锁会话使用的密钥上下文，不序列化，也不写入 Keychain。
    /// 释放引用用于缩短敏感数据寿命，不承诺 Swift 或系统副本都能可靠擦零。
    struct Session {
        fileprivate let header: Data
        fileprivate let wrappedKey: Data
        fileprivate let key: SymmetricKey
    }
    /// 位置是技术标识，不随应用语言变化，否则切换语言可能意外打开不同资料库。
    let url: URL
    /// 只准备 Application Support 路径；不创建新容器，更不覆盖已有内容。
    static func applicationVault() throws -> EncryptedVault {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CamerMemo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return EncryptedVault(url: folder.appendingPathComponent("vault.cmemo"))
    }
    /// 只允许首次创建。先生成随机 salt 与资料库密钥，成功写入空库后才返回会话。
    func create(password: String) throws -> Session {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultError.invalidFile }
        let salt = try Self.random(count: 32)
        let header = try JSONEncoder().encode(Header(format: "CamerMemo.JSONVault", version: 1, rounds: Self.rounds, salt: salt))
        let kek = try Self.derive(password: password, salt: salt)
        let rawKey = try Self.random(count: 32)
        // 使用默认随机 nonce，每次加密都产生独立 nonce；combined 对默认 nonce 可用。
        let wrapped = try AES.GCM.seal(rawKey, using: kek, authenticating: Self.context + header).combined!
        let session = Session(header: header, wrappedKey: wrapped, key: SymmetricKey(data: rawKey))
        try save([], session: session)
        return session
    }
    /// 解密顺序必须是验证文件头参数 → 解开 DEK → 验证并解密内容 → 解码文档。
    func open(password: String) throws -> (Session, [Memo]) {
        // 在读取整文件前限制大小；后续也限制头长度和 KDF 参数，拒绝异常容器。
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 100 * 1024 * 1024 else { throw VaultError.invalidFile }
        let bytes = try Data(contentsOf: url)
        do {
            let container = try JSONDecoder().decode(Container.self, from: bytes)
            guard container.header.count < 4096 else { throw VaultError.invalidFile }
            let header = try JSONDecoder().decode(Header.self, from: container.header)
            guard header.format == "CamerMemo.JSONVault", header.version == 1,
                  header.rounds == Self.rounds, header.salt.count == 32 else { throw VaultError.invalidFile }
            let kek = try Self.derive(password: password, salt: header.salt)
            // 认证原始 header 字节，而不是重新编码的 JSON，避免键顺序差异造成认证失败。
            let rawKey = try AES.GCM.open(AES.GCM.SealedBox(combined: container.wrappedKey), using: kek,
                                          authenticating: Self.context + container.header)
            guard rawKey.count == 32 else { throw VaultError.invalidFile }
            let session = Session(header: container.header, wrappedKey: container.wrappedKey, key: SymmetricKey(data: rawKey))
            // 将包装密钥也绑定到内容认证，防止不同容器片段被拼接后当作完整资料库。
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: container.payload), using: session.key,
                                         authenticating: Self.context + container.header + container.wrappedKey)
            let payload = try JSONDecoder().decode(Payload.self, from: plain)
            guard payload.version == 1, Set(payload.memos.map(\.id)).count == payload.memos.count else { throw VaultError.invalidFile }
            return (session, payload.memos)
        // 读取权限等文件错误在上方单独抛出；内部认证/格式错误统一为解锁失败。
        } catch { throw VaultError.cannotUnlock }
    }
    /// 保存完整快照；临时文件也只含密文。原子替换失败时保留最后成功版本。
    func save(_ memos: [Memo], session: Session) throws {
        let plain = try JSONEncoder().encode(Payload(version: 1, memos: memos))
        let encrypted = try AES.GCM.seal(plain, using: session.key,
                                          authenticating: Self.context + session.header + session.wrappedKey).combined!
        let bytes = try JSONEncoder().encode(Container(header: session.header, wrappedKey: session.wrappedKey, payload: encrypted))
        guard bytes.count <= 100 * 1024 * 1024 else { throw VaultError.invalidContent }
        // iOS 同时启用完整文件保护；macOS 分支用于同源核心检查程序。
        #if os(iOS)
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
    }
    /// 密钥与 salt 使用系统密码学随机源，不能替换成一般用途的随机数生成器。
    private static func random(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw VaultError.cryptoFailure }
        return Data(bytes)
    }
    /// 按密码的 UTF-8 字节长度调用 PBKDF2，不能把 Swift 字符数当作 C 接口字节数。
    /// 输出 32 字节 KEK，主密码不作为密钥直接使用，也不写入文件。
    private static func derive(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self), passwordBytes.count,
                    saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(Self.rounds), &derived, 32)
            }
        }
        guard status == kCCSuccess else { throw VaultError.cryptoFailure }
        return SymmetricKey(data: derived)
    }
}
