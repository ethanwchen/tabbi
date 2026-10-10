import Foundation
import TabbiKitCore

/// Where the account reads and saves the age check's answer
/// (`PartyAgeCheck`). It is Party's own `PartySettings.ageEligibleFrom`, so
/// one answer covers Party and Sign in with Apple, also in the App Store
/// build, which has no Party tab. Only the day the user is surely 13 is
/// kept, on this Mac.
struct AccountAgeAnswer {
    let load: () -> Date?
    let save: (Date) -> Void

    /// Party's settings in `UserDefaults`, as the app uses them.
    static func partySettings(_ repository: PartySettingsRepository = PartySettingsRepository()) -> AccountAgeAnswer {
        AccountAgeAnswer(load: { repository.load().ageEligibleFrom },
                         save: { eligibleFrom in
                             var settings = repository.load()
                             settings.ageEligibleFrom = eligibleFrom
                             repository.save(settings)
                         })
    }

    /// Kept in memory only: snapshot runs and tests.
    static func inMemory(_ eligibleFrom: Date? = nil) -> AccountAgeAnswer {
        final class Box { var value: Date? }
        let box = Box()
        box.value = eligibleFrom
        return AccountAgeAnswer(load: { box.value }, save: { box.value = $0 })
    }
}
