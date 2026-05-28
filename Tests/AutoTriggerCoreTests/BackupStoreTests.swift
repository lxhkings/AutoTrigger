import Testing
import Foundation
@testable import AutoTriggerCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func backupSaveRestoreRoundTripsExactBytes() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = BackupStore(root: root)

    let key = "/Users/me/Library/LaunchAgents/com.example.backup.plist"
    let original = Data([0x00, 0x01, 0xFF, 0x42, 0x0A])

    #expect(store.hasBackup(key: key) == false)
    try store.save(key: key, data: original)
    #expect(store.hasBackup(key: key) == true)

    let restored = try store.restore(key: key)
    #expect(restored == original)
}

@Test func backupKeysWithSlashesDoNotCollideOrEscapeRoot() throws {
    let root = try tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = BackupStore(root: root)

    try store.save(key: "/a/b", data: Data("ab".utf8))
    try store.save(key: "/a/c", data: Data("ac".utf8))

    #expect(try store.restore(key: "/a/b") == Data("ab".utf8))
    #expect(try store.restore(key: "/a/c") == Data("ac".utf8))
}
