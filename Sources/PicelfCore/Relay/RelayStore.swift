import Foundation
import Combine

@MainActor
final class RelayStore: ObservableObject {
    @Published private(set) var tasks: [RelayTask] = []
    private(set) var cancelledIDs = Set<UUID>()
    // Tiny receipts outlive large image history, so an old retry can never copy again.
    private(set) var completedRevisions: [UUID: Int] = [:]
    let directory: URL
    private let fm = FileManager.default
    init(directory: URL = AppDataPaths.appSupportDirectory.appendingPathComponent("relay", isDirectory: true)) throws {
        self.directory = directory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tombstones = directory.appendingPathComponent("cancelled.json")
        if fm.fileExists(atPath: tombstones.path) {
            cancelledIDs = try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: tombstones))
        }
        let receipts = directory.appendingPathComponent("completed.json")
        if fm.fileExists(atPath: receipts.path) {
            completedRevisions = try JSONDecoder().decode([UUID: Int].self, from: Data(contentsOf: receipts))
        }
        let children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for folder in children where UUID(uuidString: folder.lastPathComponent) != nil {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("task.json")),
                  var task = try? JSONDecoder().decode(RelayTask.self, from: data),
                  task.id.uuidString == folder.lastPathComponent else { continue }
            // An interrupted paste is never replayed automatically after restart.
            if task.state == .copying { task.state = .copyFailed }
            tasks.append(task)
        }
        tasks.sort { $0.createdAt < $1.createdAt }
    }
    func task(_ id: UUID) -> RelayTask? { tasks.first { $0.id == id } }
    func url(_ id: UUID, _ name: String) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(name)
    }
    func data(_ id: UUID, _ name: String) throws -> Data { try Data(contentsOf: url(id, name)) }
    func save(_ task: RelayTask, base: Data? = nil, ink: Data? = nil, result: Data? = nil, padText: Data? = nil) throws {
        if let padText { _ = try RelayTextDocument.decode(padText) }
        if task.state == .cancelled { try markCancelled(task.id) }
        let folder = directory.appendingPathComponent(task.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let base { try base.write(to: url(task.id, "base.png"), options: .atomic) }
        if let padText {
            try padText.write(to: url(task.id, "pad-text.json"), options: .atomic)
        }
        if let ink { try ink.write(to: url(task.id, "ink.drawing"), options: .atomic) }
        if let result { try result.write(to: url(task.id, "result.png"), options: .atomic) }
        // Write metadata last: it is the transaction's commit marker.
        try JSONEncoder().encode(task).write(to: url(task.id, "task.json"), options: .atomic)
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task); tasks.sort { $0.createdAt < $1.createdAt } }
    }
    private func markCancelled(_ id: UUID) throws {
        var updated = cancelledIDs; updated.insert(id)
        try JSONEncoder().encode(updated).write(to: directory.appendingPathComponent("cancelled.json"), options: .atomic)
        cancelledIDs = updated
    }
    func remove(_ id: UUID) throws {
        if let task = task(id) {
            if task.state == .completed {
                var updated = completedRevisions; updated[id] = task.receiptRevision ?? task.revision
                try JSONEncoder().encode(updated).write(to: directory.appendingPathComponent("completed.json"), options: .atomic)
                completedRevisions = updated
            } else { try markCancelled(id) }
        }
        if fm.fileExists(atPath: url(id, "task.json").path) {
            try fm.removeItem(at: directory.appendingPathComponent(id.uuidString))
        }
        tasks.removeAll { $0.id == id }
    }
    func prune() throws {
        let history = tasks.filter { $0.state == .completed }.sorted { $0.updatedAt > $1.updatedAt }
        var bytes = 0
        for (index, task) in history.enumerated() {
            let files = (try? fm.contentsOfDirectory(at: url(task.id, "task.json").deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
            let sizes = files.map { file -> Int in
                let attributes = try? fm.attributesOfItem(atPath: file.path)
                return (attributes?[.size] as? NSNumber)?.intValue ?? 0
            }
            bytes += sizes.reduce(0, +)
            if index >= RelayLimits.historyCount || bytes > RelayLimits.historyBytes { try remove(task.id) }
        }
    }
}
