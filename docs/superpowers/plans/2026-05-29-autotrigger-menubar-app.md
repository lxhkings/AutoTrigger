# AutoTrigger Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A status-first macOS menu bar app that shows monitored-task health at a glance, drills into recent runs, and edits monitored-task config + the alert webhook URL.

**Architecture:** Phase 1 adds pure, unit-tested types to the existing SwiftPM package `AutoTriggerCore` (config store + health computation + shared constants). Phase 2 adds an Xcode app target (generated from a committed `project.yml` via `xcodegen`) using SwiftUI `MenuBarExtra`, which links the local package and observes a view model that calls into the core. The dashboard reads `RunStore`; real run data arrives later via the wrapper (out of scope) and is validated here with a `#if DEBUG` demo-seed button.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`import Testing`), SwiftUI `MenuBarExtra` (macOS 13+), `xcodegen` (dev tool, generates `.xcodeproj` from YAML), `xcodebuild`.

**Spec:** `docs/superpowers/specs/2026-05-29-autotrigger-menubar-app-design.md`

---

## File Structure

**Phase 1 — core (SwiftPM package, TDD):**
- Create `Sources/AutoTriggerCore/SecretKeys.swift` — shared Keychain key constant.
- Create `Sources/AutoTriggerCore/MonitoredTask.swift` — Codable task config model.
- Create `Sources/AutoTriggerCore/AutoTriggerPaths.swift` — single source for Application Support paths.
- Create `Sources/AutoTriggerCore/MonitoredTaskStore.swift` — JSON-backed task config CRUD.
- Create `Sources/AutoTriggerCore/TaskHealth.swift` — `TaskHealth` enum, aggregate, `TaskHealthEvaluator`.
- Create `Tests/AutoTriggerCoreTests/SecretKeysTests.swift`, `MonitoredTaskTests.swift`, `MonitoredTaskStoreTests.swift`, `TaskHealthTests.swift`.

**Phase 2 — app (Xcode project, integration/manual):**
- Create `App/project.yml` — xcodegen spec (target `AutoTrigger`, scheme `AutoTrigger`, links package).
- Create `App/AutoTrigger/AutoTriggerApp.swift` — `@main`, `MenuBarExtra` + `Settings` scenes.
- Create `App/AutoTrigger/MenuBarViewModel.swift` — `@MainActor ObservableObject`, polling + store wiring.
- Create `App/AutoTrigger/HealthDisplay.swift` — `TaskHealth` → SF Symbol / color / label.
- Create `App/AutoTrigger/DashboardView.swift` — task list (the `MenuBarExtra` content).
- Create `App/AutoTrigger/TaskDetailView.swift` — recent runs for one task.
- Create `App/AutoTrigger/SettingsView.swift` — task CRUD + webhook URL.
- Modify `.github/workflows/release.yml` — replace the placeholder `Build .app` step.

---

## Phase 1 — Core (AutoTriggerCore)

### Task 1: SecretKeys constant

**Files:**
- Create: `Sources/AutoTriggerCore/SecretKeys.swift`
- Test: `Tests/AutoTriggerCoreTests/SecretKeysTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoTriggerCoreTests/SecretKeysTests.swift
import Testing
@testable import AutoTriggerCore

@Suite struct SecretKeysTests {
    @Test func webhookURLKeyIsStable() {
        #expect(SecretKeys.webhookURL == "webhook-url")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SecretKeysTests`
Expected: FAIL — `cannot find 'SecretKeys' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AutoTriggerCore/SecretKeys.swift
public enum SecretKeys {
    /// Keychain account key for the alert webhook URL. The app writes it; the
    /// daemon's alert layer reads it. One constant so they never drift.
    public static let webhookURL = "webhook-url"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SecretKeysTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/SecretKeys.swift Tests/AutoTriggerCoreTests/SecretKeysTests.swift
git commit -m "feat: add SecretKeys.webhookURL shared constant"
```

---

### Task 2: MonitoredTask model

