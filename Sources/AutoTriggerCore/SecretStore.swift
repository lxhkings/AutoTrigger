import Foundation

/// Secrets (the webhook URL) live behind this protocol so they are never written
/// to SQLite or a plist. Production uses the Keychain; tests use the in-memory fake.
public protocol SecretStore: Sendable {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

/// UserDefaults-backed store — avoids Keychain prompts for non-sensitive data.
public final class UserDefaultsSecretStore: SecretStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func set(_ value: String, for key: String) throws { defaults.set(value, forKey: key) }
    public func get(_ key: String) throws -> String? { defaults.string(forKey: key) }
    public func delete(_ key: String) throws { defaults.removeObject(forKey: key) }
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
