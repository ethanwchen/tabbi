import Foundation

extension AnkiConnectionState {
    /// The Connections row for this state: the Anki tab's setup steps in
    /// plain words, each with the one button that moves it forward.
    public var connectionStatus: ConnectionStatus {
        switch self {
        case .checking:
            return ConnectionStatus(light: .checking, headline: String(localized: "Looking for Anki", bundle: .tabbi),
                                    detail: String(localized: "This takes a second.", bundle: .tabbi))
        case .notInstalled:
            return ConnectionStatus(light: .notInstalled, headline: String(localized: "Anki isn't on this Mac", bundle: .tabbi),
                                    detail: String(localized: "It's a free flashcard app. Get it, then come back here.", bundle: .tabbi),
                                    action: .download(.anki))
        case .notRunning:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Anki is closed", bundle: .tabbi),
                                    detail: String(localized: "Open Anki so Tabbi can see your cards.", bundle: .tabbi),
                                    action: .openApp(.anki))
        case .starting:
            return ConnectionStatus(light: .checking, headline: String(localized: "Anki is starting", bundle: .tabbi),
                                    detail: String(localized: "This takes a few seconds.", bundle: .tabbi))
        case .addOnMissing:
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "One add-on to go", bundle: .tabbi),
                                    detail: String(localized: "Anki needs a free add-on called AnkiConnect so Tabbi can count your cards.", bundle: .tabbi),
                                    action: .showGuide(.ankiAddOn))
        case .needsPermission(.apiKeyRequired):
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Anki has a password on", bundle: .tabbi),
                                    detail: String(localized: "AnkiConnect is set to ask for a key. Turning that off takes a minute.", bundle: .tabbi),
                                    action: .showGuide(.ankiAccess))
        case .needsPermission:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Anki said no to Tabbi", bundle: .tabbi),
                                    detail: String(localized: "When Anki asked whether to let Tabbi in, the answer was no.", bundle: .tabbi),
                                    action: .showGuide(.ankiAccess))
        case .addOnOutdated:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Update AnkiConnect", bundle: .tabbi),
                                    detail: String(localized: "Your copy of the AnkiConnect add-on is too old for Tabbi.", bundle: .tabbi),
                                    action: .showGuide(.ankiAddOnUpdate))
        case .ready:
            return ConnectionStatus(light: .connected, headline: String(localized: "Anki is connected", bundle: .tabbi),
                                    detail: String(localized: "Your due cards show up in Tabbi.", bundle: .tabbi))
        case .problem(.collectionUnavailable):
            // AnkiConnect can't tell the profile list from a profile whose
            // collection is closed for a moment, so say both, likeliest first.
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Waiting for Anki", bundle: .tabbi),
                                    detail: String(localized: "Anki may be syncing or on its profile list. Tabbi reconnects by itself.", bundle: .tabbi,
                                                   comment: "Settings > Connections: the Anki row while Anki has no cards open."),
                                    action: .openApp(.anki))
        case .problem(.timeout):
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Anki is busy", bundle: .tabbi),
                                    detail: String(localized: "Close any open window inside Anki, then check again.", bundle: .tabbi),
                                    action: .checkAgain)
        case .problem(let error) where error.isUnexplained:
            // The row has room for the likeliest fix; Anki's own words are
            // in the troubleshooter's checks and the copied details.
            return ConnectionStatus(light: .needsStep, headline: error.title, detail: AnkiConnectError.addOnReminderWithCode,
                                    action: .checkAgain)
        case .problem:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Anki didn't answer", bundle: .tabbi),
                                    detail: String(localized: "This is usually short. Check again in a moment.", bundle: .tabbi),
                                    action: .checkAgain)
        }
    }
}
