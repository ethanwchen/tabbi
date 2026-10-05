import Foundation

extension AnkiConnectionState {
    /// The Connections row for this state: the Anki tab's setup steps in
    /// plain words, each with the one button that moves it forward.
    public var connectionStatus: ConnectionStatus {
        switch self {
        case .checking:
            return ConnectionStatus(light: .checking, headline: "Looking for Anki",
                                    detail: "This takes a second.")
        case .notInstalled:
            return ConnectionStatus(light: .notInstalled, headline: "Anki isn't on this Mac",
                                    detail: "Anki is a free flashcard app. Get it, then come back here.",
                                    action: .download(.anki))
        case .notRunning:
            return ConnectionStatus(light: .needsStep, headline: "Anki is closed",
                                    detail: "Open Anki so Tabbi can see your cards.",
                                    action: .openApp(.anki))
        case .starting:
            return ConnectionStatus(light: .checking, headline: "Anki is starting",
                                    detail: "This takes a few seconds.")
        case .addOnMissing:
            return ConnectionStatus(light: .notSetUp, headline: "One add-on to go",
                                    detail: "Anki needs a free add-on called AnkiConnect so Tabbi can count your cards.",
                                    action: .showGuide(.ankiAddOn))
        case .needsPermission(.apiKeyRequired):
            return ConnectionStatus(light: .needsStep, headline: "Anki has a password on",
                                    detail: "AnkiConnect is set to ask for a key. Turning that off takes a minute.",
                                    action: .showGuide(.ankiAccess))
        case .needsPermission:
            return ConnectionStatus(light: .needsStep, headline: "Anki said no to Tabbi",
                                    detail: "Anki asked whether to let Tabbi in, and it was turned down.",
                                    action: .showGuide(.ankiAccess))
        case .addOnOutdated:
            return ConnectionStatus(light: .needsStep, headline: "Update AnkiConnect",
                                    detail: "Your copy of the AnkiConnect add-on is too old for Tabbi.",
                                    action: .showGuide(.ankiAddOnUpdate))
        case .ready:
            return ConnectionStatus(light: .connected, headline: "Anki is connected",
                                    detail: "Your due cards show up in Tabbi.")
        case .problem(.collectionUnavailable):
            return ConnectionStatus(light: .needsStep, headline: "Pick your profile in Anki",
                                    detail: "Anki is waiting for you to choose whose cards to open.",
                                    action: .openApp(.anki))
        case .problem(.timeout):
            return ConnectionStatus(light: .needsStep, headline: "Anki is busy",
                                    detail: "Close any open window inside Anki, then check again.",
                                    action: .checkAgain)
        case .problem:
            return ConnectionStatus(light: .needsStep, headline: "Anki didn't answer",
                                    detail: "This is usually short. Check again in a moment.",
                                    action: .checkAgain)
        }
    }
}
