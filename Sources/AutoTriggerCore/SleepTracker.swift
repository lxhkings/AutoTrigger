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
