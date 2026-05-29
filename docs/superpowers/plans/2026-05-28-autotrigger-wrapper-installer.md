# AutoTrigger Wrapper Installer (T1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the reversible wrapper installer — the P1 data-safety core that lets AutoTrigger intercept a user's launchd/crontab tasks for monitoring, and fully restore them on uninstall.

**Architecture:** A standalone SwiftPM library `AutoTriggerCore` containing pure, unit-testable logic: atomic file writes, an exact-bytes backup store, plist/crontab wrap transforms, and an installer that snapshots originals before wrapping and restores them byte-for-byte on uninstall. The byte-for-byte round-trip is the critical safety invariant. Applying changes to *running* launchd (`launchctl bootout/bootstrap`) is a side effect handled in a thin shell-out layer, flagged as manual/integration — NOT part of the unit-tested core.

**Tech Stack:** Swift 6.3, SwiftPM, Swift Testing (`import Testing`), Foundation (`PropertyListSerialization`, `Data.write(.atomic)`). Target macOS 13+.

**Scope:** This plan is T1 only. T2 (heartbeat LaunchAgent), T3 (SQLite WAL), T4 (history retention), T5 (webhook+Keychain), T6 (CI/notarization) get their own plans. Source design: `~/.gstack/projects/lxhkings-AutoTrigger/xiaohong-main-design-20260528-132758.md`.

---

### Task 0: Scaffold SwiftPM package + Swift Testing

**Files:**
- Create: `Package.swift`
- Create: `Sources/AutoTriggerCore/AutoTriggerCore.swift`
- Test: `Tests/AutoTriggerCoreTests/SmokeTests.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoTriggerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutoTriggerCore", targets: ["AutoTriggerCore"])
    ],
    targets: [
        .target(name: "AutoTriggerCore"),
        .testTarget(name: "AutoTriggerCoreTests", dependencies: ["AutoTriggerCore"])
    ]
)
```

- [ ] **Step 2: Create a placeholder source so the target compiles**

`Sources/AutoTriggerCore/AutoTriggerCore.swift`:

```swift
public enum AutoTriggerCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Write a smoke test**

`Tests/AutoTriggerCoreTests/SmokeTests.swift`:

```swift
import Testing
@testable import AutoTriggerCore

@Test func versionIsSet() {
    #expect(AutoTriggerCore.version == "0.1.0")
}
```

- [ ] **Step 4: Run tests to verify the harness works**

Run: `swift test`
Expected: PASS — `1 test passed`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/AutoTriggerCore/AutoTriggerCore.swift Tests/AutoTriggerCoreTests/SmokeTests.swift
git commit -m "chore: scaffold AutoTriggerCore SwiftPM package with Swift Testing"
```

---

### Task 1: AtomicWriter

Why first: every file mutation in the installer must be atomic (temp + rename) so a crash mid-write never leaves a half-written user config. `Data.write(options: .atomic)` does temp+rename under the hood — we wrap it for a single seam.

**Files:**
- Create: `Sources/AutoTriggerCore/AtomicWriter.swift`
- Test: `Tests/AutoTriggerCoreTests/AtomicWriterTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/AtomicWriterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter atomicWriteThenReadRoundTrips`
Expected: FAIL — `cannot find 'AtomicWriter' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/AtomicWriter.swift`:

```swift
import Foundation

public enum AtomicWriter {
    /// Writes data to `url` atomically (temp file + rename), so a crash mid-write
    /// never leaves a partially written file at `url`.
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter atomicWriteThenReadRoundTrips`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/AtomicWriter.swift Tests/AutoTriggerCoreTests/AtomicWriterTests.swift
git commit -m "feat: add AtomicWriter for crash-safe file writes"
```

---

### Task 2: BackupStore (exact-bytes round-trip)

Why: restore-on-uninstall copies back the *exact original bytes* we snapshotted at install time. We never reconstruct the original by un-transforming — we replay the snapshot. This task pins that the store round-trips bytes identically.

**Files:**
- Create: `Sources/AutoTriggerCore/BackupStore.swift`
- Test: `Tests/AutoTriggerCoreTests/BackupStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/BackupStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BackupStore`
Expected: FAIL — `cannot find 'BackupStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/BackupStore.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BackupStore`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/BackupStore.swift Tests/AutoTriggerCoreTests/BackupStoreTests.swift
git commit -m "feat: add BackupStore with exact-bytes round-trip"
```

---

### Task 3: PlistWrapper (wrap launchd ProgramArguments, idempotent)

Why: a launchd task runs `ProgramArguments`. To intercept it, we prepend our wrapper executable path so launchd runs `wrapper original-cmd ...`. Must be idempotent (wrapping an already-wrapped plist is a no-op) and detectable (`isWrapped`).

**Files:**
- Create: `Sources/AutoTriggerCore/PlistWrapper.swift`
- Test: `Tests/AutoTriggerCoreTests/PlistWrapperTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/PlistWrapperTests.swift`:

```swift
import Testing
import Foundation
@testable import AutoTriggerCore

