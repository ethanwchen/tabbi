import Foundation
import TabbiKitCore

extension ModuleContext {
    /// The one optional Sign in with Apple account, which syncs the study
    /// pet (`studyPet`) across the user's Macs and is the Party identity.
    /// Party follows `identityChanged`; `AppServices` starts it at launch
    /// and flushes it on quit, and Settings > General shows it.
    var accountSync: SyncStore {
        shared.resolve {
            let snapshot = runMode.isSnapshot
            let credentials: any PartyCredentialStore = runMode.isEphemeral
                ? InMemoryPartyCredentialStore()
                : KeychainPartyCredentialStore(service: edition.bundleIdentifier + ".party")
            return SyncStore(storage: storage, runMode: runMode, pet: studyPet,
                             signInMethod: snapshot ? .web : AppleSignInMethod.current,
                             server: { snapshot ? nil : PartySettingsRepository().load().serverURL },
                             credentials: credentials,
                             ageAnswer: snapshot ? .inMemory() : .partySettings())
        }
    }
}
