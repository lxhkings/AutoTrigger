# AutoTrigger Alert Webhook (T5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver alerts off-device via a single user-configured webhook, with retry on transient failure, and store the webhook URL securely in the Keychain.

**Architecture:** Three units in `AutoTriggerCore`: a pure `WebhookPayload` JSON formatter, an `AlertDispatcher` with injectable sender + bounded retry (TDD with a fake sender), and a `SecretStore` protocol with an in-memory fake (for unit tests) and a real `KeychainSecretStore` (Security framework, integration). The webhook URL never lands in SQLite or a plist — only the Keychain.

**Tech Stack:** Swift 6.3, Foundation (`URLSession`), Security framework (Keychain), Swift Testing (async tests). Extends the existing `AutoTriggerCore` library.

**Depends on:** Nothing in T2-T4 directly — consumes an `AlertEvent` value. The heartbeat daemon and the wrapper both produce `AlertEvent`s that this layer delivers.

**Locked decision (CEO scope):** minimal off-device channel = one generic webhook (user points it at Slack/ntfy/Pushover themselves). No multi-channel UI in v1.

---

### Task 1: AlertEvent + WebhookPayload JSON (pure)

**Files:**
- Create: `Sources/AutoTriggerCore/AlertEvent.swift`
- Create: `Sources/AutoTriggerCore/WebhookPayload.swift`
- Test: `Tests/AutoTriggerCoreTests/WebhookPayloadTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/WebhookPayloadTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WebhookPayload`
Expected: FAIL — `cannot find 'AlertEvent' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/AlertEvent.swift`:

```swift
import Foundation

public struct AlertEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case overdue, failed }
    public let taskLabel: String
    public let kind: Kind
    public let message: String
    public let timestamp: Date

    public init(taskLabel: String, kind: Kind, message: String, timestamp: Date) {
        self.taskLabel = taskLabel
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
    }
}
```

`Sources/AutoTriggerCore/WebhookPayload.swift`:

```swift
import Foundation

/// Serializes an AlertEvent into a generic JSON body the user can route to
/// Slack / ntfy / Pushover via their own webhook.
public enum WebhookPayload {
    public static func json(from event: AlertEvent) -> Data {
        let dict: [String: Any] = [
            "task": event.taskLabel,
            "kind": event.kind.rawValue,
            "message": event.message,
            "timestamp": event.timestamp.timeIntervalSince1970
        ]
        // sortedKeys = stable output for tests; JSONSerialization handles escaping.
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WebhookPayload`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/AlertEvent.swift Sources/AutoTriggerCore/WebhookPayload.swift Tests/AutoTriggerCoreTests/WebhookPayloadTests.swift
git commit -m "feat: add AlertEvent and WebhookPayload JSON formatter"
```

---

### Task 2: AlertDispatcher with bounded retry

**Files:**
- Create: `Sources/AutoTriggerCore/AlertDispatcher.swift`
- Test: `Tests/AutoTriggerCoreTests/AlertDispatcherTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/AlertDispatcherTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AlertDispatcher`
Expected: FAIL — `cannot find 'AlertDispatcher' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/AlertDispatcher.swift`:

```swift
import Foundation

/// Abstracts the HTTP POST so retry logic is testable without the network.
public protocol WebhookSender: Sendable {
    func send(_ body: Data, to url: URL) async throws
}

public enum AlertDispatcherError: Error { case allAttemptsFailed }

/// Posts an alert to a webhook, retrying transient failures up to maxAttempts.
public struct AlertDispatcher: Sendable {
    private let sender: any WebhookSender
    private let maxAttempts: Int
    private let retryDelay: TimeInterval

    public init(sender: any WebhookSender, maxAttempts: Int = 3, retryDelay: TimeInterval = 2) {
        self.sender = sender
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelay = retryDelay
    }