private func plistData(label: String, programArguments: [String]) throws -> Data {
    let dict: [String: Any] = [
        "Label": label,
        "ProgramArguments": programArguments
    ]
    return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
}

private func programArguments(of data: Data) throws -> [String] {
    let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
    let dict = obj as! [String: Any]
    return dict["ProgramArguments"] as! [String]
}

@Test func wrapPrependsWrapperPath() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let original = try plistData(label: "com.x.job", programArguments: ["/bin/bash", "/x/run.sh"])

    let wrapped = try w.wrap(original)

    #expect(try programArguments(of: wrapped) == ["/usr/local/bin/autotrigger-wrap", "/bin/bash", "/x/run.sh"])
}

@Test func wrapIsIdempotent() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let original = try plistData(label: "com.x.job", programArguments: ["/bin/bash", "/x/run.sh"])

    let once = try w.wrap(original)
    let twice = try w.wrap(once)

    #expect(try programArguments(of: twice) == ["/usr/local/bin/autotrigger-wrap", "/bin/bash", "/x/run.sh"])
}

@Test func isWrappedReflectsState() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let original = try plistData(label: "com.x.job", programArguments: ["/bin/bash", "/x/run.sh"])

    #expect(try w.isWrapped(original) == false)
    #expect(try w.isWrapped(w.wrap(original)) == true)
}

@Test func wrapThrowsWhenNoProgramArguments() throws {
    let w = PlistWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    // A plist with no ProgramArguments (e.g. uses Program key only) is unsupported in v1.
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["Label": "com.x.job"] as [String: Any], format: .xml, options: 0)

    #expect(throws: PlistWrapperError.missingProgramArguments) {
        try w.wrap(data)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PlistWrapper`
Expected: FAIL — `cannot find 'PlistWrapper' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/PlistWrapper.swift`:

```swift
import Foundation

public enum PlistWrapperError: Error, Equatable {
    case missingProgramArguments
    case notADictionary
}

/// Wraps a launchd plist's `ProgramArguments` by prepending the wrapper
/// executable path, so launchd runs `wrapper <original args...>`.
/// `wrapperPath` doubles as the "is this ours?" marker.
public struct PlistWrapper {
    public let wrapperPath: String

    public init(wrapperPath: String) {
        self.wrapperPath = wrapperPath
    }

    public func isWrapped(_ data: Data) throws -> Bool {
        let args = try programArguments(from: try dictionary(from: data))
        return args.first == wrapperPath
    }

