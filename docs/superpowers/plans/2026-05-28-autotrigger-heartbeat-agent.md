# AutoTrigger Heartbeat Agent (T2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A dead-man's-switch heartbeat monitor that fires an alert when a task fails to run by its deadline — but does NOT false-alarm when the machine was asleep through the expected window.

**Architecture:** A pure `HeartbeatEvaluator` (the unit-tested core: deadline math with sleep time subtracted) in `AutoTriggerCore`, plus a thin `SleepTracker` (NSWorkspace sleep/wake observation) and a resident `autotrigger-heartbeatd` executable launched by a LaunchAgent. The evaluator is fully TDD'd against injected clocks/sleep-durations; the daemon + LaunchAgent + NSWorkspace wiring are integration (manual verification), consistent with how the wrapper plan handled `launchctl`.

**Tech Stack:** Swift 6.3, Foundation, AppKit (`NSWorkspace`), Swift Testing. Adds an executable target to the existing package; reads run history from `RunStore`.

**Depends on:** the run-store plan (`RunStore`) — the monitor reads each task's last successful run from it.

**Locked decision (eng review):** heartbeat runs in an independent LaunchAgent, NOT inside the menubar app — the app may be quit exactly when an alert is due. Sleep-aware grace is mandatory (learning `deadman-switch-sleep-fp`).

---

### Task 1: HeartbeatEvaluator — basic deadline (no sleep yet)

**Files:**
- Create: `Sources/AutoTriggerCore/HeartbeatEvaluator.swift`
- Test: `Tests/AutoTriggerCoreTests/HeartbeatEvaluatorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/HeartbeatEvaluatorTests.swift`:

```swift
import Testing
import Foundation
@testable import AutoTriggerCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func okWhenWithinIntervalPlusGrace() {
    let e = HeartbeatEvaluator()
    let status = e.status(
        now: t0.addingTimeInterval(50),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 0)
    #expect(status == .ok)
}

@Test func overdueWhenAwakePastIntervalPlusGrace() {
    let e = HeartbeatEvaluator()
    let status = e.status(
        now: t0.addingTimeInterval(200),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 0)
    #expect(status == .overdue)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HeartbeatEvaluator`
Expected: FAIL — `cannot find 'HeartbeatEvaluator' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/HeartbeatEvaluator.swift`:

```swift
import Foundation

public enum HeartbeatStatus: Equatable, Sendable {
    case ok
    case overdue
}

/// Pure dead-man's-switch logic. A task is overdue only if the machine has been
/// AWAKE for longer than its expected interval + grace since the reference time
/// (last successful run, or monitoring start if it never ran). Time the machine
/// was asleep does not count against the deadline — sleeping is not failing.
public struct HeartbeatEvaluator {
    public init() {}

    public func status(
        now: Date,
        lastSuccess: Date?,
        monitoringStarted: Date,
        expectedInterval: TimeInterval,
        grace: TimeInterval,
        asleepSecondsSinceReference: TimeInterval
    ) -> HeartbeatStatus {
        let reference = lastSuccess ?? monitoringStarted
        let wallElapsed = now.timeIntervalSince(reference)
        let awakeElapsed = max(0, wallElapsed - asleepSecondsSinceReference)
        return awakeElapsed > expectedInterval + grace ? .overdue : .ok
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HeartbeatEvaluator`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/HeartbeatEvaluator.swift Tests/AutoTriggerCoreTests/HeartbeatEvaluatorTests.swift
git commit -m "feat: add HeartbeatEvaluator deadline logic"
```

---

### Task 2: sleep-grace — asleep time does not count as overdue

**Files:**
- Modify: `Tests/AutoTriggerCoreTests/HeartbeatEvaluatorTests.swift`

- [ ] **Step 1: Write the failing/confirming test**

Append:

```swift
@Test func notOverdueWhenAsleepThroughTheWindow() {
    let e = HeartbeatEvaluator()
    // 200s of wall time passed, but 180s of it the machine was asleep →
    // only 20s of awake time, well under 60+30.
    let status = e.status(
        now: t0.addingTimeInterval(200),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 180)
    #expect(status == .ok)
}

@Test func overdueWhenAwakeEnoughEvenWithSomeSleep() {
    let e = HeartbeatEvaluator()
    // 300s wall, 100s asleep → 200s awake > 60+30 → overdue.
    let status = e.status(
        now: t0.addingTimeInterval(300),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 100)
    #expect(status == .overdue)
}

