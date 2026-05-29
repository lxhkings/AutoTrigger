# AutoTrigger Menu Bar App — Design

**Date:** 2026-05-29
**Status:** Design (awaiting review)

## Goal

A status-first macOS menu bar app for AutoTrigger. The menu bar icon shows aggregate task health at a glance; clicking opens a panel that lists monitored tasks with their health, drills into recent runs, and exposes secondary configuration (monitored-task definitions + alert webhook URL).

This is the `menubar app target` repeatedly referenced as a dependency in the T6 CI/release plan (`xcodebuild -scheme AutoTrigger` → `AutoTrigger.app`).

## Confirmed scope decisions

| Decision | Choice |
|----------|--------|
| Core scene | Status-first (health dashboard is the first screen); config is secondary |
| Architecture | Approach 1: Xcode project + SwiftUI `MenuBarExtra`, consuming local SwiftPM package `AutoTriggerCore` |
| Data-flow scope | B1: build the UI + new `MonitoredTaskStore`; validate the dashboard against `RunStore` data seeded via the existing `RunStore.insert` API. The wrapper executable and live launchd/cron wrapping are a **separate later slice**, NOT in this work |

## Out of scope (explicit)

- The wrapper executable (runs the original command, then records a `RunRecord` into `RunStore`). No such target exists yet; building it is a separate slice.
- Live task interception (`WrapperInstaller` + `launchctl bootout/bootstrap`) driven from the UI.
- The daemon main-loop wiring (still a stub in `Sources/autotrigger-heartbeatd/main.swift`).
- Cross-machine fleet view (TODOS P2) and the broader Delight pack (TODOS P3).

These are acknowledged pipeline gaps. The dashboard will show real data only once the wrapper records runs; until then it is validated with seeded `RunStore` rows.

## Architecture

An Xcode project `AutoTrigger.xcodeproj` defines a SwiftUI app target `AutoTrigger` (scheme `AutoTrigger`) that links the existing local SwiftPM package `AutoTriggerCore`. The app uses the `MenuBarExtra` scene (macOS 13+) and runs as an agent (`LSUIElement = true`, no Dock icon).

Shared, unit-testable logic is added to `AutoTriggerCore` so both the app and the (future) daemon consume one config source and one health-computation path. The SwiftUI layer stays thin: it observes a view model that calls into the core.

### New components in `AutoTriggerCore`

#### `MonitoredTask`

A `Codable`, `Equatable`, `Sendable` value describing one task under monitoring.

```
public struct MonitoredTask: Codable, Equatable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case launchd, cron, manual }
    public let id: String          // stable id; == task label used as RunStore key
    public var displayName: String
    public var expectedInterval: TimeInterval
    public var grace: TimeInterval
    public var source: Source
}
```

`id` equals the `task_label` written into `RunStore`, so a task's runs are looked up by `RunStore.recent(taskLabel: task.id, ...)`.

#### `MonitoredTaskStore`

JSON-backed config persistence at `~/Library/Application Support/AutoTrigger/monitored-tasks.json`.

- `load() -> [MonitoredTask]` — missing file returns `[]` (first run); corrupt JSON throws a typed error (caller surfaces, does not crash).
- `save(_ tasks: [MonitoredTask]) throws` — encodes and writes via `AtomicWriter.write`.
- Convenience `add`/`remove`/`update` that mutate-and-save.
- Creates the parent directory with `withIntermediateDirectories: true` before first write (the same gap that crashed the daemon — see startup-bug note below).

#### `TaskHealth` + `TaskHealthEvaluator`

Pure combiner mapping a task plus its run history to a display status.

```
public enum TaskHealth: Equatable, Sendable {
    case ok            // ran successfully within interval + grace
    case overdue       // HeartbeatEvaluator says overdue
    case failed        // most recent run exists but exitCode != 0
    case neverRan      // no runs recorded yet
}
```

`TaskHealthEvaluator.health(task:recentRuns:now:asleepSeconds:)` (`recentRuns` newest-first, as `RunStore.recent` returns):

1. No runs → `.neverRan`.
2. Most recent run `exitCode != 0` → `.failed`.
3. Otherwise feed the most recent run's `finishedAt` as `lastSuccess` into `HeartbeatEvaluator.status(...)`; `.overdue` → `.overdue`, else `.ok`.

Reuses the existing `HeartbeatEvaluator` for the deadline math (sleep-aware). This keeps the dead-man's-switch logic single-sourced.

#### `SecretKeys`

