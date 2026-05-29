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
