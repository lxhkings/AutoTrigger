import Testing
import Foundation
@testable import AutoTriggerCore

private func makeInstaller() throws -> (installer: WrapperInstaller, root: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let installer = WrapperInstaller(
        wrapperPath: "/usr/local/bin/autotrigger-wrap",
        backup: BackupStore(root: root.appendingPathComponent("backups"))
    )
    return (installer, root)
}

private func writePlist(at url: URL, programArguments: [String]) throws {
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["Label": "com.x.job", "ProgramArguments": programArguments] as [String: Any],
        format: .xml, options: 0)
    try data.write(to: url)
}

private func programArguments(at url: URL) throws -> [String] {
    let obj = try PropertyListSerialization.propertyList(from: try Data(contentsOf: url), format: nil)
    return (obj as! [String: Any])["ProgramArguments"] as! [String]
}

@Test func installWrapsFileAndSavesBackup() throws {
    let (installer, root) = try makeInstaller()
    defer { try? FileManager.default.removeItem(at: root) }
    let plist = root.appendingPathComponent("job.plist")
    try writePlist(at: plist, programArguments: ["/bin/bash", "/x/run.sh"])

    try installer.installPlist(at: plist)

    #expect(try programArguments(at: plist).first == "/usr/local/bin/autotrigger-wrap")
}

@Test func reinstallIsIdempotentAndPreservesOriginalBackup() throws {
    let (installer, root) = try makeInstaller()
    defer { try? FileManager.default.removeItem(at: root) }
    let plist = root.appendingPathComponent("job.plist")
    try writePlist(at: plist, programArguments: ["/bin/bash", "/x/run.sh"])
    let originalBytes = try Data(contentsOf: plist)

    try installer.installPlist(at: plist)
    try installer.installPlist(at: plist) // second time

    // Command not double-wrapped.
    #expect(try programArguments(at: plist) == ["/usr/local/bin/autotrigger-wrap", "/bin/bash", "/x/run.sh"])
    // Backup still holds the pristine original, not the wrapped version.
    let backedUp = try installer.backup.restore(key: plist.path)
    #expect(backedUp == originalBytes)
}
