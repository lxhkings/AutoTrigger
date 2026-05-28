import Testing
import Foundation
@testable import AutoTriggerCore

@Test func payloadEncodesEventAsJSON() throws {
    let event = AlertEvent(
        taskLabel: "com.x.backup",
        kind: .overdue,
        message: "No run in 3 days",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000))

    let data = WebhookPayload.json(from: event)
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(obj["task"] as? String == "com.x.backup")
    #expect(obj["kind"] as? String == "overdue")
    #expect(obj["message"] as? String == "No run in 3 days")
    #expect(obj["timestamp"] as? Double == 1_700_000_000)
}

@Test func payloadEscapesSpecialCharactersSafely() throws {
    let event = AlertEvent(taskLabel: "a\"b", kind: .failed,
                           message: "line1\nline2 \u{4e16}\u{754c}",
                           timestamp: Date(timeIntervalSince1970: 0))
    let data = WebhookPayload.json(from: event)
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(obj["task"] as? String == "a\"b")
    #expect(obj["message"] as? String == "line1\nline2 \u{4e16}\u{754c}")
}
