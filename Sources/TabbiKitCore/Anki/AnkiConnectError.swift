import Foundation

/// Every way an AnkiConnect call can fail, classified into states the UI
/// can explain in one line with one clear next step.
public enum AnkiConnectError: Error, Hashable, Sendable {
    /// Connection refused and no Anki process is running.
    case ankiNotRunning
    /// Connection refused while Anki is running: the add-on is missing or
    /// disabled, or Anki is still starting (retry for ~15 s before saying so).
    case addOnMissing
    /// The request reached Anki but it did not answer in time.
    case timeout
    /// `requestPermission` was denied, or the origin was rejected (HTTP 403).
    case permissionDenied
    /// The user set an API key in AnkiConnect and ours is missing or wrong.
    case apiKeyRequired
    /// The installed add-on speaks an older API than version 6.
    case addOnOutdated(version: Int)
    /// The add-on does not know this action (too old for it).
    case unsupportedAction(String)
    /// Anki has no collection open right now. AnkiConnect answers but can't
    /// read the cards: Anki is on its profile list, or, with a profile open,
    /// it closed the collection for a while (a full sync, Check Database, a
    /// profile loading or closing). It comes back by itself in the second case.
    case collectionUnavailable
    /// `sync` was asked for but the user has not signed in to AnkiWeb.
    case syncNotConfigured
    /// Any other error string AnkiConnect returned, as Anki wrote it.
    case anki(String)
    /// The reply was not the JSON we expected.
    case invalidResponse(String)
    /// Some other network failure.
    case transport(String)

    /// The errors AnkiConnect (plugin/__init__.py) and Anki's backend return
    /// while no collection is open, compared whole so an unrelated error
    /// that merely mentions a collection is never read as one of them.
    /// `mw.col` is None: "collection is not available". The collection is
    /// open but its database or managers are gone, as during a full sync
    /// (`close_for_full_sync`): "database is not available" and friends.
    /// The collection was closed under AnkiConnect: the backend's
    /// "CollectionNotOpen". AnkiConnect 2026.10 says "Collection is not
    /// available.", and "A collection operation is active." while a sync
    /// or Check Database holds the collection. Compared lowercased, without
    /// a final period.
    static let collectionClosedMessages: Set<String> = [
        "collection is not available",
        "database is not available",
        "decks are not available",
        "scheduler is not available",
        "media is not available",
        "collectionnotopen",
        "collection session changed",
        "a collection operation is active",
        "collection lifecycle operation is active",
    ]

    /// Maps an AnkiConnect `error` string to a typed case.
    public static func fromAnkiMessage(_ message: String, action: String) -> AnkiConnectError {
        var lower = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasSuffix(".") { lower.removeLast() }
        // AnkiConnect: "valid api key must be provided".
        if lower.contains("api key") { return .apiKeyRequired }
        if lower == "unsupported action" { return .unsupportedAction(action) }
        if collectionClosedMessages.contains(lower) { return .collectionUnavailable }
        // AnkiConnect: "sync: auth not configured".
        if lower.hasSuffix("auth not configured") { return .syncNotConfigured }
        return .anki(message)
    }

    /// Whether AnkiConnect could not parse the request body as JSON
    /// (Python's "Expecting value: line 1 column 1 (char 0)" and kin): the
    /// request reached it damaged, which one retry fixes when it was a fluke.
    public var isMalformedRequest: Bool {
        guard case .anki(let message) = self else { return false }
        return message.hasPrefix("Expecting value") || message.hasPrefix("Expecting property name")
    }

    /// Whether Tabbi can't say what went wrong: Anki sent an error Tabbi
    /// doesn't know, a reply it can't read, or the request failed some other
    /// way. These show the raw message and a reminder to check the add-on.
    public var isUnexplained: Bool {
        switch self {
        case .anki, .invalidResponse, .transport: return true
        default: return false
        }
    }

    /// What Anki (or the network) actually said, cleaned up to one short
    /// line, for the unexplained errors; nil for the others.
    public var message: String? {
        switch self {
        case .anki(let text), .invalidResponse(let text), .transport(let text):
            return Self.shortMessage(text)
        default:
            return nil
        }
    }

