import Testing
import Foundation
@testable import AutoTriggerCore

@Suite struct TaskHealthTests {
    private let task = MonitoredTask(
        id: "t", displayName: "T", expectedInterval: 3_600, grace: 600, source: .manual
    )

    private func run(exit: Int32, finishedAgo: TimeInterval, now: Date) -> RunRecord {
        let finished = now.addingTimeInterval(-finishedAgo)
        return RunRecord(taskLabel: "t", startedAt: finished.addingTimeInterval(-1),
                         finishedAt: finished, exitCode: exit, stdout: "", stderr: "")
    }

    @Test func neverRanWhenNoRuns() {
        let h = TaskHealthEvaluator().health(task: task, recentRuns: [], now: Date(), asleepSeconds: 0)
        #expect(h == .neverRan)
    }

    @Test func failedWhenLatestExitNonzero() {
        let now = Date()
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 1, finishedAgo: 60, now: now)], now: now, asleepSeconds: 0
        )
        #expect(h == .failed)
    }

    @Test func okWhenRecentSuccessWithinInterval() {
        let now = Date()
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 0, finishedAgo: 60, now: now)], now: now, asleepSeconds: 0
        )
        #expect(h == .ok)
    }

    @Test func overdueWhenSuccessTooOldAndAwake() {
        let now = Date()
        // finished 10000s ago, interval+grace = 4200s, asleep 0 → overdue
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 0, finishedAgo: 10_000, now: now)], now: now, asleepSeconds: 0
        )
        #expect(h == .overdue)
    }

    @Test func notOverdueWhenAsleepThroughTheWindow() {
        let now = Date()
        // finished 10000s ago but machine asleep 9000s → awake elapsed 1000s < 4200s → ok
        let h = TaskHealthEvaluator().health(
            task: task, recentRuns: [run(exit: 0, finishedAgo: 10_000, now: now)], now: now, asleepSeconds: 9_000
        )
        #expect(h == .ok)
    }

    @Test func aggregateReturnsMostSevere() {
        #expect(TaskHealth.aggregate([.ok, .neverRan, .overdue, .failed]) == .failed)
        #expect(TaskHealth.aggregate([.ok, .overdue]) == .overdue)
        #expect(TaskHealth.aggregate([.ok, .neverRan]) == .neverRan)
        #expect(TaskHealth.aggregate([.ok, .ok]) == .ok)
    }

    @Test func aggregateOfEmptyIsOK() {
        #expect(TaskHealth.aggregate([]) == .ok)
    }
}