**Files:**
- Create: `Sources/AutoTriggerCore/MonitoredTask.swift`
- Test: `Tests/AutoTriggerCoreTests/MonitoredTaskTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoTriggerCoreTests/MonitoredTaskTests.swift
import Testing
import Foundation
@testable import AutoTriggerCore

@Suite struct MonitoredTaskTests {
    @Test func codableRoundTrips() throws {
        let task = MonitoredTask(
            id: "com.example.backup",
            displayName: "Nightly Backup",
            expectedInterval: 86_400,
            grace: 3_600,
            source: .launchd
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(MonitoredTask.self, from: data)
        #expect(decoded == task)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MonitoredTaskTests`
Expected: FAIL — `cannot find 'MonitoredTask' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AutoTriggerCore/MonitoredTask.swift
import Foundation

/// One task under monitoring. `id` equals the `task_label` written into
/// `RunStore`, so a task's runs are fetched via `RunStore.recent(taskLabel: id, ...)`.
public struct MonitoredTask: Codable, Equatable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case launchd, cron, manual }

    public let id: String
    public var displayName: String
    public var expectedInterval: TimeInterval
    public var grace: TimeInterval
    public var source: Source

    public init(id: String, displayName: String, expectedInterval: TimeInterval,
                grace: TimeInterval, source: Source) {
        self.id = id
        self.displayName = displayName
        self.expectedInterval = expectedInterval
        self.grace = grace
        self.source = source
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MonitoredTaskTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/MonitoredTask.swift Tests/AutoTriggerCoreTests/MonitoredTaskTests.swift
git commit -m "feat: add MonitoredTask config model"
```

---

### Task 3: AutoTriggerPaths + MonitoredTaskStore

**Files:**
- Create: `Sources/AutoTriggerCore/AutoTriggerPaths.swift`
- Create: `Sources/AutoTriggerCore/MonitoredTaskStore.swift`
- Test: `Tests/AutoTriggerCoreTests/MonitoredTaskStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/AutoTriggerCoreTests/MonitoredTaskStoreTests.swift
import Testing
import Foundation
@testable import AutoTriggerCore

@Suite struct MonitoredTaskStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("monitored-tasks.json")
    }

    private func sample(_ id: String) -> MonitoredTask {
        MonitoredTask(id: id, displayName: id, expectedInterval: 3_600, grace: 600, source: .manual)
    }

    @Test func loadMissingFileReturnsEmpty() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        #expect(try store.load().isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        let tasks = [sample("a"), sample("b")]
        try store.save(tasks)
        #expect(try store.load() == tasks)
    }

    @Test func saveCreatesMissingParentDirectory() throws {
        // fileURL is two levels below a non-existent dir.
        let url = tempFile()
        let store = MonitoredTaskStore(fileURL: url)
        try store.save([sample("a")])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptFileThrowsDecodeError() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = MonitoredTaskStore(fileURL: url)
        #expect(throws: MonitoredTaskStoreError.self) { try store.load() }
    }

    @Test func addReplacesByID() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        try store.add(sample("a"))
        var renamed = sample("a"); renamed.displayName = "Renamed"
        try store.add(renamed)
        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.displayName == "Renamed")
    }

    @Test func removeDeletesByID() throws {
        let store = MonitoredTaskStore(fileURL: tempFile())
        try store.save([sample("a"), sample("b")])
        try store.remove(id: "a")
        #expect(try store.load().map(\.id) == ["b"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MonitoredTaskStoreTests`
Expected: FAIL — `cannot find 'MonitoredTaskStore' in scope`.

- [ ] **Step 3: Write AutoTriggerPaths**

```swift
// Sources/AutoTriggerCore/AutoTriggerPaths.swift
import Foundation

/// Single source for the on-disk locations AutoTrigger uses, so the app, the
/// daemon, and the stores all agree on one Application Support layout.
public enum AutoTriggerPaths {
    public static var applicationSupportDirectory: URL {
        let expanded = NSString(string: "~/Library/Application Support/AutoTrigger").expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    public static var monitoredTasksFile: URL {
        applicationSupportDirectory.appendingPathComponent("monitored-tasks.json")
    }

    public static var runStorePath: String {
        applicationSupportDirectory.appendingPathComponent("runs.sqlite").path
    }
}
```

