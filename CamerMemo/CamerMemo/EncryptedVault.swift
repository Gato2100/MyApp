import Foundation
import CryptoKit
import CommonCrypto
import Security

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
struct EncryptedVault {
    private static let rounds = 600_000
    private static let context = Data("CamerMemo.JSONVault.v1".utf8)
    private struct Header: Codable {
        let format: String
        let version: Int
        let rounds: Int
        let salt: Data
    }
    private struct Container: Codable {
        let header: Data
        let wrappedKey: Data
        let payload: Data
    }
    private struct Payload: Codable { let version: Int; let memos: [Memo] }
    struct Session {
        fileprivate let header: Data
        fileprivate let wrappedKey: Data
        fileprivate let key: SymmetricKey
    }
    let url: URL
    static func applicationVault() throws -> EncryptedVault {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CamerMemo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return EncryptedVault(url: folder.appendingPathComponent("vault.cmemo"))
    }
    func create(password: String) throws -> Session {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultError.invalidFile }
        let salt = try Self.random(count: 32)
        let header = try JSONEncoder().encode(Header(format: "CamerMemo.JSONVault", version: 1, rounds: Self.rounds, salt: salt))
        let kek = try Self.derive(password: password, salt: salt)
        let rawKey = try Self.random(count: 32)
        let wrapped = try AES.GCM.seal(rawKey, using: kek, authenticating: Self.context + header).combined!
        let session = Session(header: header, wrappedKey: wrapped, key: SymmetricKey(data: rawKey))
        try save([], session: session)
        return session
    }
    func open(password: String) throws -> (Session, [Memo]) {
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
            let rawKey = try AES.GCM.open(AES.GCM.SealedBox(combined: container.wrappedKey), using: kek,
                                          authenticating: Self.context + container.header)
            guard rawKey.count == 32 else { throw VaultError.invalidFile }
            let session = Session(header: container.header, wrappedKey: container.wrappedKey, key: SymmetricKey(data: rawKey))
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: container.payload), using: session.key,
                                         authenticating: Self.context + container.header + container.wrappedKey)
            let payload = try JSONDecoder().decode(Payload.self, from: plain)
            guard payload.version == 1, Set(payload.memos.map(\.id)).count == payload.memos.count else { throw VaultError.invalidFile }
            return (session, payload.memos)
        } catch { throw VaultError.cannotUnlock }
    }
    func save(_ memos: [Memo], session: Session) throws {
        let plain = try JSONEncoder().encode(Payload(version: 1, memos: memos))
        let encrypted = try AES.GCM.seal(plain, using: session.key,
                                          authenticating: Self.context + session.header + session.wrappedKey).combined!
        let bytes = try JSONEncoder().encode(Container(header: session.header, wrappedKey: session.wrappedKey, payload: encrypted))
        guard bytes.count <= 100 * 1024 * 1024 else { throw VaultError.invalidContent }
        #if os(iOS)
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
    }
    private static func random(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw VaultError.cryptoFailure }
        return Data(bytes)
    }
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
