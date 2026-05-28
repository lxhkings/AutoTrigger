import Testing
import Foundation
@testable import AutoTriggerCore

/// Fake sender: fails its first `failTimes` calls, then succeeds. Records count.
actor FakeSender: WebhookSender {
    private(set) var calls = 0
    private let failTimes: Int
    struct SendFailure: Error {}
    init(failTimes: Int) { self.failTimes = failTimes }
    func send(_ body: Data, to url: URL) async throws {
        calls += 1
        if calls <= failTimes { throw SendFailure() }
    }
    func callCount() -> Int { calls }
}

private let url = URL(string: "https://example.com/hook")!
private let event = AlertEvent(taskLabel: "t", kind: .failed, message: "m",
                               timestamp: Date(timeIntervalSince1970: 0))

@Test func dispatchSucceedsAfterRetries() async throws {
    let sender = FakeSender(failTimes: 2)
    let dispatcher = AlertDispatcher(sender: sender, maxAttempts: 3, retryDelay: 0)
    try await dispatcher.dispatch(event, to: url)
    #expect(await sender.callCount() == 3) // 2 fails + 1 success
}

@Test func dispatchThrowsAfterExhaustingAttempts() async {
    let sender = FakeSender(failTimes: 99)
    let dispatcher = AlertDispatcher(sender: sender, maxAttempts: 3, retryDelay: 0)
    await #expect(throws: (any Error).self) {
        try await dispatcher.dispatch(event, to: url)
    }
    #expect(await sender.callCount() == 3) // tried exactly maxAttempts
}
