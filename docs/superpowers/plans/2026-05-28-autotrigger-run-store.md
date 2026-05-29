# AutoTrigger Run Store (T3 + T4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A SQLite-backed store of task run records that survives concurrent writes from multiple wrapper processes (WAL + busy_timeout), and enforces per-task retention (keep last N) plus per-record output truncation.

**Architecture:** A `RunStore` type in the existing `AutoTriggerCore` library, backed by raw `SQLite3` (zero external dependency). Opens in WAL mode with a busy timeout so concurrent writers retry instead of erroring. Inserts truncate oversized stdout/stderr at write time and prune to the last N records per task. All logic is unit-tested against a temp-dir database via `swift test`.

**Tech Stack:** Swift 6.3, `import SQLite3` (system library), Swift Testing. Extends the existing `AutoTriggerCore` SwiftPM library (no new package).

**Depends on:** Nothing. This is the foundation T2 (heartbeat) and the wrapper's run-recording build on.

**Decision:** raw SQLite3, not GRDB — zero dependency keeps the notarized distribution's supply-chain surface empty. If a future plan needs migrations/Codable rows, revisit.

---

### Task 1: RunRecord model + output truncation

**Files:**
- Create: `Sources/AutoTriggerCore/RunRecord.swift`
- Test: `Tests/AutoTriggerCoreTests/RunRecordTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/RunRecordTests.swift`:

```swift
import Testing
import Foundation
@testable import AutoTriggerCore

@Test func truncateLeavesShortStringsUntouched() {
    #expect(RunRecord.truncate("hello", max: 100) == "hello")
}

@Test func truncateCutsLongStringsAndMarks() {
    let long = String(repeating: "x", count: 50)
    let out = RunRecord.truncate(long, max: 10)
    #expect(out.count <= 10 + RunRecord.truncationMarker.count)
    #expect(out.hasSuffix(RunRecord.truncationMarker))
    #expect(out.hasPrefix("xxxxxxxxxx"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RunRecord`
Expected: FAIL — `cannot find 'RunRecord' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/RunRecord.swift`:

