import Testing
import Foundation
@testable import AutoTriggerCore

private func tempDBURL() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("runs.sqlite")
}

@Test func storeOpensInWALMode() throws {
    let url = try tempDBURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = try RunStore(path: url.path, retentionPerTask: 200, maxOutputChars: 10_000)
    #expect(try store.journalMode().lowercased() == "wal")
}
