import Combine
import SwiftUI
import TabbiKit
import TabbiKitCore

/// The recap's moment in the notch: the first time the user opens the
/// notch after a week's recap is ready, its card fills the open notch once,
/// until they press Done or close the notch. First-run onboarding and a Party invite's
/// confirmation come first (`AppTakeover`), so a recap never interrupts
/// them and waits for the next open instead.
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
    private var reopening: AnyCancellable?

    /// - Parameter isBlocked: true while something else owns the takeover
    ///   slot (onboarding or a Party invite), so the recap waits for a
    ///   later open.
    /// - Parameter notify: posts the macOS notification for a ready recap;
    ///   nil where none can go out (demo, snapshot, a bare executable).
    init(store: RecapStore, isBlocked: @escaping () -> Bool = { false },
         notify: ((RecapNotice) -> Void)? = nil) {
        self.store = store
        self.isBlocked = isBlocked
        self.notify = notify
        store.onScheduledBuild = { [weak self] in self?.notifyIfDue() }
        reopening = store.reopened.sink { [weak self] in self?.show($0) }
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
    /// recap. It counts as seen (and is saved) the moment it shows, so a
    /// later open, a relaunch or a quit never brings it back.
    func notchOpened() {
        guard isEnabled, shown == nil, !isBlocked() else { return }
        store.refresh()
        guard let recap = store.unseen else { return }
        shown = Shown(recap: recap, cheer: store.cheer(for: recap))
        store.markSeen(recap.week)
    }

    /// Shows a past recap picked from the list. The notch is already open,
    /// so the takeover simply replaces the tabs until Done.
    private func show(_ recap: WeeklyRecap) {
        guard isEnabled, !isBlocked() else { return }
        shown = Shown(recap: recap, cheer: store.cheer(for: recap))
    }

    /// Done: back to the tabs.
    func dismiss() { shown = nil }

    /// The user closed the notch: a card on show is done with, so the next
    /// open shows the tabs. Past weeks stay in the recap list.
    func notchClosed() { dismiss() }

    /// Follows the Settings switch. Off hides a card on show and stops the
    /// Sunday build; back on builds what is ready, which the next open shows.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        store.isEnabled = enabled
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
