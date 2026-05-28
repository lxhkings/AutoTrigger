import Foundation

public enum AtomicWriter {
    /// Writes data to `url` atomically (temp file + rename), so a crash mid-write
    /// never leaves a partially written file at `url`.
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
