import Combine
import Foundation
import NotchDeckCore

/// Drives the live preview beside the closed notch.
///
/// Collects a `TickerSources` snapshot from the module stores, filters it by
/// the user's notch preview settings, and runs `TickerRotation` to pick the
/// item on screen. The clock only ticks while the notch is closed: once a
/// second while an item shows (countdowns and the rotation need it), twice a
/// minute while only a far-off meeting could appear, and not at all otherwise.
@MainActor
final class TickerStore: ObservableObject {
    /// The item beside the closed notch; nil keeps the notch plain black.
    @Published private(set) var item: TickerItem?

    /// The latest module snapshot, before the user's settings filter it.
    private(set) var sources = TickerSources()
    private var preview: NotchPreviewSettings
    private var rotation: TickerRotation
    /// False while the notch is open, where the preview isn't visible.
    private var isActive = true
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var cancellables: Set<AnyCancellable> = []

    /// While nothing shows, how often to check whether a meeting has come
    /// within `TickerSources.meetingHorizon`.
    private static let idleMeetingCheck: TimeInterval = 30

    init(settings: SettingsStore, spotify: SpotifyController, planner: PlannerStore, claudeUsage: ClaudeUsageStore) {
        preview = settings.settings.notchPreview
        rotation = TickerRotation(interval: preview.interval.seconds)

        let tasksRemaining = planner.$day.map { $0.items.count - $0.doneCount }
        planner.upNext.$events
            .combineLatest(spotify.$showsCompactActivity, planner.focus.$timer, tasksRemaining)
            .combineLatest(claudeUsage.$limits.map { $0?.snapshot })
            .map { modules, usage in
                TickerSources(events: modules.0, isMusicPlaying: modules.1, focus: modules.2,
                              tasksRemaining: modules.3, usage: usage)
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
            .map(\.notchPreview)
            .removeDuplicates()
            .sink { [weak self] preview in
                guard let self else { return }
                self.preview = preview
                self.rotation.interval = preview.interval.seconds
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
        if isActive {
            let now = Date()
            let next = rotation.update(items: sources.items(at: now, enabled: preview.enabledKinds), at: now)
            if next != item { item = next }
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        let wanted: TimeInterval? = if !isActive {
            nil
        } else if item != nil {
            1
        } else if preview.enabledKinds.contains(.meeting), !sources.events.isEmpty {
            Self.idleMeetingCheck
        } else {
            nil
        }
        guard wanted != timerInterval else { return }
        timer?.invalidate()
        timer = nil
        timerInterval = wanted
        guard let wanted else { return }
        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = wanted / 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
