import Foundation

/// A screenshot sent with an Ask Claude question.
///
/// The image itself is a PNG file named after `id`. It waits in a staging
/// folder until the chat is saved, then moves next to the chat in the
/// history (see `ClaudeAskAttachmentStore`), so the message only records
/// what the panel needs to find and lay out its thumbnail.
public struct ClaudeAskAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var pixelWidth: Int
    public var pixelHeight: Int

    public static let mediaType = "image/png"

    public init(id: UUID = UUID(), pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var fileName: String { "\(id.uuidString).png" }

    /// The longest edge Claude reads at full detail. Larger images are scaled
    /// down by the model anyway, so sending them only costs time and tokens.
    public static let maxLongEdge = 1568

    /// The size to scale a capture of `width` x `height` pixels to before it
    /// is attached: the same aspect ratio with the long edge at most
    /// `maxLongEdge`, never scaled up, and at least 1 pixel on each side.
    public static func fittedPixelSize(width: Int, height: Int, maxLongEdge: Int = maxLongEdge) -> (width: Int, height: Int) {
        let width = max(width, 1)
        let height = max(height, 1)
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge else { return (width, height) }
        let scale = Double(maxLongEdge) / Double(longEdge)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}

/// Where Ask Claude keeps screenshot files.
///
/// A new capture is staged in a temporary folder. When its chat is saved
/// the file moves into the chat's own folder beside the chat file
/// (`ClaudeAskHistory.attachmentsDirectory(for:)`), and deleting the chat
/// deletes it. A capture whose chat is never saved (demo and snapshot runs,
/// or a failed question) is discarded once it is answered, and anything
/// left in staging is cleared at the next launch.
/// Not thread-safe; own it from a single actor.
public final class ClaudeAskAttachmentStore {
    public let stagingDirectory: URL
    private let history: ClaudeAskHistory?
    private let fileManager: FileManager

    /// `history` is nil when chats are not saved; then every capture stays
    /// staged until it is discarded.
    public init(stagingDirectory: URL, history: ClaudeAskHistory?, fileManager: FileManager = .default) {
        self.stagingDirectory = stagingDirectory
        self.history = history
        self.fileManager = fileManager
    }

    /// Writes a new capture to staging.
    public func stage(pngData: Data, pixelWidth: Int, pixelHeight: Int) throws -> ClaudeAskAttachment {
        let attachment = ClaudeAskAttachment(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try pngData.write(to: stagedURL(for: attachment), options: .atomic)
        return attachment
    }

    /// The file for `attachment`: kept with `chatID` or still staged, or nil
    /// when it is gone (for example after the chat was deleted).
    public func url(for attachment: ClaudeAskAttachment, in chatID: UUID) -> URL? {
        [keptURL(for: attachment, in: chatID), stagedURL(for: attachment)]
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    /// The image bytes, read from wherever the file is now.
    public func data(for attachment: ClaudeAskAttachment, in chatID: UUID) -> Data? {
        url(for: attachment, in: chatID).flatMap { try? Data(contentsOf: $0) }
    }

    /// Moves staged files into the saved chat's folder. Files already kept
    /// (or missing) are left as they are. Does nothing without a history.
    public func keep(_ attachments: [ClaudeAskAttachment], in chatID: UUID) throws {
        guard let history else { return }
        let folder = history.attachmentsDirectory(for: chatID)
        for attachment in attachments {
            let staged = stagedURL(for: attachment)
            guard fileManager.fileExists(atPath: staged.path) else { continue }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let kept = folder.appendingPathComponent(attachment.fileName, isDirectory: false)
            if fileManager.fileExists(atPath: kept.path) { try fileManager.removeItem(at: kept) }
            try fileManager.moveItem(at: staged, to: kept)
        }
    }

    /// Deletes staged files. Kept files belong to a saved chat and stay.
    public func discard(_ attachments: [ClaudeAskAttachment]) {
        for attachment in attachments {
            try? fileManager.removeItem(at: stagedURL(for: attachment))
        }
    }

    /// Deletes everything in staging, for captures a previous run left behind.
    public func clearStaging() {
        try? fileManager.removeItem(at: stagingDirectory)
    }

    private func stagedURL(for attachment: ClaudeAskAttachment) -> URL {
        stagingDirectory.appendingPathComponent(attachment.fileName, isDirectory: false)
    }

    private func keptURL(for attachment: ClaudeAskAttachment, in chatID: UUID) -> URL? {
        history?.attachmentsDirectory(for: chatID).appendingPathComponent(attachment.fileName, isDirectory: false)
    }
}
