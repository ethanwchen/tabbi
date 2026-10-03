import Combine
import Foundation
import NotchKitCore

/// Drives the live preview beside the closed notch.
///
/// Collects a `TickerSources` snapshot from the shared providers (events,
/// focus, open tasks, study progress) and the Now Playing and Claude Usage stores, filters it by
/// the user's notch preview settings, and runs `TickerRotation` to pick the
/// item on screen. The clock only runs while the notch is closed, and then
/// only wakes when the screen can change: the next rotation turn, the next
/// change `TickerSources.nextChange` predicts, or every second while a
/// running focus clock is showing.
/// While the meeting item is on and the notch is closed it also keeps
/// `UpNextStore` reloading, so events added since Today was last open show up.
@MainActor
final class TickerStore: ObservableObject {
    /// The item beside the closed notch; nil keeps the notch plain black.
    @Published private(set) var item: TickerItem?

    /// The latest module snapshot, before the user's settings filter it.
    private(set) var sources = TickerSources()
    /// Kinds allowed by the preview settings and the enabled modules.
    private var kinds: Set<TickerKind>
    private let upNext: UpNextStore?
    private var rotation: TickerRotation
    /// False while the notch is open, where the preview isn't visible.
    private var isActive = true
    /// More than one item can take a turn, so the rotation has a deadline.
    private var rotates = false
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// The stores are nil when this build lacks their module.
    init(settings: SettingsStore, providers: ProviderHub, spotify: SpotifyController?,
         claudeUsage: ClaudeUsageStore?, upNext: UpNextStore?) {
        kinds = settings.settings.previewKinds
        self.upNext = upNext
        rotation = TickerRotation(interval: settings.settings.notchPreview.interval.seconds)

        providers.$snapshot
            .combineLatest(spotify?.$showsCompactActivity.eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher(),
                           claudeUsage?.$limits.map { $0?.snapshot }.eraseToAnyPublisher()
                               ?? Just(nil).eraseToAnyPublisher())
            .map { shared, isMusicPlaying, usage in
                TickerSources(events: shared.events, isMusicPlaying: isMusicPlaying, focus: shared.focus,
                              focusSource: shared.focusSource, tasksRemaining: shared.openTasks.count,
                              progress: shared.progress, usage: usage,
                              pet: shared.pet, party: shared.party)
            }
            .removeDuplicates()
            .sink { [weak self] sources in
                self?.sources = sources
                self?.refresh()
            }
            .store(in: &cancellables)

        // `$settings` emits before the new value is stored, so read it from
        // the emission rather than from `settings.settings`.
        settings.$settings
            .map { ($0.previewKinds, $0.notchPreview.interval) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] kinds, interval in
                guard let self else { return }
                self.kinds = kinds
                self.rotation.interval = interval.seconds
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
        upNext?.setPreviewWatching(isActive && kinds.contains(.meeting))
        let now = Date()
        if isActive {
            let items = sources.items(at: now, enabled: kinds)
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
        var wakes = [sources.nextChange(after: now, enabled: kinds)]
        if rotates, let shownSince = rotation.shownSince {
            wakes.append(shownSince.addingTimeInterval(rotation.interval))
        }
        if case .focus(_, _, isRunning: true, _) = item {
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
