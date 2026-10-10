import Foundation
import CryptoKit
import Security

struct RelayHello: Codable, Equatable {
    var version = 1
    var role: RelayRole
    var identity: Data
    var ephemeral: Data
    var nonce: Data
    var transcriptPart: Data {
        Data("picelf-relay-v1:\(role.rawValue):".utf8) + identity + ephemeral + nonce
    }
}
// A fresh signed ephemeral exchange for every connection. Payload encryption also
// prevents an intermediary relaying a valid handshake from reading image resources.
struct RelayHandshake {
    let signingKey: Curve25519.Signing.PrivateKey
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    let hello: RelayHello
    init(role: RelayRole, signingKey: Curve25519.Signing.PrivateKey) {
        self.signingKey = signingKey
        var nonce = Data(count: 32)
        nonce.withUnsafeMutableBytes { bytes in _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!) }
        hello = RelayHello(role: role, identity: signingKey.publicKey.rawRepresentation,
                           ephemeral: ephemeral.publicKey.rawRepresentation, nonce: nonce)
    }
    func transcript(_ remote: RelayHello) throws -> Data {
        guard remote.version == 1, remote.role != hello.role, remote.identity.count == 32,
              remote.ephemeral.count == 32, remote.nonce.count == 32,
              remote.identity != hello.identity else { throw RelayError.message(L10n.localized("设备协议不兼容，请更新两端 Picelf。", "The device protocols are incompatible. Update Picelf on both devices.")) }
        return hello.role == .mac ? hello.transcriptPart + remote.transcriptPart : remote.transcriptPart + hello.transcriptPart
    }
    func proof(_ remote: RelayHello) throws -> Data { try signingKey.signature(for: transcript(remote)) }
    func verify(_ proof: Data, from remote: RelayHello) throws {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: remote.identity)
        guard try key.isValidSignature(proof, for: transcript(remote)) else { throw RelayError.message(L10n.localized("配对身份验证失败。", "Pairing verification failed.")) }
    }
    func sessionKey(_ remote: RelayHello) throws -> SymmetricKey {
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: remote.ephemeral))
        return try shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(SHA256.hash(data: transcript(remote))),
                                                  sharedInfo: Data("picelf-relay-images".utf8), outputByteCount: 32)
    }
    func code(_ remote: RelayHello) throws -> String {
        let bytes = Array(SHA256.hash(data: try transcript(remote)))
        let value = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }
    static func seal(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw RelayError.message(L10n.localized("无法加密传输内容。", "Could not encrypt the transfer.")) }
        return combined
    }
    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(.init(combined: data), using: key)
    }
}
enum RelayKeychain {
    private static let service = "com.picelf.open.relay.identity.v1"
    static func read(_ account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw RelayError.message(L10n.localized("无法读取接力画板的设备凭据（\(status)）。", "Could not read Relay Canvas device credentials (\(status)).")) }
        return result as? Data
    }
    static func write(_ data: Data, account: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        let status = SecItemUpdate(query, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd([
                kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary, nil)
            guard status == errSecSuccess else { throw RelayError.message(L10n.localized("无法保存设备凭据（\(status)）。", "Could not save device credentials (\(status)).")) }
        } else if status != errSecSuccess { throw RelayError.message(L10n.localized("无法更新设备凭据（\(status)）。", "Could not update device credentials (\(status)).")) }
    }
    static func forgetPeer() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                   kSecAttrAccount: "trusted-peer"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RelayError.message(L10n.localized("无法解除配对（\(status)）。", "Could not remove pairing (\(status)).")) }
    }
    static func signingKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try read("signing-key") { return try .init(rawRepresentation: data) }
        let key = Curve25519.Signing.PrivateKey()
        try write(key.rawRepresentation, account: "signing-key")
        return key
    }
}
