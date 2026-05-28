import Testing
import Foundation
@testable import AutoTriggerCore

@Test func atomicWriteThenReadRoundTrips() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("out.txt")
    let payload = Data("hello \u{4e16}\u{754c}".utf8)

    try AtomicWriter.write(payload, to: url)

    let readBack = try Data(contentsOf: url)
    #expect(readBack == payload)
}