```swift
import Foundation

/// One execution of a monitored task.
public struct RunRecord: Equatable, Sendable {
    public let taskLabel: String
    public let startedAt: Date
    public let finishedAt: Date
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(taskLabel: String, startedAt: Date, finishedAt: Date,
                exitCode: Int32, stdout: String, stderr: String) {
        self.taskLabel = taskLabel
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public static let truncationMarker = "\n…[truncated]"

    /// Caps a string to `max` characters, appending a marker when cut.
    public static func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + truncationMarker
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RunRecord`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/RunRecord.swift Tests/AutoTriggerCoreTests/RunRecordTests.swift
git commit -m "feat: add RunRecord model with output truncation helper"
```

---

### Task 2: RunStore opens in WAL mode

**Files:**
- Create: `Sources/AutoTriggerCore/RunStore.swift`
- Test: `Tests/AutoTriggerCoreTests/RunStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/RunStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter storeOpensInWALMode`
Expected: FAIL — `cannot find 'RunStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/RunStore.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter storeOpensInWALMode`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/RunStore.swift Tests/AutoTriggerCoreTests/RunStoreTests.swift
git commit -m "feat: add RunStore opening SQLite in WAL mode with busy_timeout"
```

---

### Task 3: insert + fetch run records

**Files:**
- Modify: `Sources/AutoTriggerCore/RunStore.swift`
- Modify: `Tests/AutoTriggerCoreTests/RunStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoTriggerCoreTests/RunStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter insertThenFetchReturnsRecordsNewestFirst`
Expected: FAIL — `value of type 'RunStore' has no member 'insert'`.

- [ ] **Step 3: Write minimal implementation**

Add to `RunStore` (inside the class, before the closing brace):

```swift
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

    /// Stub for now — filled in Task 5. Keeps insert() compiling.
    func pruneRetention(taskLabel: String) throws {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter insertThenFetchReturnsRecordsNewestFirst`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/RunStore.swift Tests/AutoTriggerCoreTests/RunStoreTests.swift
git commit -m "feat: add RunStore insert and recent-fetch (newest first)"
```

---

### Task 4: concurrent writers don't error (WAL + busy_timeout)

**Files:**
- Modify: `Tests/AutoTriggerCoreTests/RunStoreTests.swift`

- [ ] **Step 1: Write the failing/confirming test**

Append:

```swift
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
```

- [ ] **Step 2: Run test**

Run: `swift test --filter concurrentInsertsAllSucceed`
Expected: PASS — `SQLITE_OPEN_FULLMUTEX` + `busy_timeout` (set in Task 2) serialize writers so all 200 inserts land. If it FAILS with `database is locked`, the busy_timeout from Task 2 is missing — fix Task 2's `sqlite3_busy_timeout` call.

- [ ] **Step 3: Commit**

```bash
git add Tests/AutoTriggerCoreTests/RunStoreTests.swift
git commit -m "test: pin concurrent-writer safety for RunStore (WAL + busy_timeout)"
```

---

### Task 5: per-task retention (keep last N)

**Files:**
- Modify: `Sources/AutoTriggerCore/RunStore.swift`
- Modify: `Tests/AutoTriggerCoreTests/RunStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Append:

```swift
@Test func retentionKeepsOnlyLastNPerTask() throws {
    let url = try tempDBURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try RunStore(path: url.path, retentionPerTask: 5, maxOutputChars: 10_000)

    let base = Date(timeIntervalSince1970: 0)
    for i in 0..<12 {
        let t = base.addingTimeInterval(Double(i))
        try store.insert(RunRecord(taskLabel: "com.x.job", startedAt: t, finishedAt: t,
                                   exitCode: Int32(i), stdout: "", stderr: ""))
    }

    let rows = try store.recent(taskLabel: "com.x.job", limit: 100)
    #expect(rows.count == 5)                 // pruned to N
    #expect(rows.map(\.exitCode) == [11, 10, 9, 8, 7]) // newest 5 kept
}

@Test func retentionIsPerTaskNotGlobal() throws {
    let url = try tempDBURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try RunStore(path: url.path, retentionPerTask: 2, maxOutputChars: 10_000)
    let t = Date(timeIntervalSince1970: 0)
    for i in 0..<3 { try store.insert(RunRecord(taskLabel: "a", startedAt: t.addingTimeInterval(Double(i)), finishedAt: t, exitCode: 0, stdout: "", stderr: "")) }
    for i in 0..<3 { try store.insert(RunRecord(taskLabel: "b", startedAt: t.addingTimeInterval(Double(i)), finishedAt: t, exitCode: 0, stdout: "", stderr: "")) }

    #expect(try store.recent(taskLabel: "a", limit: 100).count == 2)
    #expect(try store.recent(taskLabel: "b", limit: 100).count == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter retention`
Expected: FAIL — too many rows kept (prune is a no-op stub).

- [ ] **Step 3: Replace the `pruneRetention` stub with the real implementation**

In `RunStore.swift`, replace `func pruneRetention(taskLabel: String) throws {}` with:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter retention`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/RunStore.swift Tests/AutoTriggerCoreTests/RunStoreTests.swift
git commit -m "feat: enforce per-task retention (keep last N) on insert"
```

---

### Task 6: output truncation persists

**Files:**
- Modify: `Tests/AutoTriggerCoreTests/RunStoreTests.swift`

- [ ] **Step 1: Write the failing/confirming test**

Append:

```swift
@Test func oversizedOutputIsTruncatedInStore() throws {
    let url = try tempDBURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try RunStore(path: url.path, retentionPerTask: 200, maxOutputChars: 100)

    let huge = String(repeating: "z", count: 5_000)
    let t = Date(timeIntervalSince1970: 0)
    try store.insert(RunRecord(taskLabel: "com.x.job", startedAt: t, finishedAt: t,
                               exitCode: 0, stdout: huge, stderr: huge))

    let row = try store.recent(taskLabel: "com.x.job", limit: 1)[0]
    #expect(row.stdout.count <= 100 + RunRecord.truncationMarker.count)
    #expect(row.stdout.hasSuffix(RunRecord.truncationMarker))
}
```

- [ ] **Step 2: Run test**

Run: `swift test --filter oversizedOutputIsTruncatedInStore`
Expected: PASS — `insert` already truncates via `RunRecord.truncate` (Task 3). If it FAILS, `insert` is binding `record.stdout` instead of the truncated `out` — fix Task 3's bind.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS — all RunStore + T1 tests green.

- [ ] **Step 4: Commit**

```bash
git add Tests/AutoTriggerCoreTests/RunStoreTests.swift
git commit -m "test: pin output truncation persists through RunStore insert"
```

---

## Out of scope for this plan

- The `autotrigger-wrap` executable that actually runs a task and calls `store.insert` — that wires RunStore into a real wrapper binary; belongs in the wrapper-executable plan (after this store exists).
- DB file location / migration across app versions — v1 uses a fixed schema; add a `user_version` migration scheme when the schema first changes.
- Vacuuming / WAL checkpoint tuning — defaults are fine at this scale (retention caps total rows).

## Self-Review

- **Spec coverage:** T3 = "SQLite WAL + 短事务 + busy_timeout 写重试" → Tasks 2 (WAL+timeout), 3 (single-statement inserts), 4 (concurrent safety). T4 = "每任务最近 N 条 + 单条 output 截断" → Tasks 5 (retention), 6 (truncation) + Task 1 (truncate helper).
- **Placeholder scan:** the `pruneRetention` stub in Task 3 is intentional and explicitly replaced in Task 5 (TDD: insert/fetch first, retention second). No other placeholders; all SQLite calls are complete.
- **Type consistency:** `RunStore(path:retentionPerTask:maxOutputChars:)`, `insert(_:)`, `recent(taskLabel:limit:)`, `journalMode()`, `pruneRetention(taskLabel:)`, `RunRecord(taskLabel:startedAt:finishedAt:exitCode:stdout:stderr:)`, `RunRecord.truncate(_:max:)`, `RunRecord.truncationMarker` consistent across all tasks. `SQLITE_TRANSIENT` defined once at file scope.
