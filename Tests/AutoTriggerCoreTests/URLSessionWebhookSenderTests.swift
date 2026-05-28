import Testing
import Foundation
@testable import AutoTriggerCore

@Suite(.serialized)
struct URLSessionWebhookSenderTests {

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let body = request.httpBody {
            MockURLProtocol.lastBody = body
        } else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 4096)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            MockURLProtocol.lastBody = data
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: MockURLProtocol.statusCode,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@Test func senderPostsBodyAndAccepts2xx() async throws {
    MockURLProtocol.statusCode = 200
    let sender = URLSessionWebhookSender(session: mockSession())
    let body = Data("{\"ok\":true}".utf8)
    try await sender.send(body, to: URL(string: "https://example.com/hook")!)
    #expect(MockURLProtocol.lastBody == body)
}

@Test func senderThrowsOnNon2xx() async {
    MockURLProtocol.statusCode = 500
    let sender = URLSessionWebhookSender(session: mockSession())
    await #expect(throws: (any Error).self) {
        try await sender.send(Data("{}".utf8), to: URL(string: "https://example.com/hook")!)
    }
}

} // URLSessionWebhookSenderTests