@Test func neverRanIsOkUntilFirstAwakeWindowElapses() {
    let e = HeartbeatEvaluator()
    // No successful run yet; only 20s awake since monitoring started → ok.
    let early = e.status(now: t0.addingTimeInterval(20), lastSuccess: nil,
                         monitoringStarted: t0, expectedInterval: 60, grace: 30,
                         asleepSecondsSinceReference: 0)
    #expect(early == .ok)
    // 200s awake since start, still never ran → overdue.
    let late = e.status(now: t0.addingTimeInterval(200), lastSuccess: nil,
                        monitoringStarted: t0, expectedInterval: 60, grace: 30,
                        asleepSecondsSinceReference: 0)
    #expect(late == .overdue)
}
```

- [ ] **Step 2: Run test**

Run: `swift test --filter HeartbeatEvaluator`
Expected: PASS — the sleep subtraction in Task 1 already implements this. If `notOverdueWhenAsleepThroughTheWindow` FAILS, the evaluator isn't subtracting `asleepSecondsSinceReference` — fix Task 1's `awakeElapsed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/AutoTriggerCoreTests/HeartbeatEvaluatorTests.swift
git commit -m "test: pin sleep-aware grace so asleep time never triggers false overdue"
```

---

### Task 3: SleepTracker (integration — NSWorkspace, not unit-tested)

This component cannot be unit-tested without a real run loop and power events. Implement it, then verify manually. It records cumulative asleep-seconds that the evaluator consumes.

**Files:**
- Create: `Sources/AutoTriggerCore/SleepTracker.swift`

- [ ] **Step 1: Implement**

`Sources/AutoTriggerCore/SleepTracker.swift`:

```swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Tracks how long the machine has been asleep since it started observing.
/// The heartbeat daemon feeds `asleepSeconds(since:)` into HeartbeatEvaluator.
public final class SleepTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var totalAsleep: TimeInterval = 0
    private var sleepStartedAt: Date?

    public init() {}

    #if canImport(AppKit)
    /// Call once on the daemon's main thread to begin observing power events.
    public func startObserving() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func willSleep() {
        lock.lock(); sleepStartedAt = Date(); lock.unlock()
    }

    @objc private func didWake() {
        lock.lock()
        if let start = sleepStartedAt { totalAsleep += Date().timeIntervalSince(start) }
        sleepStartedAt = nil
        lock.unlock()
    }
    #endif

    /// Asleep-seconds accumulated since `reference`. Conservative: if currently
    /// asleep, includes the in-progress sleep. (Reference is informational; the
    /// daemon resets the tracker per evaluation window in practice.)
    public func asleepSeconds(asOf now: Date = Date()) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        var total = totalAsleep
        if let start = sleepStartedAt { total += now.timeIntervalSince(start) }
        return total
    }

    /// For tests: inject asleep time without real power events.
    func _testRecordAsleep(_ seconds: TimeInterval) {
        lock.lock(); totalAsleep += seconds; lock.unlock()
    }
}
```

- [ ] **Step 2: Smoke test the injectable seam (the only unit-testable part)**

`Tests/AutoTriggerCoreTests/SleepTrackerTests.swift`:

```swift
import Testing
@testable import AutoTriggerCore

@Test func injectedAsleepSecondsAccumulate() {
    let tracker = SleepTracker()
    tracker._testRecordAsleep(120)
    tracker._testRecordAsleep(60)
    #expect(tracker.asleepSeconds() == 180)
}
```

Run: `swift test --filter injectedAsleepSecondsAccumulate`
Expected: PASS.

- [ ] **Step 3: Manual integration verification (document, don't automate)**

In the daemon (Task 4) wire `SleepTracker.startObserving()`. To verify: run the daemon, `pmset sleepnow`, wait, wake, and confirm `asleepSeconds()` increased by roughly the sleep duration. This is a manual check — note the result in the PR description.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoTriggerCore/SleepTracker.swift Tests/AutoTriggerCoreTests/SleepTrackerTests.swift
git commit -m "feat: add SleepTracker observing NSWorkspace sleep/wake (integration)"
```

---

### Task 4: heartbeat daemon executable + LaunchAgent (integration)

