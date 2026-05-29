import Testing
@testable import AutoTriggerCore

@Test func webhookURLKeyIsStable() {
    #expect(SecretKeys.webhookURL == "webhook-url")
}
