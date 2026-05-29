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