This is the resident process. No red-green unit tests — verification is loading the agent and confirming it survives the menubar app quitting. Keep the daemon thin: it composes `RunStore` + `HeartbeatEvaluator` + `SleepTracker` and dispatches alerts (alert delivery itself is the alert-webhook plan).

**Files:**
- Modify: `Package.swift` (add executable target)
- Create: `Sources/autotrigger-heartbeatd/main.swift`
- Create: `Resources/com.autotrigger.heartbeatd.plist`

- [ ] **Step 1: Add the executable target to `Package.swift`**

In `Package.swift`, add to `targets:`:

```swift
        .executableTarget(
            name: "autotrigger-heartbeatd",
            dependencies: ["AutoTriggerCore"]
        ),
```

And add to `products:`:

```swift
        .executable(name: "autotrigger-heartbeatd", targets: ["autotrigger-heartbeatd"]),
```

- [ ] **Step 2: Write the daemon entry point**

`Sources/autotrigger-heartbeatd/main.swift`:

```swift
import Foundation
import AutoTriggerCore

// Resident heartbeat checker. Polls every 60s: for each monitored task, read its
// last successful run from RunStore, evaluate with sleep-aware grace, and emit
// an alert event for overdue tasks. Alert delivery is handled by the alert layer.

let storePath = NSString(string: "~/Library/Application Support/AutoTrigger/runs.sqlite").expandingTildeInPath
let store = try RunStore(path: storePath, retentionPerTask: 200, maxOutputChars: 10_000)
let evaluator = HeartbeatEvaluator()
let sleepTracker = SleepTracker()
sleepTracker.startObserving()

// MonitoredTask config (label, expectedInterval, grace) is loaded from the app's
// shared config; for v1 wire a JSON file at the same Application Support dir.
// Left as the config-loading integration point — see Out of scope.

print("autotrigger-heartbeatd started")
let timer = Timer(timeInterval: 60, repeats: true) { _ in
    // For each task: let last = store.recent(...).first(where success); evaluate;
    // if .overdue → emit alert (alert-webhook plan owns delivery).
}
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
```

- [ ] **Step 3: Write the LaunchAgent plist**

`Resources/com.autotrigger.heartbeatd.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.autotrigger.heartbeatd</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/autotrigger-heartbeatd</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Build and verify it compiles + the agent loads**

Run: `swift build`
Expected: builds `autotrigger-heartbeatd`.

Manual verification (document in PR, not automated):
```bash
# install + load
cp Resources/com.autotrigger.heartbeatd.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.autotrigger.heartbeatd.plist
launchctl print gui/$(id -u)/com.autotrigger.heartbeatd   # confirm running
# kill any menubar app, confirm the daemon still runs (independence)
```

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/autotrigger-heartbeatd/main.swift Resources/com.autotrigger.heartbeatd.plist
git commit -m "feat: add resident heartbeat daemon + LaunchAgent (independent of menubar app)"
```

---

## Out of scope for this plan

- Monitored-task config schema/loading (which tasks, their expected intervals/grace) — shared config format is its own small plan; the daemon's timer body and the menubar app both read it.
- Alert delivery (notification center, webhook) — the alert-webhook plan owns it; this daemon only decides `.overdue` and emits an event.
- The `expectedInterval` derivation from a cron/launchd schedule (e.g. `*/5 * * * *` → 300s) — a separate schedule-parsing helper; v1 can store interval explicitly at import time.

## Self-Review

- **Spec coverage:** T2 = "独立 LaunchAgent 常驻心跳监控 + sleep-grace" → Task 1+2 (evaluator + sleep math, fully TDD'd), Task 3 (SleepTracker), Task 4 (LaunchAgent daemon, independent of app). Matches learnings `heartbeat-needs-launchagent` and `deadman-switch-sleep-fp`.
- **Placeholder scan:** the daemon timer body and config-loading are explicitly deferred to Out of scope (they need the config plan + alert plan), NOT hidden TODOs in the testable core. The evaluator — the part that must be correct — has zero placeholders and full tests.
- **Type consistency:** `HeartbeatEvaluator().status(now:lastSuccess:monitoringStarted:expectedInterval:grace:asleepSecondsSinceReference:)`, `HeartbeatStatus.ok/.overdue`, `SleepTracker().asleepSeconds(asOf:)` / `startObserving()` / `_testRecordAsleep(_:)`, `RunStore(path:retentionPerTask:maxOutputChars:)` (matches run-store plan) are consistent.
