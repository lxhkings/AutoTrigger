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

@Test func insertThenFetchReturnsRecordsNewestFirst() throws {
    let url = try tempDBURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try RunStore(path: url.path, retentionPerTask: 200, maxOutputChars: 10_000)

    let t0 = Date(timeIntervalSince1970: 1_000)
    let r1 = RunRecord(taskLabel: "com.x.job", startedAt: t0, finishedAt: t0.addingTimeInterval(1),
                       exitCode: 0, stdout: "ok", stderr: "")
    let r2 = RunRecord(taskLabel: "com.x.job", startedAt: t0.addingTimeInterval(60),
                       finishedAt: t0.addingTimeInterval(61), exitCode: 1, stdout: "", stderr: "boom")
    try store.insert(r1)
    try store.insert(r2)

    let rows = try store.recent(taskLabel: "com.x.job", limit: 10)
    #expect(rows.count == 2)
    #expect(rows[0].exitCode == 1)   // newest first
    #expect(rows[1].exitCode == 0)
    #expect(rows[0].stderr == "boom")
}

@Test func concurrentInsertsAllSucceed() throws {
    let url = try tempDBURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try RunStore(path: url.path, retentionPerTask: 10_000, maxOutputChars: 10_000)

    let n = 200
    let errorCount = LockedCounter()
    DispatchQueue.concurrentPerform(iterations: n) { i in
        let now = Date()
        let rec = RunRecord(taskLabel: "com.x.job", startedAt: now, finishedAt: now,
                            exitCode: 0, stdout: "i=\(i)", stderr: "")
        do { try store.insert(rec) } catch { errorCount.increment() }
    }

    #expect(errorCount.value == 0)
    #expect(try store.recent(taskLabel: "com.x.job", limit: 100_000).count == n)
}

final class LockedCounter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
