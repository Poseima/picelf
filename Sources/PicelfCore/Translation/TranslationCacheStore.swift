import Foundation
import CryptoKit

enum TranslationCacheStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func imageHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func load(imageHash: String, targetLanguageCode: String) -> TranslationCachePayload? {
        let url = cacheFileURL(imageHash: imageHash, targetLanguageCode: targetLanguageCode)
        guard let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(TranslationCachePayload.self, from: data),
              payload.version == TranslationCachePayload.currentVersion else {
            return nil
        }
        return payload
    }

    static func store(_ payload: TranslationCachePayload) {
        let url = cacheFileURL(imageHash: payload.imageHash, targetLanguageCode: payload.targetLanguageCode)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func cacheFileURL(imageHash: String, targetLanguageCode: String) -> URL {
        let safeTarget = targetLanguageCode
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return AppDataPaths.translationCacheDirectory
            .appendingPathComponent(imageHash, isDirectory: true)
            .appendingPathComponent("\(safeTarget).json")
    }
}
