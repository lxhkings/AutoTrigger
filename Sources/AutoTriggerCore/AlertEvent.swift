import Foundation

public struct AlertEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case overdue, failed }
    public let taskLabel: String
    public let kind: Kind
    public let message: String
    public let timestamp: Date

    public init(taskLabel: String, kind: Kind, message: String, timestamp: Date) {
        self.taskLabel = taskLabel
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
    }
}
