import Foundation

/// An Ask Claude chat as it is kept in the history on this Mac.
///
/// Only finished exchanges are stored (see `ClaudeAskConversation.savedChat`),
/// so a restored chat reads like the one the user left.
public struct ClaudeAskChat: Codable, Identifiable, Equatable, Sendable {
    public struct Message: Codable, Equatable, Sendable {
        public var role: ClaudeAskMessage.Role
        public var text: String
        public var status: ClaudeAskMessage.Status

        public init(role: ClaudeAskMessage.Role, text: String, status: ClaudeAskMessage.Status = .complete) {
            self.role = role
            self.text = text
            self.status = status
        }
    }

    public var id: UUID
    public var createdAt: Date
    /// When the last answer arrived; the history lists newest first by this.
    public var updatedAt: Date
    /// The CLI session the chat continues with `--resume`, if it had one.
    public var sessionID: String?
    public var messages: [Message]

    public init(id: UUID, createdAt: Date, updatedAt: Date, sessionID: String?, messages: [Message]) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionID = sessionID
        self.messages = messages
    }

    /// The first question on one line, short enough for a history row.
    public var title: String {
        let question = messages.first(where: { $0.role == .user })?.text
        let oneLine = question?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return ClaudeAskConversation.summarize(oneLine, limit: Self.titleLimit) ?? "Untitled chat"
    }

    static let titleLimit = 60
}

/// Keeps Ask Claude chats on this Mac, one JSON file per chat
/// (`<id>.json`) in the edition's `Claude Chats` folder.
///
/// Writes are atomic. A corrupt file is skipped when listing, so one bad
/// chat never hides the rest. Not thread-safe; own it from a single actor.
public final class ClaudeAskHistory {
    public let directory: URL
    private let fileManager: FileManager

    public static let folderName = "Claude Chats"

    /// The chat file format. Version 1 is the first.
    public static let schema = VersionedJSON(current: 1)

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// The edition's chat folder.
    public convenience init(storage: EditionStorage) {
        self.init(directory: storage.folder(Self.folderName))
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    /// Every readable saved chat, the most recently answered first.
    public func chats() -> [ClaudeAskChat] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .compactMap { name -> UUID? in
                guard name.hasSuffix(".json") else { return nil }
                return UUID(uuidString: String(name.dropLast(5)))
            }
            .compactMap { try? load($0) }
            .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    /// The saved chat, or nil if none exists. Throws if the file is corrupt.
    public func load(_ id: UUID) throws -> ClaudeAskChat? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        var chat = try Self.schema.decode(ClaudeAskChat.self, from: Data(contentsOf: url), using: Self.decoder)
        // The file name is authoritative, so a copied file can't shadow another chat.
        chat.id = id
        return chat
    }

    public func save(_ chat: ClaudeAskChat) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.schema.encode(chat, using: Self.encoder).write(to: fileURL(for: chat.id), options: .atomic)
    }

    /// Removes one chat. Removing a chat that isn't saved is not an error.
    public func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Removes every chat file, readable or not, and leaves unrelated files
    /// in the folder alone.
    public func deleteAll() throws {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".json") && UUID(uuidString: String(name.dropLast(5))) != nil {
            try fileManager.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