    public func dispatch(_ event: AlertEvent, to url: URL) async throws {
        let body = WebhookPayload.json(from: event)
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try await sender.send(body, to: url)
                return
            } catch {
                lastError = error
                if attempt < maxAttempts, retryDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? AlertDispatcherError.allAttemptsFailed
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AlertDispatcher`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/AlertDispatcher.swift Tests/AutoTriggerCoreTests/AlertDispatcherTests.swift
git commit -m "feat: add AlertDispatcher with bounded retry over injectable sender"
```

---

### Task 3: real URLSession sender

**Files:**
- Create: `Sources/AutoTriggerCore/URLSessionWebhookSender.swift`
- Test: `Tests/AutoTriggerCoreTests/URLSessionWebhookSenderTests.swift`

- [ ] **Step 1: Write the failing test (with a mock URLProtocol)**

`Tests/AutoTriggerCoreTests/URLSessionWebhookSenderTests.swift`:

```swift
import Testing
import Foundation
@testable import AutoTriggerCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        MockURLProtocol.lastBody = request.httpBody
            ?? request.httpBodyStream.map { stream -> Data in
                stream.open(); defer { stream.close() }
                var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }
                    data.append(buf, count: n)
                }
                return data
            }
        let resp = HTTPURLResponse(url: request.url!, statusCode: MockURLProtocol.statusCode,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@Test func senderPostsBodyAndAccepts2xx() async throws {
    MockURLProtocol.statusCode = 200
    let sender = URLSessionWebhookSender(session: mockSession())
    let body = Data("{\"ok\":true}".utf8)
    try await sender.send(body, to: URL(string: "https://example.com/hook")!)
    #expect(MockURLProtocol.lastBody == body)
}

@Test func senderThrowsOnNon2xx() async {
    MockURLProtocol.statusCode = 500
    let sender = URLSessionWebhookSender(session: mockSession())
    await #expect(throws: (any Error).self) {
        try await sender.send(Data("{}".utf8), to: URL(string: "https://example.com/hook")!)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter URLSessionWebhookSender`
Expected: FAIL — `cannot find 'URLSessionWebhookSender' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/URLSessionWebhookSender.swift`:

```swift
import Foundation

public enum WebhookSendError: Error { case badStatus(Int) }

/// Production WebhookSender: POSTs the JSON body, treats non-2xx as failure
/// (so AlertDispatcher retries it).
public struct URLSessionWebhookSender: WebhookSender {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ body: Data, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw WebhookSendError.badStatus(http.statusCode)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter URLSessionWebhookSender`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/URLSessionWebhookSender.swift Tests/AutoTriggerCoreTests/URLSessionWebhookSenderTests.swift
git commit -m "feat: add URLSession webhook sender treating non-2xx as retryable failure"
```

---

### Task 4: SecretStore protocol + in-memory fake (webhook URL never in plaintext)

**Files:**
- Create: `Sources/AutoTriggerCore/SecretStore.swift`
- Test: `Tests/AutoTriggerCoreTests/SecretStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AutoTriggerCoreTests/SecretStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SecretStore`
Expected: FAIL — `cannot find 'InMemorySecretStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AutoTriggerCore/SecretStore.swift`:

```swift
import Foundation

/// Secrets (the webhook URL) live behind this protocol so they are never written
/// to SQLite or a plist. Production uses the Keychain; tests use the in-memory fake.
public protocol SecretStore: Sendable {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func set(_ value: String, for key: String) throws {
        lock.lock(); storage[key] = value; lock.unlock()
    }
    public func get(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }; return storage[key]
    }
    public func delete(_ key: String) throws {
        lock.lock(); storage[key] = nil; lock.unlock()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SecretStore`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AutoTriggerCore/SecretStore.swift Tests/AutoTriggerCoreTests/SecretStoreTests.swift
git commit -m "feat: add SecretStore protocol + in-memory fake for webhook URL"
```

---

### Task 5: KeychainSecretStore (integration — real Keychain)

The real Keychain implementation. Keychain access under `swift test` is unreliable without a signed host/entitlements, so this is verified in the running (signed) app, not in unit tests. The in-memory fake (Task 4) covers the protocol contract for logic that depends on `SecretStore`.

**Files:**
- Create: `Sources/AutoTriggerCore/KeychainSecretStore.swift`

- [ ] **Step 1: Implement**

`Sources/AutoTriggerCore/KeychainSecretStore.swift`:

```swift
import Foundation
import Security

public enum KeychainError: Error { case status(OSStatus) }

/// Generic-password Keychain backing for SecretStore. Service-scoped so all
/// AutoTrigger secrets live under one service name.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.autotrigger.secrets") { self.service = service }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(key)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let upd = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard upd == errSecSuccess else { throw KeychainError.status(upd) }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let add = SecItemAdd(query as CFDictionary, nil)
            guard add == errSecSuccess else { throw KeychainError.status(add) }
        } else {
            throw KeychainError.status(status)
        }
    }

    public func get(_ key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Manual integration verification (document in PR, do not automate)**

In the running signed app: `try KeychainSecretStore().set("https://x", for: "webhookURL")`, relaunch, `get("webhookURL")` returns it; verify it appears in Keychain Access under service `com.autotrigger.secrets`. Note the result in the PR description.

- [ ] **Step 4: Commit**

```bash
git add Sources/AutoTriggerCore/KeychainSecretStore.swift
git commit -m "feat: add KeychainSecretStore for webhook URL (integration-verified)"
```

---

## Out of scope for this plan

- Wiring `AlertDispatcher` into the heartbeat daemon / wrapper (who calls `dispatch`) — that's the daemon's job; this plan delivers the unit.
- Notification Center alerts (the on-device channel) — separate small piece; this plan is the off-device webhook only.
- Webhook config UI in the menubar app (entering/testing the URL) — the menubar-app plan owns the UI; it calls `SecretStore.set`.

## Self-Review

- **Spec coverage:** T5 = "最小 webhook 告警渠道, URL 存 Keychain" → Tasks 1 (payload), 2 (dispatcher+retry), 3 (real sender), 4 (SecretStore contract), 5 (Keychain impl). Off-device delivery + secure URL storage both covered.
- **Placeholder scan:** Keychain (Task 5) is integration-verified not unit-tested — explicitly flagged, with the in-memory fake (Task 4) covering the protocol contract. No hidden TODOs in the testable units (payload/dispatcher/sender all fully tested).
- **Type consistency:** `WebhookSender.send(_:to:)`, `AlertDispatcher(sender:maxAttempts:retryDelay:)` + `dispatch(_:to:)`, `URLSessionWebhookSender(session:)`, `SecretStore` (`set(_:for:)`/`get(_:)`/`delete(_:)`) implemented by both `InMemorySecretStore` and `KeychainSecretStore`, `AlertEvent(taskLabel:kind:message:timestamp:)`, `WebhookPayload.json(from:)` consistent across tasks.
