import Foundation
import TabbiKitCore

/// Where the account reads what Party's age check (`PartyAgeCheck`)
/// learned: Party's own `PartySettings.ageEligibleFrom`. Signing in never
/// asks for a birthday, so the account only reads it; an answer under 13
/// given in Party keeps signing in off (and signs out an account) until the
/// user turns 13. The App Store build has no Party tab, so it is always
/// unanswered there. Only the day the user is surely 13 is kept, on this
/// Mac.
struct AccountAgeAnswer {
    let load: () -> Date?

    /// Party's settings in `UserDefaults`, as the app uses them.
    static func partySettings(_ repository: PartySettingsRepository = PartySettingsRepository()) -> AccountAgeAnswer {
        AccountAgeAnswer(load: { repository.load().ageEligibleFrom })
    }

    /// A fixed answer, or none: snapshot runs and tests.
    static func fixed(_ eligibleFrom: Date? = nil) -> AccountAgeAnswer {
        AccountAgeAnswer(load: { eligibleFrom })
    }
}
