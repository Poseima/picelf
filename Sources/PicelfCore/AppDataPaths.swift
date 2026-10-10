import Foundation

enum AppDataPaths {
    private static var baseIdentifier: String {
        let fallback = "com.picelf.open.app"
        guard let bundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return fallback
        }
        return bundleIdentifier
    }

    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(baseIdentifier, isDirectory: true)
    }

    static var workbenchResultsDirectory: URL {
        appSupportDirectory.appendingPathComponent("workbench-results", isDirectory: true)
    }

    static var workbenchJobsFileURL: URL {
        appSupportDirectory.appendingPathComponent("workbench-jobs.json")
    }

    static var pinnedStateFileURL: URL {
        appSupportDirectory.appendingPathComponent("pinned-state.json")
    }

    static var translationCacheDirectory: URL {
        appSupportDirectory.appendingPathComponent("translation-cache", isDirectory: true)
    }
}

enum AppDataHygiene {
    @discardableResult
    static func purgeWorkbenchTestArtifactsInTemporaryDirectory(fileManager: FileManager = .default) -> Int {
        let tempDirectory = fileManager.temporaryDirectory
        guard let urls = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removed = 0
        for url in urls {
            let name = url.lastPathComponent
            let isTestFramesDirectory = name.hasPrefix("picelf-workbench-tests-")
            let isTestJobsFile = name.hasPrefix("picelf-workbench-jobs-") && name.hasSuffix(".json")
            guard isTestFramesDirectory || isTestJobsFile else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }
}
