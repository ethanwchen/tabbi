import Foundation
import Security

/// Keeps the user's API keys for the hosted providers. Keys never go into
/// `UserDefaults` or a file: the app stores them in the Keychain, and
/// tests, demo mode and snapshots keep them in memory.
public protocol AIKeyStore: Sendable {
    func key(for provider: AIProviderID) -> String?
    /// Saves `key` for `provider`; nil or blank deletes it.
    func setKey(_ key: String?, for provider: AIProviderID) throws
}

extension AIKeyStore {
    public func hasKey(for provider: AIProviderID) -> Bool { key(for: provider) != nil }

    /// Trims a pasted key; blank is no key.
    static func cleaned(_ key: String?) -> String? {
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Stores each key as a generic password in the login Keychain, one item
/// per provider (`kSecAttrAccount` is the provider's raw value).
public struct KeychainAIKeyStore: AIKeyStore {
    /// The Keychain service; one per app edition keeps their keys apart.
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func key(for provider: AIProviderID) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return Self.cleaned(String(data: data, encoding: .utf8))
    }

    public func setKey(_ key: String?, for provider: AIProviderID) throws {
        let query = baseQuery(for: provider)
        guard let key = Self.cleaned(key) else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "Tabbi \(provider.displayName) key"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        default:
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(for provider: AIProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    /// A Keychain call that failed, with its `OSStatus`.
    public struct KeychainError: Error, Hashable, Sendable {
        public let status: OSStatus
    }
}

/// Keeps keys in memory only: for tests, demo mode and snapshots, which
/// must never touch the user's Keychain.
public final class InMemoryAIKeyStore: AIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [AIProviderID: String]

    public init(_ keys: [AIProviderID: String] = [:]) {
        self.keys = keys.compactMapValues { Self.cleaned($0) }
    }

    public func key(for provider: AIProviderID) -> String? {
        lock.withLock { keys[provider] }
    }

    public func setKey(_ key: String?, for provider: AIProviderID) {
        lock.withLock { keys[provider] = Self.cleaned(key) }
    }
}