    /// The raw message as one short line: whitespace collapsed and long
    /// text (a Python error can run on) cut at `messageLimit` characters.
    public static func shortMessage(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > messageLimit else { return line.isEmpty ? "?" : line }
        return String(line.prefix(messageLimit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// The longest message shown; enough for any AnkiConnect error, short
    /// enough for two lines of the panel.
    public static let messageLimit = 90

    /// The quoted message under an unexplained error, such as
    /// "Anki said: “database is locked”", or nil for the other errors.
    public var quotedMessage: String? {
        guard let message else { return nil }
        if case .anki = self {
            return String(localized: "Anki said: \u{201C}\(message)\u{201D}", bundle: .tabbi,
                          comment: "Anki tab and Settings > Connections: the error text Anki sent, quoted as is (stays English).")
        }
        return String(localized: "Details: \(message)", bundle: .tabbi,
                      comment: "Anki tab and Settings > Connections: a technical error message, shown as is.")
    }

    /// The reminder an unexplained error ends with: most often the add-on
    /// is missing, disabled, or Anki wasn't restarted after installing it.
    public static var addOnReminder: String {
        String(localized: "Make sure the AnkiConnect add-on is installed and Anki was restarted after installing it.", bundle: .tabbi,
               comment: "Anki tab: shown when Tabbi can't tell what went wrong. A Copy code button for the add-on sits next to it.")
    }

    /// `addOnReminder` with the add-on's code, for places without a Copy
    /// code button (tooltips, Settings > Connections).
    public static var addOnReminderWithCode: String {
        String(localized: "Make sure the AnkiConnect add-on (code \(AnkiConnectClient.addOnCode)) is installed and Anki was restarted after installing it.", bundle: .tabbi,
               comment: "Anki: shown when Tabbi can't tell what went wrong. The code is the add-on's AnkiWeb code, pasted in Tools > Add-ons > Get Add-ons.")
    }

    /// Short headline for an empty or error state.
    public var title: String {
        switch self {
        case .ankiNotRunning: return String(localized: "Anki is closed", bundle: .tabbi)
        case .addOnMissing: return String(localized: "AnkiConnect isn't answering", bundle: .tabbi)
        case .timeout: return String(localized: "Anki is busy", bundle: .tabbi)
        case .permissionDenied: return String(localized: "Anki said no", bundle: .tabbi)
        case .apiKeyRequired: return String(localized: "AnkiConnect needs your API key", bundle: .tabbi)
        case .addOnOutdated, .unsupportedAction: return String(localized: "AnkiConnect is out of date", bundle: .tabbi)
        case .collectionUnavailable: return String(localized: "Waiting for Anki", bundle: .tabbi)
        case .syncNotConfigured: return String(localized: "Sign in to AnkiWeb to sync", bundle: .tabbi)
        case .anki: return String(localized: "Anki reported a problem", bundle: .tabbi)
        case .invalidResponse: return String(localized: "Unexpected reply from Anki", bundle: .tabbi)
        case .transport: return String(localized: "Couldn't reach Anki", bundle: .tabbi)
        }
    }

    /// What to do next, in a sentence or two. For an unexplained error it
    /// also quotes the message and reminds the user to check the add-on.
    public var suggestion: String {
        switch self {
        case .ankiNotRunning:
            return String(localized: "Open Anki to see your due cards.", bundle: .tabbi)
        case .addOnMissing:
            return String(localized: "Install AnkiConnect (code \(AnkiConnectClient.addOnCode)) from Tools › Add-ons, then restart Anki.", bundle: .tabbi)
        case .timeout:
            return String(localized: "Close any open Anki dialog. If it keeps happening, turn off App Nap for Anki.", bundle: .tabbi)
        case .permissionDenied:
            return String(localized: "Allow Tabbi in AnkiConnect's settings, then try again.", bundle: .tabbi)
        case .apiKeyRequired:
            return String(localized: "Enter the key from AnkiConnect's config in Settings.", bundle: .tabbi)
        case .addOnOutdated, .unsupportedAction:
            return String(localized: "Update AnkiConnect from Tools › Add-ons › Check for Updates.", bundle: .tabbi)
        case .collectionUnavailable:
            return Self.collectionUnavailableMessage
        case .syncNotConfigured:
            return String(localized: "Log in from Anki's Sync button once, then sync here.", bundle: .tabbi)
        case .anki, .invalidResponse, .transport:
            return Sentences.join([messageSentence ?? "", Self.addOnReminderWithCode])
        }
    }

    /// `quotedMessage` as a sentence, to lead a longer explanation.
    public var messageSentence: String? {
        guard let message else { return nil }
        if case .anki = self {
            return String(localized: "Anki said \u{201C}\(message)\u{201D}.", bundle: .tabbi,
                          comment: "Anki: the error text Anki sent, quoted as is (stays English), as the first sentence of an explanation.")
        }
        return quotedMessage.map { $0 + "." }
    }

    /// Why Anki's cards are closed for now, and that Tabbi waits it out.
    public static var collectionUnavailableMessage: String {
        String(localized: "Anki may be syncing, checking its database or showing a dialog. Tabbi reconnects when it's done.", bundle: .tabbi,
               comment: "Anki tab: Anki answers but has no cards open for a moment.")
    }

    /// The hint beside Open Anki while the collection is closed: the other
    /// reason it can be, which only the user can fix.
    public static var profileListHint: String {
        String(localized: "On the profile list? Open your profile.", bundle: .tabbi,
               comment: "Anki tab: hint beside the Open Anki button when Anki has no cards open. The profile list is Anki's Switch Profile window.")
    }
}
