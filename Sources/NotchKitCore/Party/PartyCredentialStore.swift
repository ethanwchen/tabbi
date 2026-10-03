import Foundation
import Security

/// What `POST /v1/register` hands back that the app must keep: the secret
/// bearer token and the public friend code.
public struct PartyCredentials: Codable, Hashable, Sendable {
    public var token: String
    public var code: String

    public init(token: String, code: String) {
        self.token = token
        self.code = code
    }

    public init(_ registration: PartyRegistration) {
        self.init(token: registration.token, code: registration.code)
    }
}

/// Keeps one identity per friends server. The server only stores the
/// token's hash, so losing it means a new friend code; switching servers
/// must not overwrite the identity on the other one.
public protocol PartyCredentialStore: Sendable {
    func load(for server: URL) -> PartyCredentials?
    func save(_ credentials: PartyCredentials, for server: URL) throws
    func delete(for server: URL) throws
}

extension PartyServer {
    /// A stable key for a server URL: lower-cased scheme and host, port,
    /// and path without trailing slashes, so `HTTPS://Host/` and
    /// `https://host` share one identity.
    public static func identityKey(for server: URL) -> String {
        let scheme = server.scheme?.lowercased() ?? "https"
        let host = server.host?.lowercased() ?? ""
        let port = server.port.map { ":\($0)" } ?? ""
        var path = server.path
        while path.hasSuffix("/") { path.removeLast() }
        return "\(scheme)://\(host)\(port)\(path)"
    }
}

/// Stores credentials as generic passwords in the login Keychain, one item
/// per server (`kSecAttrAccount` is `PartyServer.identityKey`), as the API
/// contract asks.
public struct KeychainPartyCredentialStore: PartyCredentialStore {
    /// The Keychain service; one per app edition keeps their identities apart.
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func load(for server: URL) -> PartyCredentials? {
        var query = baseQuery(for: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(PartyCredentials.self, from: data)
    }

    public func save(_ credentials: PartyCredentials, for server: URL) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery(for: server)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "Tabbi friends (\(server.host ?? "server"))"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        default:
            throw KeychainError(status: status)
        }
    }

    public func delete(for server: URL) throws {
        let status = SecItemDelete(baseQuery(for: server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(for server: URL) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: PartyServer.identityKey(for: server),
        ]
    }

    /// A Keychain call that failed, with its `OSStatus`.
    public struct KeychainError: Error, Hashable, Sendable {
        public let status: OSStatus
    }
}

/// Keeps credentials in memory only: for tests, demo mode and snapshots,
/// which must never touch the user's Keychain.
public final class InMemoryPartyCredentialStore: PartyCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: PartyCredentials]

    public init(_ items: [URL: PartyCredentials] = [:]) {
        self.items = Dictionary(items.map { (PartyServer.identityKey(for: $0.key), $0.value) },
                                uniquingKeysWith: { _, last in last })
    }

    public func load(for server: URL) -> PartyCredentials? {
        lock.withLock { items[PartyServer.identityKey(for: server)] }
    }

    public func save(_ credentials: PartyCredentials, for server: URL) {
        lock.withLock { items[PartyServer.identityKey(for: server)] = credentials }
    }

    public func delete(for server: URL) {
        lock.withLock { _ = items.removeValue(forKey: PartyServer.identityKey(for: server)) }
    }
}
