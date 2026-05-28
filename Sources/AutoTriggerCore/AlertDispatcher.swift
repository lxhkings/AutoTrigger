import Foundation

/// Abstracts the HTTP POST so retry logic is testable without the network.
public protocol WebhookSender: Sendable {
    func send(_ body: Data, to url: URL) async throws
}

public enum AlertDispatcherError: Error { case allAttemptsFailed }

/// Posts an alert to a webhook, retrying transient failures up to maxAttempts.
public struct AlertDispatcher: Sendable {
    private let sender: any WebhookSender
    private let maxAttempts: Int
    private let retryDelay: TimeInterval

    public init(sender: any WebhookSender, maxAttempts: Int = 3, retryDelay: TimeInterval = 2) {
        self.sender = sender
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelay = retryDelay
    }

    public func dispatch(_ event: AlertEvent, to url: URL) async throws {
        let body = WebhookPayload.json(from: event)
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try await sender.send(body, to: url)
                return
            } catch {
                lastError = error
                if attempt < maxAttempts, retryDelay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? AlertDispatcherError.allAttemptsFailed
    }
}
