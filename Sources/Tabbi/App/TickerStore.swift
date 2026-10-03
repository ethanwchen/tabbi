import Combine
import Foundation
import TabbiKitCore

/// Which closed-notch previews can show right now, for modules that only
/// refresh their data while someone can see it (Today keeps reloading the
/// calendar while the meeting preview can show).
@MainActor
final class ClosedNotchPreview: ObservableObject {
    /// The kinds the user allows while the notch is closed; empty while it
    /// is open or the preview is off.
    @Published fileprivate(set) var watchedKinds: Set<TickerKind> = []
}

extension SharedServices {
    /// The one `ClosedNotchPreview`, written by the `TickerStore`.
    var closedNotchPreview: ClosedNotchPreview { resolve { ClosedNotchPreview() } }
}

extension ModuleContext {
    /// Which closed-notch previews can show right now.
    var closedNotchPreview: ClosedNotchPreview { shared.closedNotchPreview }
}

/// Drives the live preview beside the closed notch.
///
/// Builds a `TickerSources` snapshot from the shared providers (events,
/// music, focus, open tasks, progress, module highlights, the pet and the
/// party), filters it by the user's notch preview settings, and runs
/// `TickerRotation` to pick the item on screen. It knows no module: whatever
/// the enabled modules provide is what it shows. The clock only runs while
/// the notch is closed, and then only wakes when the screen can change: the
/// next rotation turn, the next change `TickerSources.nextChange` predicts,
/// or every second while a running focus clock is showing.
@MainActor
final class TickerStore: ObservableObject {
    /// The item beside the closed notch; nil keeps the notch plain black.
    @Published private(set) var item: TickerItem?

    /// The latest module snapshot, before the user's settings filter it.
    private(set) var sources = TickerSources()
    /// The settings that decide which kinds may show.
    private var settings: AppSettings
    private let catalog: ModuleCatalog
    private let preview: ClosedNotchPreview
    private var rotation: TickerRotation
    /// False while the notch is open, where the preview isn't visible.
    private var isActive = true
    /// More than one item can take a turn, so the rotation has a deadline.
    private var rotates = false
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(settings store: SettingsStore, providers: ProviderHub, preview: ClosedNotchPreview) {
        settings = store.settings
        catalog = store.catalog
        self.preview = preview
        rotation = TickerRotation(interval: store.settings.notchPreview.interval.seconds)

        providers.$snapshot
            .map(TickerSources.init)
            .removeDuplicates()
            .sink { [weak self] sources in
                self?.sources = sources
                self?.refresh()
            }
            .store(in: &cancellables)

        // `$settings` emits before the new value is stored, so read it from
        // the emission rather than from `store.settings`.
        store.$settings
            .removeDuplicates { $0.notchPreview == $1.notchPreview && $0.modules == $1.modules }
            .sink { [weak self] settings in
                guard let self else { return }
                self.settings = settings
                self.rotation.interval = settings.notchPreview.interval.seconds
                self.refresh()
            }
            .store(in: &cancellables)
    }

    /// Pauses the clock while the notch is open and catches up on close.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        refresh()
    }

    private func refresh() {
        let watched = isActive ? Set(TickerKind.all(in: catalog).filter(settings.showsPreview)) : []
        if watched != preview.watchedKinds { preview.watchedKinds = watched }
        let now = Date()
        if isActive {
            let items = sources.items(at: now, enabled: settings.showsPreview)
            let next = rotation.update(items: items, at: now)
            rotates = items.count > 1 && next?.isPinned == false
            if next != item { item = next }
        }
        scheduleTimer(now: now)
    }

    private func scheduleTimer(now: Date) {
        timer?.invalidate()
        timer = nil
        guard isActive else { return }
        var wakes = [sources.nextChange(after: now, enabled: settings.showsPreview)]
        if rotates, let shownSince = rotation.shownSince {
            wakes.append(shownSince.addingTimeInterval(rotation.interval))
        }
        if case .focus(let focus) = item, focus.isRunning {
            wakes.append(now.addingTimeInterval(1))
        }
        guard let fireDate = wakes.compactMap({ $0 }).min() else { return }
        let timer = Timer(fire: max(fireDate, now), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = min(max(fireDate.timeIntervalSince(now), 0) / 10, 1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
