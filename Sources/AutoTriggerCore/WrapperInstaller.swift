import Foundation

/// Installs/uninstalls the monitoring wrapper for launchd plist files.
/// Install snapshots the pristine original before mutating; uninstall replays
/// that snapshot byte-for-byte. Applying the change to the *running* launchd
/// (bootout/bootstrap) is a separate side effect handled outside this type.
public struct WrapperInstaller {
    public let wrapperPath: String
    public let backup: BackupStore

    public init(wrapperPath: String, backup: BackupStore) {
        self.wrapperPath = wrapperPath
        self.backup = backup
    }

    public func installPlist(at url: URL) throws {
        let current = try Data(contentsOf: url)
        // Snapshot the pristine original exactly once, before any mutation.
        if !backup.hasBackup(key: url.path) {
            try backup.save(key: url.path, data: current)
        }
        let wrapper = PlistWrapper(wrapperPath: wrapperPath)
        if try wrapper.isWrapped(current) { return } // idempotent
        let wrapped = try wrapper.wrap(current)
        try AtomicWriter.write(wrapped, to: url)
    }

    public func uninstallPlist(at url: URL) throws {
        guard backup.hasBackup(key: url.path) else { return }
        let original = try backup.restore(key: url.path)
        try AtomicWriter.write(original, to: url)
    }
}
