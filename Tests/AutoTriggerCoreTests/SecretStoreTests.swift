import Testing
@testable import AutoTriggerCore

@Test func inMemorySecretStoreRoundTrips() throws {
    let store = InMemorySecretStore()
    #expect(try store.get("webhookURL") == nil)
    try store.set("https://hooks.example.com/abc", for: "webhookURL")
    #expect(try store.get("webhookURL") == "https://hooks.example.com/abc")
}

@Test func inMemorySecretStoreOverwritesAndDeletes() throws {
    let store = InMemorySecretStore()
    try store.set("v1", for: "k")
    try store.set("v2", for: "k")
    #expect(try store.get("k") == "v2")
    try store.delete("k")
    #expect(try store.get("k") == nil)
}
