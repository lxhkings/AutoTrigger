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
