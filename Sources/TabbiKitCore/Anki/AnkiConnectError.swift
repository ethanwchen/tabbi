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
    /// Anki is on the profile picker, so no collection is open.
    case collectionUnavailable
    /// `sync` was asked for but the user has not signed in to AnkiWeb.
    case syncNotConfigured
    /// Any other error string AnkiConnect returned.
    case anki(String)
    /// The reply was not the JSON we expected.
    case invalidResponse(String)
    /// Some other network failure.
    case transport(String)

    /// Maps an AnkiConnect `error` string to a typed case.
    public static func fromAnkiMessage(_ message: String, action: String) -> AnkiConnectError {
        let lower = message.lowercased()
        if lower.contains("api key") { return .apiKeyRequired }
        if lower.contains("unsupported action") { return .unsupportedAction(action) }
        if lower.contains("collection") && (lower.contains("not available") || lower.contains("not open") || lower.contains("is none")) {
            return .collectionUnavailable
        }
        if lower.contains("auth not configured") { return .syncNotConfigured }
        return .anki(message)
    }

    /// Short headline for an empty or error state.
    public var title: String {
        switch self {
        case .ankiNotRunning: return "Anki is closed"
        case .addOnMissing: return "AnkiConnect isn't answering"
        case .timeout: return "Anki is busy"
        case .permissionDenied: return "Anki said no"
        case .apiKeyRequired: return "AnkiConnect needs your API key"
        case .addOnOutdated: return "AnkiConnect is out of date"
        case .unsupportedAction: return "AnkiConnect is out of date"
        case .collectionUnavailable: return "Pick a profile in Anki"
        case .syncNotConfigured: return "Sign in to AnkiWeb to sync"
        case .anki: return "Anki reported a problem"
        case .invalidResponse: return "Unexpected reply from Anki"
        case .transport: return "Couldn't reach Anki"
        }
    }

    /// One plain sentence telling the user what to do next.
    public var suggestion: String {
        switch self {
        case .ankiNotRunning:
            return "Open Anki to see your due cards."
        case .addOnMissing:
            return "Install AnkiConnect (code 2055492159) from Tools › Add-ons, then restart Anki."
        case .timeout:
            return "Close any open Anki dialog. If it keeps happening, turn off App Nap for Anki."
        case .permissionDenied:
            return "Allow Tabbi in AnkiConnect's settings, then try again."
        case .apiKeyRequired:
            return "Enter the key from AnkiConnect's config in Settings."
        case .addOnOutdated, .unsupportedAction:
            return "Update AnkiConnect from Tools › Add-ons › Check for Updates."
        case .collectionUnavailable:
            return "Open your profile in Anki, then come back."
        case .syncNotConfigured:
            return "Log in from Anki's Sync button once, then sync here."
        case .anki, .invalidResponse, .transport:
            return "Try again in a moment."
        }
    }
}
