import Foundation
import AutoTriggerCore

// Resident heartbeat checker. Polls every 60s: for each monitored task, read its
// last successful run from RunStore, evaluate with sleep-aware grace, and emit
// an alert event for overdue tasks. Alert delivery is handled by the alert layer.

let storePath = NSString(string: "~/Library/Application Support/AutoTrigger/runs.sqlite").expandingTildeInPath
let store: RunStore
do {
    try FileManager.default.createDirectory(
        atPath: (storePath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true
    )
    store = try RunStore(path: storePath, retentionPerTask: 200, maxOutputChars: 10_000)
} catch {
    fputs("autotrigger-heartbeatd: failed to open RunStore: \(error)\n", stderr)
    exit(1)
}
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
