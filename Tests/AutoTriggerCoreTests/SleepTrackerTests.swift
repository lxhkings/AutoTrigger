import Testing
@testable import AutoTriggerCore

@Test func injectedAsleepSecondsAccumulate() {
    let tracker = SleepTracker()
    tracker._testRecordAsleep(120)
    tracker._testRecordAsleep(60)
    #expect(tracker.asleepSeconds() == 180)
}
