import Testing
import Foundation
@testable import AutoTriggerCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func okWhenWithinIntervalPlusGrace() {
    let e = HeartbeatEvaluator()
    let status = e.status(
        now: t0.addingTimeInterval(50),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 0)
    #expect(status == .ok)
}

@Test func overdueWhenAwakePastIntervalPlusGrace() {
    let e = HeartbeatEvaluator()
    let status = e.status(
        now: t0.addingTimeInterval(200),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 0)
    #expect(status == .overdue)
}
