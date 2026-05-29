import Testing
import Foundation
@testable import AutoTriggerCore

@Suite struct MonitoredTaskStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("monitored-tasks.json")
    }

    private func sample(_ id: String) -> MonitoredTask {
        MonitoredTask(id: id, displayName: id, expectedInterval: 3_600, grace: 600, source: .manual)
    }

    @Test func loadMissingFileReturnsEmpty() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        #expect(try store.load().isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        let tasks = [sample("a"), sample("b")]
        try store.save(tasks)
        #expect(try store.load() == tasks)
    }

    @Test func saveCreatesMissingParentDirectory() throws {
        // fileURL is two levels below a non-existent dir.
        let url = tempFile()
        let store = MonitoredTaskStore(fileURL: url)
        try store.save([sample("a")])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptFileThrowsDecodeError() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = MonitoredTaskStore(fileURL: url)
        #expect(throws: MonitoredTaskStoreError.self) { try store.load() }
    }

    @Test func addReplacesByID() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        try store.add(sample("a"))
        var renamed = sample("a"); renamed.displayName = "Renamed"
        try store.add(renamed)
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.displayName == "Renamed")
    }

    @Test func removeDeletesByID() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        try store.save([sample("a"), sample("b")])
        try store.remove(id: "a")
        #expect(try store.load().map(\.id) == ["b"])
    }
}