- [ ] **Step 4: Write MonitoredTaskStore**

```swift
// Sources/AutoTriggerCore/MonitoredTaskStore.swift
import Foundation

public enum MonitoredTaskStoreError: Error {
    case decode(String)
}

/// JSON-backed persistence for the monitored-task list. Missing file reads as
/// empty (first run); writes are atomic and create the parent directory.
public final class MonitoredTaskStore {
    private let fileURL: URL

    public init(fileURL: URL = AutoTriggerPaths.monitoredTasksFile) {
        self.fileURL = fileURL
    }

    public func load() throws -> [MonitoredTask] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode([MonitoredTask].self, from: data)
        } catch {
            throw MonitoredTaskStoreError.decode("\(error)")
        }
    }

    public func save(_ tasks: [MonitoredTask]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        try AtomicWriter.write(data, to: fileURL)
    }

    /// Adds the task, replacing any existing task with the same id.
    public func add(_ task: MonitoredTask) throws {
        var tasks = try load()
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
        try save(tasks)
    }

    public func remove(id: String) throws {
        var tasks = try load()
        tasks.removeAll { $0.id == id }
        try save(tasks)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter MonitoredTaskStoreTests`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoTriggerCore/AutoTriggerPaths.swift Sources/AutoTriggerCore/MonitoredTaskStore.swift Tests/AutoTriggerCoreTests/MonitoredTaskStoreTests.swift
git commit -m "feat: add AutoTriggerPaths + JSON MonitoredTaskStore"
```

---

### Task 4: TaskHealth + aggregate + TaskHealthEvaluator

**Files:**
- Create: `Sources/AutoTriggerCore/TaskHealth.swift`
- Test: `Tests/AutoTriggerCoreTests/TaskHealthTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/AutoTriggerCoreTests/TaskHealthTests.swift
import Testing
import Foundation
@testable import AutoTriggerCore

@Suite struct TaskHealthTests {
    private let task = MonitoredTask(
        id: "t", displayName: "T", expectedInterval: 3_600, grace: 600, source: .manual
    )

    private func run(exit: Int32, finishedAgo: TimeInterval, now: Date) -> RunRecord {
        let finished = now.addingTimeInterval(-finishedAgo)
        return RunRecord(taskLabel: "t", startedAt: finished.addingTimeInterval(-1),
                         finishedAt: finished, exitCode: exit, stdout: "", stderr: "")
    }

    @Test func neverRanWhenNoRuns() {
        let h = TaskHealthEvaluator().health(task: task, recentRuns: [], now: Date(), asleepSeconds: 0)
        #expect(h == .neverRan)
    }

