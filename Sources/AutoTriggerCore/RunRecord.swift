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
