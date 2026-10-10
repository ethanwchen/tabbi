import Combine
import SwiftUI
import TabbiKit
import TabbiKitCore

/// The recap's moment in the notch: the first time the user opens the
/// notch after a week's recap is ready, its card fills the open notch once
/// until they press Done. First-run onboarding comes first, so a recap
/// never interrupts setup and waits for the next open instead.
@MainActor
final class RecapMoment: ObservableObject {
    /// A recap on show, with its warm line worked out when it appeared.
    struct Shown: Equatable {
        let recap: WeeklyRecap
        let cheer: RecapCheer
    }

    /// The recap filling the notch now, nil when the tabs show.
    @Published private(set) var shown: Shown?

    let store: RecapStore
    private let isBlocked: () -> Bool
    private let notify: ((RecapNotice) -> Void)?
    /// The user's Weekly recap switch in Settings.
    private(set) var isEnabled = true
    private var isStarted = false
    private var isFollowingSwitch = false

    /// - Parameter isBlocked: true while something else owns the takeover
    ///   slot (onboarding), so the recap waits for a later open.
    /// - Parameter notify: posts the macOS notification for a ready recap;
    ///   nil where none can go out (demo, snapshot, a bare executable).
    init(store: RecapStore, isBlocked: @escaping () -> Bool = { false },
         notify: ((RecapNotice) -> Void)? = nil) {
        self.store = store
        self.isBlocked = isBlocked
        self.notify = notify
        store.onScheduledBuild = { [weak self] in self?.notifyIfDue() }
    }

    /// Says once that the newest recap is ready, unless the user already saw
    /// its card or turned recaps off.
    private func notifyIfDue() {
        guard isEnabled, !isFollowingSwitch, shown == nil, let notify, let recap = store.unnotified else { return }
        store.markNotified(recap.week)
        notify(RecapNotice(recap: recap, cheer: store.cheer(for: recap)))
    }

    /// The user opened the notch: builds what is ready (a Mac that slept
    /// through Sunday evening catches up here) and shows the newest unseen
    /// recap. It counts as seen once shown, so it never comes back after a
    /// relaunch, but it stays until Done even if the notch closes first.
    func notchOpened() {
        guard isEnabled, shown == nil, !isBlocked() else { return }
        store.refresh()
        guard let recap = store.unseen else { return }
        shown = Shown(recap: recap, cheer: store.cheer(for: recap))
        store.markSeen(recap.week)
    }

    /// Done: back to the tabs.
    func dismiss() { shown = nil }

    /// Follows the Settings switch. Off hides a card on show and stops the
    /// Sunday build; back on builds what is ready, which the next open shows.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled { shown = nil }
        guard isStarted else { return }
        guard enabled else { return store.stop() }
        // The user is in Settings right now: the next open shows the card,
        // with no notification about it.
        isFollowingSwitch = true
        store.start()
        isFollowingSwitch = false
    }

    func start() {
        isStarted = true
        if isEnabled { store.start() }
    }

    func stop() {
        isStarted = false
        store.stop()
    }
}

/// The notch's one takeover slot, shared by first-run onboarding and the
/// weekly recap. Onboarding wins while it runs.
enum AppTakeover {
    /// True while either one should fill the open notch.
    @MainActor
    static func isActive(onboarding: OnboardingStore, recaps: RecapMoment) -> AnyPublisher<Bool, Never> {
        onboarding.$flow.map { $0 != nil }
            .combineLatest(recaps.$shown.map { $0 != nil })
            .map { $0 || $1 }
            .eraseToAnyPublisher()
    }

    /// Onboarding's takeover while it runs, else the recap on show.
    @MainActor
    static func takeover(onboarding: NotchTakeover, store: OnboardingStore, recaps: RecapMoment,
                         providers: ProviderHub) -> NotchTakeover {
        func pick(_ part: @escaping (NotchTakeover) -> AnyView) -> () -> AnyView {
            {
                AnyView(TakeoverSlot(onboarding: store, recaps: recaps) { shown in
                    part(shown.map {
                        RecapViews.takeover(recap: $0.recap, cheer: $0.cheer, providers: providers,
                                            done: { recaps.dismiss() })
                    } ?? onboarding)
                })
            }
        }
        return NotchTakeover(leading: pick { $0.leading() }, trailing: pick { $0.trailing() },
                             body: pick { $0.body() })
    }
}

/// Follows both owners of the takeover slot, so the notch redraws when
/// either starts or ends. Hands `content` the recap only while onboarding
/// isn't running.
private struct TakeoverSlot: View {
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var recaps: RecapMoment
    let content: (RecapMoment.Shown?) -> AnyView

    var body: some View {
        content(onboarding.flow == nil ? recaps.shown : nil)
    }
}
