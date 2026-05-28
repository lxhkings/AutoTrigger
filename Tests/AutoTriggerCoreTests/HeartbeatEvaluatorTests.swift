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

@Test func notOverdueWhenAsleepThroughTheWindow() {
    let e = HeartbeatEvaluator()
    // 200s of wall time passed, but 180s of it the machine was asleep →
    // only 20s of awake time, well under 60+30.
    let status = e.status(
        now: t0.addingTimeInterval(200),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 180)
    #expect(status == .ok)
}

@Test func overdueWhenAwakeEnoughEvenWithSomeSleep() {
    let e = HeartbeatEvaluator()
    // 300s wall, 100s asleep → 200s awake > 60+30 → overdue.
    let status = e.status(
        now: t0.addingTimeInterval(300),
        lastSuccess: t0,
        monitoringStarted: t0,
        expectedInterval: 60, grace: 30,
        asleepSecondsSinceReference: 100)
    #expect(status == .overdue)
}

@Test func neverRanIsOkUntilFirstAwakeWindowElapses() {
    let e = HeartbeatEvaluator()
    // No successful run yet; only 20s awake since monitoring started → ok.
    let early = e.status(now: t0.addingTimeInterval(20), lastSuccess: nil,
                         monitoringStarted: t0, expectedInterval: 60, grace: 30,
                         asleepSecondsSinceReference: 0)
    #expect(early == .ok)
    // 200s awake since start, still never ran → overdue.
    let late = e.status(now: t0.addingTimeInterval(200), lastSuccess: nil,
                        monitoringStarted: t0, expectedInterval: 60, grace: 30,
                        asleepSecondsSinceReference: 0)
    #expect(late == .overdue)
}