A small constants enum: `SecretKeys.webhookURL = "webhook-url"`. Both the app (writes the URL via `SecretStore`) and the daemon's alert layer (reads it) reference this one constant, so they never drift on the key string.

### App layer (Xcode target `AutoTrigger`)

| Unit | Responsibility |
|------|----------------|
| `AutoTriggerApp` | `@main`, declares the `MenuBarExtra` scene + a `Settings`/`Window` scene for the settings sheet |
| `MenuBarViewModel` | `@MainActor ObservableObject`. Holds `[TaskHealthRow]` and an `aggregateHealth`. Polls every 30s (and on menu open) by reading `MonitoredTaskStore` + `RunStore` and running `TaskHealthEvaluator`. Owns a `SleepTracker` for the asleep-seconds input |
| `DashboardView` | The `MenuBarExtra` content: a `List` of task rows — display name, status badge (color + SF Symbol), and a relative "last run 3m ago" line |
| `TaskDetailView` | Recent runs for one task (timestamp, exit code, duration) plus a tail of stdout/stderr from the latest `RunRecord` |
| `SettingsView` | Webhook URL field (read/write via `SecretStore` under the shared `SecretKeys.webhookURL` key); monitored-task add/remove/edit (display name, expected interval, grace) persisted through `MonitoredTaskStore` |

The menu bar label is an SF Symbol tinted by `aggregateHealth`: green when all `ok`, yellow when any `overdue`/`neverRan`, red when any `failed`.

### Data flow

```
RunStore (SQLite; later written by the wrapper) ─┐
                                                  ├─► MenuBarViewModel (polls 30s)
MonitoredTaskStore (JSON config) ─────────────────┘        │
                                                            ▼
                                                  TaskHealthEvaluator (+ HeartbeatEvaluator)
                                                            │
                                                            ▼
                                                  DashboardView / TaskDetailView

SettingsView writes:  webhook URL → SecretStore (Keychain)
                      monitored tasks → MonitoredTaskStore (JSON)
```

`AlertDispatcher.dispatch(_:to:)` takes the URL as a parameter — there is no key constant today. This design introduces a shared `SecretKeys.webhookURL` constant in `AutoTriggerCore`; the UI writes the secret under it and the daemon's alert layer reads it under the same key, single-sourcing the agreement.

## Error handling

| Condition | Behavior |
|-----------|----------|
| `monitored-tasks.json` missing | Treat as empty list (first launch) |
| `monitored-tasks.json` corrupt | `MonitoredTaskStore.load` throws typed error; `SettingsView` shows it, dashboard shows empty — no crash |
| `RunStore` open/read fails | Affected task row renders an `unknown`/error state; the menu bar keeps working |
| Keychain read/write fails | `SettingsView` surfaces the error inline; not fatal |

## Testing strategy

| Layer | Method |
|-------|--------|
| `MonitoredTaskStore` | `swift test`: save/load round-trip, add/remove/update, missing-file → `[]`, corrupt-file → throws, atomic write into a temp dir |
| `TaskHealthEvaluator` | `swift test`: pure logic, injected `now`/`asleepSeconds`, covering all four states (ok / overdue / failed / neverRan) |
| `MenuBarViewModel` mapping | Where extractable as pure mapping (rows + aggregate from inputs), unit test it; the 30s `Timer` wiring is integration |
| SwiftUI views, menu bar presence | Manual QA on a real machine: launch app, confirm menu bar icon + color, open panel, verify rows against seeded `RunStore` data, open settings, edit a task, confirm JSON written |

Core additions follow the repo's existing TDD pattern (Swift Testing, temp-dir databases). SwiftUI/AppKit presentation is integration/manual, consistent with how the daemon, `SleepTracker`, and `WrapperInstaller`'s `launchctl` layer were handled.

## Distribution / CI

- `Info.plist`: `LSUIElement = true` (agent app).
- Xcode scheme `AutoTrigger`, Release configuration.
- The T6 `release.yml` `Build .app` step (currently a placeholder that exits 1) is replaced with the templated `xcodebuild -scheme AutoTrigger -configuration Release` command already documented in that plan. Signing/notarization/DMG steps downstream are unchanged.

## Note: a startup bug fixed during verification

While verifying the engine, the daemon crashed on first run: `RunStore` opens SQLite with `SQLITE_OPEN_CREATE` (creates the file, not the parent dir), and `~/Library/Application Support/AutoTrigger/` did not exist. Fixed by creating the directory in `main.swift` before opening the store. `MonitoredTaskStore` must apply the same directory-creation guard, since the UI may run before the daemon ever has.
