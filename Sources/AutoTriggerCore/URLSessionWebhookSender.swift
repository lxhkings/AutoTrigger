import Foundation

public enum WebhookSendError: Error { case badStatus(Int) }

/// Production WebhookSender: POSTs the JSON body, treats non-2xx as failure
/// (so AlertDispatcher retries it).
public struct URLSessionWebhookSender: WebhookSender {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ body: Data, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw WebhookSendError.badStatus(http.statusCode)
        }
    }
}
