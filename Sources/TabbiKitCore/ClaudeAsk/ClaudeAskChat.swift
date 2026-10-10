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
        /// Screenshots sent with a question. Absent in files written before
        /// attachments existed, and left out when empty.
        public var attachments: [ClaudeAskAttachment]

        public init(role: ClaudeAskMessage.Role, text: String, status: ClaudeAskMessage.Status = .complete,
                    attachments: [ClaudeAskAttachment] = []) {
            self.role = role
            self.text = text
            self.status = status
            self.attachments = attachments
        }

        private enum CodingKeys: String, CodingKey {
            case role, text, status, attachments
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(ClaudeAskMessage.Role.self, forKey: .role)
            text = try container.decode(String.self, forKey: .text)
            status = try container.decode(ClaudeAskMessage.Status.self, forKey: .status)
            attachments = try container.decodeIfPresent([ClaudeAskAttachment].self, forKey: .attachments) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(text, forKey: .text)
            try container.encode(status, forKey: .status)
            if !attachments.isEmpty { try container.encode(attachments, forKey: .attachments) }
        }
    }

    public var id: UUID
    public var createdAt: Date
    /// When the last answer arrived; the history lists newest first by this.
    public var updatedAt: Date
    /// The CLI session the chat continues with `--resume`, if it had one.
    public var sessionID: String?
    /// The command line tool that holds `sessionID`.
    public var sessionProvider: AIProviderID?
    public var messages: [Message]

    public init(id: UUID, createdAt: Date, updatedAt: Date, sessionID: String?,
                sessionProvider: AIProviderID? = nil, messages: [Message]) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionID = sessionID
        self.sessionProvider = sessionID == nil ? nil : sessionProvider
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, sessionID, sessionProvider, messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        // A tool this build doesn't know (written by a newer one) just
        // means the session can't be resumed here.
        sessionProvider = (try? container.decodeIfPresent(AIProviderID.self, forKey: .sessionProvider)) ?? nil
        messages = try container.decode([Message].self, forKey: .messages)
    }

    /// The first question on one line, short enough for a history row.
    public var title: String {
        let question = messages.first(where: { $0.role == .user })?.text
        let oneLine = question?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return ClaudeAskConversation.summarize(oneLine, limit: Self.titleLimit) ?? "Untitled chat"
    }

    static let titleLimit = 60

    /// Every screenshot in the chat, in message order.
    public var attachments: [ClaudeAskAttachment] { messages.flatMap(\.attachments) }
}

/// Keeps Ask Claude chats on this Mac, one JSON file per chat
/// (`<id>.json`) in the edition's `Claude Chats` folder, with the chat's
/// screenshots in a `<id>` folder beside it.
///
/// Writes are atomic. A corrupt file is skipped when listing, so one bad
/// chat never hides the rest. Not thread-safe; own it from a single actor.
public final class ClaudeAskHistory {
    public let directory: URL
    private let fileManager: FileManager

    public static let folderName = "Claude Chats"

    /// The chat file format. Version 1 is the first. Version 2 records which
    /// tool holds the session; every earlier chat was Claude Code's.
    public static let schema = VersionedJSON(current: 2, migrations: [
        .init(version: 2) { chat in
            if chat["sessionID"] is String, chat["sessionProvider"] == nil {
                chat["sessionProvider"] = AIProviderID.claudeCLI.rawValue
            }
        },
    ])

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

    /// Where a chat's screenshots are kept once it is saved.
    public func attachmentsDirectory(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
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

    /// Removes one chat and its screenshots. Removing a chat that isn't
    /// saved is not an error.
    public func delete(_ id: UUID) throws {
        for url in [fileURL(for: id), attachmentsDirectory(for: id)]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Removes every chat file, readable or not, and every chat's
    /// screenshot folder, and leaves unrelated files in the folder alone.
    public func deleteAll() throws {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            let id = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
            guard UUID(uuidString: id) != nil else { continue }
            try fileManager.removeItem(at: directory.appendingPathComponent(name))
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

extension ClaudeAskChat {
    /// When the chat was last answered, as a history row shows it: the time
    /// today, "Yesterday", the weekday within the past week, then the date
    /// (with the year once it is another year).
    public func dateLabel(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let day = calendar.startOfDay(for: updatedAt)
        let today = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let template: String
        switch daysAgo {
        case ..<1: template = "jmm"
        case 1: return "Yesterday"
        case 2..<7: template = "EEEE"
        default:
            let sameYear = calendar.component(.year, from: updatedAt) == calendar.component(.year, from: now)
            template = sameYear ? "MMMd" : "yMMMd"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: updatedAt)
    }

    /// Sample saved chats for `TABBI_DEMO=1`, newest first. The first is
    /// the demo conversation, which the panel opens on launch. With
    /// `screenshot`, the second is a question asked about that screenshot
    /// (`demoScreenshotChat`), so the demo shows a sent thumbnail too.
    public static func demoHistory(now: Date, screenshot: ClaudeAskAttachment? = nil) -> [ClaudeAskChat] {
        let hour: TimeInterval = 3600
        func chat(_ question: String, _ answer: String, hoursAgo: Double, session: String) -> ClaudeAskChat {
            let date = now.addingTimeInterval(-hoursAgo * hour)
            return ClaudeAskChat(
                id: UUID(), createdAt: date, updatedAt: date, sessionID: session,
                messages: [Message(role: .user, text: question), Message(role: .assistant, text: answer)]
            )
        }
        var current = ClaudeAskConversation.demo.savedChat(updatedAt: now.addingTimeInterval(-0.2 * hour))
        current?.createdAt = now.addingTimeInterval(-0.2 * hour)
        let withScreenshot = screenshot.map { demoScreenshotChat($0, at: now.addingTimeInterval(-1.5 * hour)) }
        return [current, withScreenshot].compactMap { $0 } + [
            chat("Explain the difference between a mutex and a semaphore",
                 "A **mutex** lets one thread in at a time and is released by the thread that took it. "
                     + "A **semaphore** counts, so up to *n* threads can hold it.",
                 hoursAgo: 5, session: "demo-session-2"),
            chat("Write a polite reminder about the overdue invoice",
                 "Hi Sam, a quick reminder that invoice 1042 was due last Friday. Could you take a look this week?",
                 hoursAgo: 28, session: "demo-session-3"),
            chat("Quick dinner ideas with chickpeas and spinach",
                 "- Chickpea and spinach curry\n- Crispy chickpeas over garlicky spinach\n- A warm salad with feta",
                 hoursAgo: 80, session: "demo-session-4"),
            chat("Summarize the main ideas of spaced repetition",
                 "Review just before you would forget, and stretch the gap each time you remember.",
                 hoursAgo: 24 * 12, session: "demo-session-5"),
        ]
    }

    /// A sample chat whose question carries `screenshot`, for demo and
    /// snapshot runs, which never record the real screen.
    public static func demoScreenshotChat(_ screenshot: ClaudeAskAttachment, at date: Date) -> ClaudeAskChat {
        ClaudeAskChat(
            id: UUID(), createdAt: date, updatedAt: date, sessionID: "demo-session-screenshot",
            messages: [
                Message(role: .user, text: "How can I make this page easier to read?", attachments: [screenshot]),
                Message(role: .assistant, text: "Shorten the lines to about **70 characters** and darken the grey text."),
            ]
        )
    }
}
