import Foundation

/// Stores exact original bytes of files we are about to modify, keyed by the
/// file's absolute path. Restore replays these bytes verbatim — we never
/// reconstruct an original by un-transforming a wrapped file.
public struct BackupStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Maps an arbitrary path key to a flat filename inside `root`.
    /// base64url-encoding the key guarantees no slashes leak into the path
    /// (so a key can never escape `root`) and no two distinct keys collide.
    private func backupURL(for key: String) -> URL {
        let encoded = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return root.appendingPathComponent(encoded).appendingPathExtension("bak")
    }

    public func hasBackup(key: String) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(for: key).path)
    }

    public func save(key: String, data: Data) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try AtomicWriter.write(data, to: backupURL(for: key))
    }

    public func restore(key: String) throws -> Data {
        try Data(contentsOf: backupURL(for: key))
    }
}
