import Foundation

/// Serializes an AlertEvent into a generic JSON body the user can route to
/// Slack / ntfy / Pushover via their own webhook.
public enum WebhookPayload {
    public static func json(from event: AlertEvent) -> Data {
        let dict: [String: Any] = [
            "task": event.taskLabel,
            "kind": event.kind.rawValue,
            "message": event.message,
            "timestamp": event.timestamp.timeIntervalSince1970
        ]
        // sortedKeys = stable output for tests; JSONSerialization handles escaping.
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
