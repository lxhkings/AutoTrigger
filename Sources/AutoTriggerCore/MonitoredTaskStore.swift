import Foundation

public enum MonitoredTaskStoreError: Error {
    case decode(String)
}

/// JSON-backed persistence for the monitored-task list. Missing file reads as
/// empty (first run); writes are atomic and create the parent directory.
public final class MonitoredTaskStore {
    private let fileURL: URL

    public init(fileURL: URL = AutoTriggerPaths.monitoredTasksFile) {
        self.fileURL = fileURL
    }

    public func load() throws -> [MonitoredTask] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode([MonitoredTask].self, from: data)
        } catch {
            throw MonitoredTaskStoreError.decode("\(error)")
        }
    }

    public func save(_ tasks: [MonitoredTask]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        try AtomicWriter.write(data, to: fileURL)
    }

    /// Adds the task, replacing any existing task with the same id.
    public func add(_ task: MonitoredTask) throws {
        var tasks = try load()
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
        try save(tasks)
    }

    public func remove(id: String) throws {
        var tasks = try load()
        tasks.removeAll { $0.id == id }
        try save(tasks)
    }
}