    @Test func failedWhenLatestExitNonzero() {
        let now = Date()
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 1, finishedAgo: 60, now: now)], now: now, asleepSeconds: 0
        )
        #expect(h == .failed)
    }

    @Test func okWhenRecentSuccessWithinInterval() {
        let now = Date()
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 0, finishedAgo: 60, now: now)], now: now, asleepSeconds: 0
        )
        #expect(h == .ok)
    }

    @Test func overdueWhenSuccessTooOldAndAwake() {
        let now = Date()
        // finished 10000s ago, interval+grace = 4200s, asleep 0 → overdue
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 0, finishedAgo: 10_000, now: now)], now: now, asleepSeconds: 0
        )
        #expect(h == .overdue)
    }

    @Test func notOverdueWhenAsleepThroughTheWindow() {
        let now = Date()
        // finished 10000s ago but machine asleep 9000s → awake elapsed 1000s < 4200s → ok
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 0, finishedAgo: 10_000, now: now)], now: now, asleepSeconds: 9_000
        )
        #expect(h == .ok)
    }

    @Test func aggregateReturnsMostSevere() {
        #expect(TaskHealth.aggregate([.ok, .neverRan, .overdue, .failed]) == .failed)
        #expect(TaskHealth.aggregate([.ok, .overdue]) == .overdue)
        #expect(TaskHealth.aggregate([.ok, .neverRan]) == .neverRan)
        #expect(TaskHealth.aggregate([.ok, .ok]) == .ok)
    }

    @Test func aggregateOfEmptyIsOK() {
        #expect(TaskHealth.aggregate([]) == .ok)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TaskHealthTests`
Expected: FAIL — `cannot find 'TaskHealth' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/AutoTriggerCore/TaskHealth.swift
import Foundation

public enum TaskHealth: Equatable, Sendable {
    case ok        // most recent run succeeded and is within interval + grace
    case neverRan  // no runs recorded yet
    case overdue   // most recent run succeeded but the deadline has passed
    case failed    // most recent run exists with a nonzero exit code

    var severity: Int {
        switch self {
        case .ok:       return 0
        case .neverRan: return 1
        case .overdue:  return 2
        case .failed:   return 3
        }
    }

    /// The most severe health across tasks; `[]` is `.ok`. Drives the menu bar icon.
    public static func aggregate(_ healths: [TaskHealth]) -> TaskHealth {
        healths.max(by: { $0.severity < $1.severity }) ?? .ok
    }
}

/// Maps a task plus its run history to a display health, reusing the
/// sleep-aware `HeartbeatEvaluator` for the deadline math.
public struct TaskHealthEvaluator {
    public init() {}

    /// `recentRuns` must be newest-first (as `RunStore.recent` returns).
    public func health(
        task: MonitoredTask,
        recentRuns: [RunRecord],
        now: Date,
        asleepSeconds: TimeInterval
    ) -> TaskHealth {
        guard let latest = recentRuns.first else { return .neverRan }
        if latest.exitCode != 0 { return .failed }
        let status = HeartbeatEvaluator().status(
            now: now,
            lastSuccess: latest.finishedAt,
            monitoringStarted: latest.finishedAt,
            expectedInterval: task.expectedInterval,
            grace: task.grace,
            asleepSecondsSinceReference: asleepSeconds
        )
        return status == .overdue ? .overdue : .ok
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TaskHealthTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `swift test`
Expected: PASS — all prior 39 tests plus the new ones.

- [ ] **Step 6: Commit**

```bash
git add Sources/AutoTriggerCore/TaskHealth.swift Tests/AutoTriggerCoreTests/TaskHealthTests.swift
git commit -m "feat: add TaskHealth + TaskHealthEvaluator"
```

---

## Phase 2 — App (Xcode target via xcodegen)

> Phase 2 is GUI/integration work: verification is `xcodebuild` success plus manual QA on a real machine, consistent with how the daemon, `SleepTracker`, and `WrapperInstaller`'s `launchctl` layer are treated. There is no red-green unit loop here — the unit-testable logic already lives in Phase 1.

### Task 5: Xcode app scaffold (xcodegen + minimal MenuBarExtra)

**Files:**
- Create: `App/project.yml`
- Create: `App/AutoTrigger/AutoTriggerApp.swift`

- [ ] **Step 1: Ensure xcodegen is installed**

Run: `which xcodegen || brew install xcodegen`
Expected: a path to `xcodegen`, or a successful Homebrew install.

- [ ] **Step 2: Write the xcodegen spec**

```yaml
# App/project.yml
name: AutoTrigger
options:
  bundleIdPrefix: com.autotrigger
  deploymentTarget:
    macOS: "13.0"
packages:
  AutoTriggerCore:
    path: ..
targets:
  AutoTrigger:
    type: application
    platform: macOS
    sources:
      - path: AutoTrigger
    dependencies:
      - package: AutoTriggerCore
        product: AutoTriggerCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.autotrigger.app
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSUIElement: YES
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
schemes:
  AutoTrigger:
    build:
      targets:
        AutoTrigger: all
    run:
      config: Debug
```

- [ ] **Step 3: Write a minimal app entry point**

```swift
// App/AutoTrigger/AutoTriggerApp.swift
import SwiftUI

@main
struct AutoTriggerApp: App {
    var body: some Scene {
        MenuBarExtra("AutoTrigger", systemImage: "bolt.horizontal.circle") {
            Text("AutoTrigger")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Generate the project and build**

Run:
```bash
cd App && xcodegen generate && \
xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
  -configuration Debug -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`. This proves the local-package link, `MenuBarExtra`, and `LSUIElement` bundling work before any real UI is added.

- [ ] **Step 5: Add a .gitignore entry for generated artifacts**

Append to `App/.gitignore` (create it):
```
AutoTrigger.xcodeproj/
build/
```
`project.yml` is the committed source of truth; the `.xcodeproj` is regenerated.

- [ ] **Step 6: Commit**

```bash
git add App/project.yml App/AutoTrigger/AutoTriggerApp.swift App/.gitignore
git commit -m "feat: scaffold AutoTrigger menu bar app target (xcodegen)"
```

---

### Task 6: Health display mapping + MenuBarViewModel

**Files:**
- Create: `App/AutoTrigger/HealthDisplay.swift`
- Create: `App/AutoTrigger/MenuBarViewModel.swift`

- [ ] **Step 1: Write the health → UI mapping**

```swift
// App/AutoTrigger/HealthDisplay.swift
import SwiftUI
import AutoTriggerCore

extension TaskHealth {
    var symbolName: String {
        switch self {
        case .ok:       return "checkmark.circle.fill"
        case .neverRan: return "clock"
        case .overdue:  return "exclamationmark.triangle.fill"
        case .failed:   return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok:       return .green
        case .neverRan: return .gray
        case .overdue:  return .yellow
        case .failed:   return .red
        }
    }

    var label: String {
        switch self {
        case .ok:       return "OK"
        case .neverRan: return "Never ran"
        case .overdue:  return "Overdue"
        case .failed:   return "Failed"
        }
    }
}
```

- [ ] **Step 2: Write the view model**

```swift
// App/AutoTrigger/MenuBarViewModel.swift
import SwiftUI
import AutoTriggerCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    struct Row: Identifiable {
        let task: MonitoredTask
        let health: TaskHealth
        let lastRun: Date?
        var id: String { task.id }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var aggregate: TaskHealth = .ok

    private let taskStore: MonitoredTaskStore
    private let runStore: RunStore?
    private let secretStore: SecretStore
    private let evaluator = TaskHealthEvaluator()
    private let sleepTracker = SleepTracker()
    private var timer: Timer?

    init(
        taskStore: MonitoredTaskStore = MonitoredTaskStore(),
        runStore: RunStore? = try? RunStore(
            path: AutoTriggerPaths.runStorePath, retentionPerTask: 200, maxOutputChars: 10_000
        ),
        secretStore: SecretStore = KeychainSecretStore()
    ) {
        self.taskStore = taskStore
        self.runStore = runStore
        self.secretStore = secretStore
        sleepTracker.startObserving()
        refresh()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let tasks = (try? taskStore.load()) ?? []
        let now = Date()
        let asleep = sleepTracker.asleepSeconds(asOf: now)
        rows = tasks.map { task in
            let runs = recentRuns(for: task.id)
            let health = evaluator.health(task: task, recentRuns: runs, now: now, asleepSeconds: asleep)
            return Row(task: task, health: health, lastRun: runs.first?.finishedAt)
        }
        aggregate = TaskHealth.aggregate(rows.map(\.health))
    }

    func recentRuns(for taskID: String, limit: Int = 50) -> [RunRecord] {
        guard let runStore, let runs = try? runStore.recent(taskLabel: taskID, limit: limit) else { return [] }
        return runs
    }

    // MARK: Task config mutations
    func addTask(_ task: MonitoredTask) { try? taskStore.add(task); refresh() }
    func removeTask(id: String) { try? taskStore.remove(id: id); refresh() }

    // MARK: Webhook secret
    func webhookURL() -> String { (try? secretStore.get(SecretKeys.webhookURL)) ?? nil ?? "" }
    func setWebhookURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? secretStore.delete(SecretKeys.webhookURL)
        } else {
            try? secretStore.set(trimmed, for: SecretKeys.webhookURL)
        }
    }

    // MARK: Debug seeding (manual QA only; compiled out of Release)
    #if DEBUG
    func seedDemoRuns() {
        guard let runStore else { return }
        let now = Date()
        for task in (try? taskStore.load()) ?? [] {
            let rec = RunRecord(
                taskLabel: task.id,
                startedAt: now.addingTimeInterval(-5),
                finishedAt: now,
                exitCode: 0,
                stdout: "demo ok\n",
                stderr: ""
            )
            try? runStore.insert(rec)
        }
        refresh()
    }
    #endif
}
```

- [ ] **Step 3: Regenerate and build**

Run:
```bash
cd App && xcodegen generate && \
xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
  -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/AutoTrigger/HealthDisplay.swift App/AutoTrigger/MenuBarViewModel.swift
git commit -m "feat: add MenuBarViewModel + health display mapping"
```

---

### Task 7: DashboardView + live menu bar icon

**Files:**
- Create: `App/AutoTrigger/DashboardView.swift`
- Modify: `App/AutoTrigger/AutoTriggerApp.swift`

- [ ] **Step 1: Write the dashboard**

```swift
// App/AutoTrigger/DashboardView.swift
import SwiftUI
import AutoTriggerCore

struct DashboardView: View {
    @ObservedObject var model: MenuBarViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationStack {
            Group {
                if model.rows.isEmpty {
                    Text("No monitored tasks.\nAdd one in Settings.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.rows) { row in
                        NavigationLink {
                            TaskDetailView(model: model, taskID: row.id)
                        } label: {
                            HStack {
                                Image(systemName: row.health.symbolName)
                                    .foregroundStyle(row.health.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.task.displayName)
                                    Text(lastRunText(row.lastRun))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 260)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Refresh") { model.refresh() }
                }
            }
        }
        Divider()
        HStack {
            #if DEBUG
            Button("Seed demo") { model.seedDemoRuns() }
            #endif
            Button("Settings…") { openSettings() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
    }

    private func lastRunText(_ date: Date?) -> String {
        guard let date else { return "never run" }
        let f = RelativeDateTimeFormatter()
        return "last run " + f.localizedString(for: date, relativeTo: Date())
    }
}
```

> Note: `openSettings` is macOS 14+. The fallback for 13 is wired in the app entry point (Step 2) — `DashboardView` uses `openSettings` which is available because the deployment target's settings scene exists; if building against the 13 SDK only, replace the `openSettings()` call with `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`. Use the selector form to stay 13-compatible.

Revised settings button (13-safe) — use this version instead of `openSettings`:

```swift
Button("Settings…") {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
```

And remove the `@Environment(\.openSettings)` line.

- [ ] **Step 2: Wire the dashboard + dynamic icon into the app**

```swift
// App/AutoTrigger/AutoTriggerApp.swift
import SwiftUI
import AutoTriggerCore

@main
struct AutoTriggerApp: App {
    @StateObject private var model = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
        } label: {
            Image(systemName: model.aggregate.symbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
```

> `SettingsView` is created in Task 9. To keep this task building on its own, add a temporary stub at the bottom of `AutoTriggerApp.swift` and delete it in Task 9:
> ```swift
> // TEMP stub — replaced by SettingsView.swift in Task 9
> struct SettingsView: View { @ObservedObject var model: MenuBarViewModel; var body: some View { Text("Settings") } }
> ```

- [ ] **Step 3: Regenerate and build**

Run:
```bash
cd App && xcodegen generate && \
xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
  -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/AutoTrigger/DashboardView.swift App/AutoTrigger/AutoTriggerApp.swift
git commit -m "feat: add DashboardView + dynamic menu bar health icon"
```

---

### Task 8: TaskDetailView

**Files:**
- Create: `App/AutoTrigger/TaskDetailView.swift`

- [ ] **Step 1: Write the detail view**

```swift
// App/AutoTrigger/TaskDetailView.swift
import SwiftUI
import AutoTriggerCore

struct TaskDetailView: View {
    @ObservedObject var model: MenuBarViewModel
    let taskID: String

    var body: some View {
        let runs = model.recentRuns(for: taskID)
        List {
            if runs.isEmpty {
                Text("No runs recorded yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: run.exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(run.exitCode == 0 ? .green : .red)
                        Text(run.finishedAt.formatted(date: .abbreviated, time: .standard))
                        Spacer()
                        Text("exit \(run.exitCode)").font(.caption)
                        Text(durationText(run)).font(.caption).foregroundStyle(.secondary)
                    }
                    let tail = run.stderr.isEmpty ? run.stdout : run.stderr
                    if !tail.isEmpty {
                        Text(tail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Runs")
    }

    private func durationText(_ run: RunRecord) -> String {
        String(format: "%.1fs", run.finishedAt.timeIntervalSince(run.startedAt))
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
cd App && xcodegen generate && \
xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
  -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/AutoTrigger/TaskDetailView.swift
git commit -m "feat: add TaskDetailView showing recent runs"
```

---

### Task 9: SettingsView (task CRUD + webhook URL)

**Files:**
- Create: `App/AutoTrigger/SettingsView.swift`
- Modify: `App/AutoTrigger/AutoTriggerApp.swift` (remove the temporary `SettingsView` stub from Task 7)

- [ ] **Step 1: Delete the temporary stub**

Remove this block from `App/AutoTrigger/AutoTriggerApp.swift`:
```swift
// TEMP stub — replaced by SettingsView.swift in Task 9
struct SettingsView: View { @ObservedObject var model: MenuBarViewModel; var body: some View { Text("Settings") } }
```

- [ ] **Step 2: Write the settings view**

```swift
// App/AutoTrigger/SettingsView.swift
import SwiftUI
import AutoTriggerCore

struct SettingsView: View {
    @ObservedObject var model: MenuBarViewModel

    var body: some View {
        TabView {
            TasksSettings(model: model)
                .tabItem { Label("Tasks", systemImage: "list.bullet") }
            WebhookSettings(model: model)
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 480, height: 380)
        .padding()
    }
}

private struct TasksSettings: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var id = ""
    @State private var name = ""
    @State private var intervalMinutes = "60"
    @State private var graceMinutes = "10"

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(model.rows) { row in
                    HStack {
                        Text(row.task.displayName)
                        Spacer()
                        Text(row.task.id).font(.caption).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.removeTask(id: row.task.id) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            Divider()
            Text("Add task").font(.headline)
            TextField("Task label (RunStore id)", text: $id)
            TextField("Display name", text: $name)
            HStack {
                TextField("Interval (min)", text: $intervalMinutes).frame(width: 120)
                TextField("Grace (min)", text: $graceMinutes).frame(width: 120)
            }
            Button("Add") {
                guard !id.isEmpty,
                      let interval = Double(intervalMinutes),
                      let grace = Double(graceMinutes) else { return }
                model.addTask(MonitoredTask(
                    id: id,
                    displayName: name.isEmpty ? id : name,
                    expectedInterval: interval * 60,
                    grace: grace * 60,
                    source: .manual
                ))
                id = ""; name = ""
            }
        }
    }
}

private struct WebhookSettings: View {
    @ObservedObject var model: MenuBarViewModel
    @State private var url = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alert webhook URL").font(.headline)
            Text("Point this at Slack / ntfy / Pushover. Stored in the Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://…", text: $url)
            HStack {
                Button("Save") {
                    model.setWebhookURL(url)
                    saved = true
                }
                if saved { Text("Saved").foregroundStyle(.green).font(.caption) }
            }
            Spacer()
        }
        .onAppear { url = model.webhookURL() }
    }
}
```

- [ ] **Step 3: Regenerate and build**

Run:
```bash
cd App && xcodegen generate && \
xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
  -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App/AutoTrigger/SettingsView.swift App/AutoTrigger/AutoTriggerApp.swift
git commit -m "feat: add SettingsView for task CRUD + webhook URL"
```

---

### Task 10: Manual QA + wire CI release build

**Files:**
- Modify: `.github/workflows/release.yml` (the `Build .app` step)

- [ ] **Step 1: Launch and QA the app**

Run:
```bash
cd App && xcodegen generate && \
xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
  -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build && \
open build/Build/Products/Debug/AutoTrigger.app
```

Manual checklist (real machine):
- Menu bar shows the AutoTrigger icon, no Dock icon (LSUIElement).
- Click icon → empty-state text ("No monitored tasks").
- Settings… → Tasks tab → add a task (label `demo`, interval 60, grace 10) → it appears in the list.
- Back in the dashboard, the task row shows "Never ran" (gray clock); menu bar icon reflects `neverRan`.
- Click "Seed demo" → row flips to OK (green); menu bar icon turns to the OK symbol; "last run … seconds ago".
- Open the row → TaskDetailView lists the seeded run (exit 0, duration, `demo ok` tail).
- Settings → Alerts → enter a URL, Save → reopen Settings, the field is repopulated (Keychain round-trip).
- Remove the task in Settings → dashboard returns to empty state.

- [ ] **Step 2: Replace the CI Build .app step**

In `.github/workflows/release.yml`, replace the placeholder `Build .app` step body with:

```yaml
      - name: Install xcodegen
        run: brew install xcodegen

      - name: Build .app
        run: |
          cd App
          xcodegen generate
          xcodebuild -project AutoTrigger.xcodeproj -scheme AutoTrigger \
            -configuration Release -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO build
          echo "APP_PATH=$(pwd)/build/Build/Products/Release/AutoTrigger.app" >> "$GITHUB_ENV"
```

> The downstream Codesign step signs `build/AutoTrigger.app`. Update its path to `${{ env.APP_PATH }}` (and the DMG `srcfolder` likewise) so it points at the xcodebuild output. Keep the signing/notarization/staple/DMG logic otherwise unchanged.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: wire release Build .app step to xcodegen + xcodebuild"
```

---

## Self-Review

**1. Spec coverage**

| Spec item | Task |
|-----------|------|
| `SecretKeys.webhookURL` shared constant | Task 1 |
| `MonitoredTask` model | Task 2 |
| `AutoTriggerPaths` + `MonitoredTaskStore` (JSON, missing→[], corrupt→throws, atomic, mkdir) | Task 3 |
| `TaskHealth` + aggregate + `TaskHealthEvaluator` (ok/overdue/failed/neverRan, sleep-aware) | Task 4 |
| Xcode app target, `MenuBarExtra`, `LSUIElement`, links package | Task 5 |
| `MenuBarViewModel` (30s poll, stores, secret) + health→UI mapping | Task 6 |
| `DashboardView` + dynamic aggregate icon | Task 7 |
| `TaskDetailView` (recent runs + stdout/stderr tail) | Task 8 |
| `SettingsView` (task CRUD + webhook via Keychain under `SecretKeys.webhookURL`) | Task 9 |
| Seeded-data validation + CI Build .app wiring | Task 10 |
| Error handling (missing/corrupt config, RunStore open fail) | Tasks 3 (store) + 6 (ViewModel `try?` degradation) |

No spec requirement is left without a task.

**2. Placeholder scan:** No "TBD"/"implement later". The only stub is the explicitly temporary `SettingsView` in Task 7, created and removed within the plan (Task 9 Step 1).

**3. Type consistency:** `MonitoredTask(id:displayName:expectedInterval:grace:source:)`, `MonitoredTaskStore(fileURL:)` with `load/save/add/remove`, `TaskHealthEvaluator.health(task:recentRuns:now:asleepSeconds:)`, `TaskHealth.aggregate(_:)`, `MenuBarViewModel` methods (`refresh`, `recentRuns(for:limit:)`, `addTask`, `removeTask`, `webhookURL`, `setWebhookURL`, `seedDemoRuns`), and `RunStore.recent(taskLabel:limit:)` / `RunStore.insert(_:)` / `RunRecord(taskLabel:startedAt:finishedAt:exitCode:stdout:stderr:)` are used consistently across tasks and match the existing core APIs.

## Known follow-ups (out of scope for this plan)

- The wrapper executable that records real `RunRecord`s into `RunStore` (without it the dashboard only shows seeded data).
- Live launchd/cron interception from the UI via `WrapperInstaller`.
- Daemon main-loop wiring in `Sources/autotrigger-heartbeatd/main.swift`.
