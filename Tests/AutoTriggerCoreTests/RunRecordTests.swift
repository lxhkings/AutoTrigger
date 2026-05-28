import Testing
import Foundation
@testable import AutoTriggerCore

@Test func truncateLeavesShortStringsUntouched() {
    #expect(RunRecord.truncate("hello", max: 100) == "hello")
}

@Test func truncateCutsLongStringsAndMarks() {
    let long = String(repeating: "x", count: 50)
    let out = RunRecord.truncate(long, max: 10)
    #expect(out.count <= 10 + RunRecord.truncationMarker.count)
    #expect(out.hasSuffix(RunRecord.truncationMarker))
    #expect(out.hasPrefix("xxxxxxxxxx"))
}
