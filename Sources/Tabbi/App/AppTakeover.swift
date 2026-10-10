import Combine
import SwiftUI
import TabbiKit
import TabbiKitCore

/// The notch's one takeover slot, which fills the whole open notch for a
/// while. Three things share it, in this order: first-run onboarding, a
/// Party invite link's confirmation, and the weekly recap card. Whoever
/// ranks lower waits until the higher one is done.
enum AppTakeover {
    /// Who fills the slot right now.
    enum Owner: Equatable {
        case onboarding
        case invite
        case recap(RecapMoment.Shown)
    }

    /// A Party invite link's confirmation and whether one is showing. Nil
    /// where the edition has no Party module.
    struct Invite {
        let takeover: NotchTakeover
        let showing: AnyPublisher<Bool, Never>
    }

    /// Onboarding first, then a pending invite, then the recap on show; nil
    /// when none is, so the tabs show.
    static func owner(onboarding: Bool, invite: Bool, recap: RecapMoment.Shown?) -> Owner? {
        if onboarding { return .onboarding }
        if invite { return .invite }
        return recap.map(Owner.recap)
    }

    /// True while any of the three should fill the open notch.
    @MainActor
    static func isActive(onboarding: OnboardingStore, invite: AnyPublisher<Bool, Never>?,
                         recaps: RecapMoment) -> AnyPublisher<Bool, Never> {
        onboarding.$flow.map { $0 != nil }
            .combineLatest(invite ?? Just(false).eraseToAnyPublisher(), recaps.$shown.map { $0 != nil })
            .map { $0 || $1 || $2 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// The takeover of whoever owns the slot (see `owner`).
    @MainActor
    static func takeover(onboarding: NotchTakeover, store: OnboardingStore, invite: Invite?,
                         recaps: RecapMoment, providers: ProviderHub) -> NotchTakeover {
        let inviteShowing = TakeoverFlag(invite?.showing)
        func pick(_ part: @escaping (NotchTakeover) -> AnyView) -> () -> AnyView {
            {
                AnyView(TakeoverSlot(onboarding: store, invite: inviteShowing, recaps: recaps) { owner in
                    switch owner {
                    case .recap(let shown):
                        part(RecapViews.takeover(recap: shown.recap, cheer: shown.cheer, providers: providers,
                                                 done: { recaps.dismiss() }))
                    case .invite:
                        part(invite?.takeover ?? onboarding)
                    case .onboarding, nil:
                        part(onboarding)
                    }
                })
            }
        }
        return NotchTakeover(leading: pick { $0.leading() }, trailing: pick { $0.trailing() },
                             body: pick { $0.body() })
    }
}

/// Holds the latest value of a Bool publisher, so a view redraws when it
/// changes.
@MainActor
private final class TakeoverFlag: ObservableObject {
    @Published private(set) var isOn = false
    private var subscription: AnyCancellable?

    init(_ publisher: AnyPublisher<Bool, Never>?) {
        subscription = publisher?.removeDuplicates().sink { [weak self] in self?.isOn = $0 }
    }
}

/// Follows every owner of the takeover slot, so the notch redraws when any
/// of them starts or ends, and hands `content` the one that wins.
private struct TakeoverSlot: View {
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var invite: TakeoverFlag
    @ObservedObject var recaps: RecapMoment
    let content: (AppTakeover.Owner?) -> AnyView

    var body: some View {
        content(AppTakeover.owner(onboarding: onboarding.flow != nil, invite: invite.isOn, recap: recaps.shown))
    }
}
