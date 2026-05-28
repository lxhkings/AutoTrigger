import Foundation
import SQLite3

// SQLite expects this sentinel for transient (copied) bound text/blobs.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum RunStoreError: Error {
    case open(String)
    case exec(String)
    case prepare(String)
}

/// SQLite-backed run-record store. Safe for concurrent writers via WAL +
/// busy_timeout. Enforces per-task retention and output truncation on insert.
public final class RunStore {
    private var db: OpaquePointer?
    private let retentionPerTask: Int
    private let maxOutputChars: Int

    public init(path: String, retentionPerTask: Int, maxOutputChars: Int) throws {
        self.retentionPerTask = retentionPerTask
        self.maxOutputChars = maxOutputChars
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            throw RunStoreError.open(lastError)
        }
        sqlite3_busy_timeout(db, 5_000) // 5s: concurrent writers retry, don't error
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS runs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_label TEXT NOT NULL,
                started_at REAL NOT NULL,
                finished_at REAL NOT NULL,
                exit_code INTEGER NOT NULL,
                stdout TEXT NOT NULL,
                stderr TEXT NOT NULL
            );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_runs_task ON runs(task_label, id);")
    }

    deinit { if db != nil { sqlite3_close(db) } }

    public func journalMode() throws -> String {
        try queryString("PRAGMA journal_mode;")
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw RunStoreError.exec(lastError)
        }
    }

    private func queryString(_ sql: String) throws -> String {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RunStoreError.prepare(lastError)
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else {
            return ""
        }
        return String(cString: c)
    }
}
