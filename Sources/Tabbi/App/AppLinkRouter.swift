import Foundation
import TabbiKit
import TabbiKitCore

/// Sends a `tabbi://` link to whoever handles it: an invite to Party, whose
/// confirmation fills the notch (it offers to turn Party on first), and the
/// widget's open link to the notch itself.
@MainActor
struct AppLinkRouter {
    let services: AppServices
    let notch: NotchViewModel

    /// Handles `url` and returns whether it was a link Tabbi knows.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = AppLink(url: url) else { return false }
        switch link {
        case .open:
            notch.open()
        case .invite(let invite):
            // An edition without Party ignores invites.
            guard let party = services.modules.module(PartyModule.self) else { return false }
            party.open(invite)
        }
        return true
    }
}