    public func wrap(_ data: Data) throws -> Data {
        var dict = try dictionary(from: data)
        var args = try programArguments(from: dict)
        if args.first == wrapperPath { return data } // idempotent
        args.insert(wrapperPath, at: 0)
        dict["ProgramArguments"] = args
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func dictionary(from data: Data) throws -> [String: Any] {
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = obj as? [String: Any] else { throw PlistWrapperError.notADictionary }
        return dict
    }

    private func programArguments(from dict: [String: Any]) throws -> [String] {
        guard let args = dict["ProgramArguments"] as? [String], !args.isEmpty else {
            throw PlistWrapperError.missingProgramArguments
        }
        return args
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PlistWrapper`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/PlistWrapper.swift Tests/AutoTriggerCoreTests/PlistWrapperTests.swift
git commit -m "feat: add PlistWrapper for idempotent launchd ProgramArguments wrapping"
```

---

### Task 4: CrontabWrapper (wrap a crontab command, skip comments/env)

Why: crontab lines are `<schedule> <command>`. We prepend the wrapper to the command part only, and must never touch comments (`#...`), blank lines, or environment-variable lines (`FOO=bar`). Schedule supports the 5-field form and `@`-shortcuts (`@daily` etc).

**Files:**
- Create: `Sources/AutoTriggerCore/CrontabWrapper.swift`
- Test: `Tests/AutoTriggerCoreTests/CrontabWrapperTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/CrontabWrapperTests.swift`:

```swift
import Testing
@testable import AutoTriggerCore

@Test func wrapsFiveFieldScheduleCommand() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "*/5 * * * * /bin/bash /x/run.sh arg"
    #expect(w.wrap(line) == "*/5 * * * * /usr/local/bin/autotrigger-wrap /bin/bash /x/run.sh arg")
}

@Test func wrapsAtShortcutSchedule() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "@daily /x/backup.sh"
    #expect(w.wrap(line) == "@daily /usr/local/bin/autotrigger-wrap /x/backup.sh")
}

@Test func leavesCommentsBlanksAndEnvUntouched() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    #expect(w.wrap("# a comment") == "# a comment")
    #expect(w.wrap("") == "")
    #expect(w.wrap("PATH=/usr/bin:/bin") == "PATH=/usr/bin:/bin")
}

@Test func crontabWrapIsIdempotent() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "0 9 * * 1 /x/weekly.sh"
    let once = w.wrap(line)
    #expect(w.wrap(once) == once)
}

@Test func crontabIsWrappedReflectsState() {
    let w = CrontabWrapper(wrapperPath: "/usr/local/bin/autotrigger-wrap")
    let line = "0 9 * * 1 /x/weekly.sh"
    #expect(w.isWrapped(line) == false)
    #expect(w.isWrapped(w.wrap(line)) == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CrontabWrapper`
Expected: FAIL — `cannot find 'CrontabWrapper' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/CrontabWrapper.swift`:

```swift
import Foundation

/// Wraps the command portion of a crontab line, leaving the schedule fields,
/// comments, blank lines, and environment assignments untouched.
public struct CrontabWrapper {
    public let wrapperPath: String

    public init(wrapperPath: String) {
        self.wrapperPath = wrapperPath
    }

    public func isWrapped(_ line: String) -> Bool {
        guard let split = scheduleCommandSplit(line) else { return false }
        return split.command.hasPrefix(wrapperPath + " ") || split.command == wrapperPath
    }

    public func wrap(_ line: String) -> String {
        guard let split = scheduleCommandSplit(line) else { return line } // comment/blank/env
        if split.command.hasPrefix(wrapperPath + " ") { return line }     // idempotent
        return split.schedule + " " + wrapperPath + " " + split.command
    }

    /// Returns (schedule, command) for a runnable crontab line, or nil for a
    /// comment, blank line, or environment assignment that must not be wrapped.
    private func scheduleCommandSplit(_ line: String) -> (schedule: String, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        // Environment assignment: NAME=value as the first token, no schedule.
        if let eq = trimmed.firstIndex(of: "="),
           !trimmed[..<eq].contains(" "),
           !trimmed.hasPrefix("@"),
           !trimmed.hasPrefix("*"),
           trimmed.first.map({ !$0.isNumber }) ?? false {
            return nil
        }

        if trimmed.hasPrefix("@") {
            // @shortcut command...
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
        }

        // 5 schedule fields, then the command (which may contain spaces).
        let fields = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard fields.count == 6 else { return nil }
        let schedule = fields[0..<5].joined(separator: " ")
        let command = String(fields[5]).trimmingCharacters(in: .whitespaces)
        return (schedule, command)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CrontabWrapper`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/CrontabWrapper.swift Tests/AutoTriggerCoreTests/CrontabWrapperTests.swift
git commit -m "feat: add CrontabWrapper that wraps command and preserves comments/env"
```

---

### Task 5: WrapperInstaller.install (snapshot → wrap → atomic write)

Why: this composes the pieces for launchd plist files. Install must snapshot the original to the backup store *before* mutating, then atomically write the wrapped version. Re-installing must be a no-op (idempotent) and must NOT overwrite the original backup.

**Files:**
- Create: `Sources/AutoTriggerCore/WrapperInstaller.swift`
- Test: `Tests/AutoTriggerCoreTests/WrapperInstallerTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/WrapperInstallerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WrapperInstaller`
Expected: FAIL — `cannot find 'WrapperInstaller' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/WrapperInstaller.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WrapperInstaller`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/WrapperInstaller.swift Tests/AutoTriggerCoreTests/WrapperInstallerTests.swift
git commit -m "feat: add WrapperInstaller.installPlist with one-time backup snapshot"
```

---

### Task 6: WrapperInstaller.uninstall — byte-for-byte round-trip (CRITICAL)

Why: this is the data-safety invariant the whole feature rests on. install → uninstall must leave the user's file *byte-identical* to the original, and leave no wrapper reference behind. If this test ever fails, we are corrupting user configs.

**Files:**
- Modify: `Tests/AutoTriggerCoreTests/WrapperInstallerTests.swift` (add tests; uninstall impl already exists from Task 5)

- [ ] **Step 1: Write the failing test**

Append to `Tests/AutoTriggerCoreTests/WrapperInstallerTests.swift`:

```swift
@Test func installThenUninstallRestoresByteForByte() throws {
    let (installer, root) = try makeInstaller()
    defer { try? FileManager.default.removeItem(at: root) }
    let plist = root.appendingPathComponent("job.plist")
    try writePlist(at: plist, programArguments: ["/bin/bash", "/x/run.sh", "--flag"])
    let originalBytes = try Data(contentsOf: plist)

    try installer.installPlist(at: plist)
    #expect(try Data(contentsOf: plist) != originalBytes) // proves install mutated it

    try installer.uninstallPlist(at: plist)
    let restored = try Data(contentsOf: plist)

    #expect(restored == originalBytes) // CRITICAL: exact restore
    let wrapper = PlistWrapper(wrapperPath: installer.wrapperPath)
    #expect(try wrapper.isWrapped(restored) == false) // no orphaned wrapper ref
}

@Test func uninstallWithoutBackupIsNoOp() throws {
    let (installer, root) = try makeInstaller()
    defer { try? FileManager.default.removeItem(at: root) }
    let plist = root.appendingPathComponent("job.plist")
    try writePlist(at: plist, programArguments: ["/bin/bash", "/x/run.sh"])
    let before = try Data(contentsOf: plist)

    try installer.uninstallPlist(at: plist) // never installed → nothing to restore

    #expect(try Data(contentsOf: plist) == before) // unchanged, no crash
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `swift test --filter WrapperInstaller`
Expected: PASS — uninstall was implemented in Task 5, so these tests should pass immediately and confirm the round-trip invariant. If `installThenUninstallRestoresByteForByte` FAILS, stop and fix `WrapperInstaller` — do not proceed; this is the safety gate.

- [ ] **Step 3: (only if a test failed) Fix the implementation**

If the round-trip failed, the bug is almost certainly in `installPlist` saving a non-pristine backup or `uninstallPlist` not writing the restored bytes. Re-read Task 5's implementation, fix, and re-run until PASS. No code change needed if tests already pass.

- [ ] **Step 4: Run the full suite**

Run: `swift test`
Expected: PASS — all tasks' tests green.

- [ ] **Step 5: Commit**

```bash
git add Tests/AutoTriggerCoreTests/WrapperInstallerTests.swift
git commit -m "test: pin byte-for-byte install/uninstall round-trip invariant"
```

---

## Out of scope for this plan (T1)

- Applying changes to running launchd (`launchctl bootout`/`bootstrap` of the affected plist) — side-effecting, manually/integration tested, lives in a thin shell-out layer added when the menubar app wires this in.
- crontab read/write via `crontab -l` / `crontab <file>` — the `CrontabWrapper` transform is unit-tested here; the actual `crontab` shell-out is the same integration concern as launchctl.
- The wrapper executable itself (`autotrigger-wrap`) that records exit/stdout/stderr — that is T1-adjacent but belongs with the SQLite store (T3); wire after T3 exists.
- Orphan *scanning* across the whole system (find wrapper refs with no backup) — v1 relies on per-file backup presence; full-system orphan sweep is a follow-up TODO.

## Self-Review

- **Spec coverage:** T1 = "reversible wrapper: backup + atomic write + uninstall restore + round-trip test." Covered: AtomicWriter (Task 1), BackupStore (Task 2), PlistWrapper + CrontabWrapper transforms (Tasks 3-4), install/uninstall (Tasks 5-6), round-trip invariant (Task 6). Gap intentionally deferred: live launchctl/crontab application (listed in Out of scope).
- **Placeholder scan:** every code step has complete, compilable Swift. No TBD/TODO in implementation steps.
- **Type consistency:** `WrapperInstaller` exposes `installPlist(at:)` / `uninstallPlist(at:)` and public `backup`/`wrapperPath` (used by tests in Tasks 5-6). `PlistWrapper(wrapperPath:)`, `BackupStore(root:)`, `AtomicWriter.write(_:to:)`, `CrontabWrapper(wrapperPath:)` are consistent across all tasks. `PlistWrapperError.missingProgramArguments` referenced in Task 3 test matches the enum.
