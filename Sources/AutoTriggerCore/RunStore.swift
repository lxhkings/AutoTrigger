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

    public func insert(_ record: RunRecord) throws {
        let sql = """
            INSERT INTO runs (task_label, started_at, finished_at, exit_code, stdout, stderr)
            VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RunStoreError.prepare(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        let out = RunRecord.truncate(record.stdout, max: maxOutputChars)
        let err = RunRecord.truncate(record.stderr, max: maxOutputChars)
        sqlite3_bind_text(stmt, 1, record.taskLabel, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, record.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, record.finishedAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 4, record.exitCode)
        sqlite3_bind_text(stmt, 5, out, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, err, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw RunStoreError.exec(lastError) }
        try pruneRetention(taskLabel: record.taskLabel)
    }

    public func recent(taskLabel: String, limit: Int) throws -> [RunRecord] {
        let sql = """
            SELECT task_label, started_at, finished_at, exit_code, stdout, stderr
            FROM runs WHERE task_label = ? ORDER BY id DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RunStoreError.prepare(lastError)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, taskLabel, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var out: [RunRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(RunRecord(
                taskLabel: String(cString: sqlite3_column_text(stmt, 0)),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                finishedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                exitCode: sqlite3_column_int(stmt, 3),
                stdout: String(cString: sqlite3_column_text(stmt, 4)),
                stderr: String(cString: sqlite3_column_text(stmt, 5))
            ))
        }
        return out
    }

    /// Deletes all but the newest `retentionPerTask` rows for one task.
    func pruneRetention(taskLabel: String) throws {
        let sql = """
            DELETE FROM runs WHERE task_label = ?1 AND id NOT IN (
                SELECT id FROM runs WHERE task_label = ?1 ORDER BY id DESC LIMIT ?2
            );
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RunStoreError.prepare(lastError)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, taskLabel, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(retentionPerTask))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw RunStoreError.exec(lastError) }
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
