import Foundation

/// The format of one kind of JSON document Tabbi writes to disk or to
/// `UserDefaults`, with the ordered steps that bring older documents up to it.
///
/// Every document is a JSON object carrying a top-level `schemaVersion`;
/// documents written before versions existed have none and count as 0.
/// Decoding first runs each step newer than the document's version on the
/// raw JSON object, so a renamed or reshaped field is fixed up once, in one
/// place, before the `Codable` type sees it. To change a format, bump the
/// schema with a new step at the end; never edit a step that has shipped.
///
/// A document from a newer build (after a downgrade) is decoded as it is:
/// the `Codable` types ignore keys they don't know and default the ones
/// they miss, so an older build still reads what it can.
public struct VersionedJSON: Sendable {
    /// One step: upgrades a document at `version - 1` to `version` by
    /// rewriting its top-level JSON object.
    public struct Migration: Sendable {
        public let version: Int
        public let migrate: @Sendable (inout [String: Any]) throws -> Void

        public init(version: Int, migrate: @escaping @Sendable (inout [String: Any]) throws -> Void) {
            self.version = version
            self.migrate = migrate
        }
    }

    public static let versionKey = "schemaVersion"

    /// The version this build writes.
    public let current: Int
    /// Steps up to `current`, in order.
    public let migrations: [Migration]

    /// A format at `current` whose older versions need the given steps. The
    /// steps must be in order and end at or below `current`; versions with
    /// no step (such as 0 to 1 when the version key was added) only change
    /// the recorded number.
    public init(current: Int, migrations: [Migration] = []) {
        precondition(migrations.map(\.version) == migrations.map(\.version).sorted(),
                     "Migrations must be in version order")
        precondition((migrations.last?.version ?? 0) <= current, "A migration goes past the current version")
        self.current = current
        self.migrations = migrations
    }

    /// The version recorded in `data` (0 when there is none or it isn't an object).
    public static func version(of data: Data) -> Int {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?[versionKey] as? Int ?? 0
    }

    /// Decodes `data` after running the steps its version hasn't had yet.
    public func decode<Value: Decodable>(_ type: Value.Type, from data: Data,
                                         using decoder: JSONDecoder = JSONDecoder()) throws -> Value {
        let stored = Self.version(of: data)
        let pending = migrations.filter { $0.version > stored }
        guard !pending.isEmpty else { return try decoder.decode(type, from: data) }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected a JSON object"))
        }
        for step in pending {
            try step.migrate(&object)
        }
        object[Self.versionKey] = current
        return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    /// Encodes `value` (which must encode as a JSON object) with this
    /// schema's `current` version alongside its own keys.
    public func encode<Value: Encodable>(_ value: Value,
                                         using encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(Stamped(value: value, version: current))
    }

    /// Writes the value's keys and `schemaVersion` into one JSON object.
    private struct Stamped<Wrapped: Encodable>: Encodable {
        let value: Wrapped
        let version: Int

        private struct VersionKey: CodingKey {
            var stringValue: String { VersionedJSON.versionKey }
            var intValue: Int? { nil }
            init() {}
            init?(stringValue: String) { nil }
            init?(intValue: Int) { nil }
        }

        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
            var container = encoder.container(keyedBy: VersionKey.self)
            try container.encode(version, forKey: VersionKey())
        }
    }
}
