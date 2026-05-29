import Testing
import Foundation
@testable import AutoTriggerCore

@Suite struct MonitoredTaskTests {
    @Test func codableRoundTrips() throws {
        let task = MonitoredTask(
            id: "com.example.backup",
            displayName: "Nightly Backup",
            expectedInterval: 86_400,
            grace: 3_600,
            source: .launchd
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(MonitoredTask.self, from: data)
        #expect(decoded == task)
    }
}
