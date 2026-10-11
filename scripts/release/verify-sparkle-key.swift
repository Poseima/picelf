import Foundation
import CryptoKit

// Never print key contents. This only checks that the CI secret can sign updates
// trusted by the public key embedded in the candidate app.
do {
    guard CommandLine.arguments.count == 3 else { throw Failure.invalidArguments }
    let keyFile = URL(fileURLWithPath: CommandLine.arguments[1])
    let infoFile = URL(fileURLWithPath: CommandLine.arguments[2])
    let keyText = try String(contentsOf: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyBytes = Data(base64Encoded: keyText), keyBytes.count == 32 else { throw Failure.invalidKey }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyBytes)
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoFile), format: nil) as? [String: Any]
    guard let publicText = info?["SUPublicEDKey"] as? String,
          Data(base64Encoded: publicText) == key.publicKey.rawRepresentation else { throw Failure.publicKeyMismatch }
    print("Sparkle signing key matches the candidate application's public key")
} catch {
    fputs("Sparkle key verification failed: \(error)\n", stderr)
    exit(1)
}

enum Failure: Error { case invalidArguments, invalidKey, publicKeyMismatch }
