import Combine
import Foundation
import TabbiKitCore
import TabbiKit

/// The break buddy: at the start of a study break the pet models one short,
/// healthy move (a stretch, a sip of water, resting the eyes, a slow breath,
/// standing up) and the user copies it if they like.
///
/// Not a tab: one shared service (`context.breakBuddy`) that follows the
/// shared focus clock, so it works the same for Study's and Focus' breaks.
/// On a fresh switch into a break with a countdown (never a break already
/// under way at launch) the pure `BreakBuddyPlanner` picks the move, and
/// the moment shows in the closed notch (the Closet passes it on through
/// `PetPresence.breakMoment`) and as a card in the open Study or Focus tab.
///
/// Cozy and guilt-free: Done logs the move and the pet hops for joy, Skip
/// just ends it, and nothing counts against the user. Done moves and the
/// water tally go to the activity log as kinds of their own
/// (`WaterTally`), which no points, streak or chart reads. It needs no
/// permissions. Preferences and the planner's history are saved in
/// `UserDefaults` (`BreakBuddyPreferencesStorage`), except in demo and
/// snapshot runs, which save nothing; a demo run starts with a sample
/// moment showing beside the closed notch.
@MainActor
final class BreakBuddyController: ObservableObject {
    @Published private(set) var preferences: BreakBuddyPreferences
    /// The move the pet is modeling now, or nil.
    @Published private(set) var moment: BreakMoment?
    /// True after Done while the pet does its happy hop, just before the
    /// moment goes.
    @Published private(set) var isFinishing = false
    /// Glasses of water logged today.
    @Published private(set) var waterToday = 0
    /// The pet the open card draws, made for each moment so it starts
    /// straight in the move.
    @Published private(set) var cardPet: PetPlayer?

    /// A break that began longer ago than this when it is first seen is
    /// not fresh (a relaunch mid-break, a clock restored from disk).
    static let freshWindow: TimeInterval = 10

    private let storage: BreakBuddyPreferencesStorage?
    private let activityLog: ActivityLog
    private let runMode: RunMode
    private let props: BreakProps
    private let calendar: Calendar
    private let clock: () -> Date
    private var profile: PetProfile
    /// The last shared focus clock seen; nil before the first.
    private var lastFocus: ProvidedFocus??
    private var endTask: Task<Void, Never>?
    /// The moment showing stays when the clock leaves the break: the demo's
    /// sample and snapshot shots, which no real break started.
    private var outlivesBreak = false
    /// The moment showing is the demo's launch sample, which the open tabs
    /// leave out (`cardMoment`).
    @Published private var isDemoSample = false
    private var cancellables: Set<AnyCancellable> = []

    init(runMode: RunMode, activityLog: ActivityLog, profile: PetProfile, defaults: UserDefaults = .standard,
         props: BreakProps = .standard, calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.runMode = runMode
        self.activityLog = activityLog
        self.profile = profile
        self.props = props
        self.calendar = calendar
        self.clock = clock
        storage = runMode.isEphemeral ? nil : BreakBuddyPreferencesStorage(defaults: defaults)
        preferences = storage?.load() ?? BreakBuddyPreferences()
        recountWater()
        activityLog.recorded
            .filter { $0.kind == WaterTally.waterKind }
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.recountWater() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.recountWater() } }
            .store(in: &cancellables)
        // A demo shows what a break looks like right away, beside the closed
        // notch only, so the demo's timer stays usable in the open tabs;
        // snapshots set their own moment per shot.
        if runMode.isDemo, !runMode.isSnapshot, preferences.isOn {
            start(.sample(at: clock()), outlivesBreak: true)
            isDemoSample = true
        }
    }

    /// Follows the shared focus clock (`ProviderSnapshot.focus`).
    func follow(focus: AnyPublisher<ProvidedFocus?, Never>) {
        focus.removeDuplicates()
            .sink { [weak self] focus in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.observe(focus, at: self.clock())
                }
            }
            .store(in: &cancellables)
    }

    /// Follows the pet's look, so the card's pet matches the Closet.
    func follow(profiles: AnyPublisher<PetProfile, Never>) {
        profiles.sink { [weak self] profile in
            MainActor.assumeIsolated {
                self?.profile = profile
                self?.cardPet?.update(profile: profile)
            }
        }
        .store(in: &cancellables)
    }

    /// The moment for the open Study or Focus tab's card: `moment`, except
    /// the demo's launch sample, which only the closed notch shows.
    var cardMoment: BreakMoment? { isDemoSample ? nil : moment }

    /// The pet's name for the card's lines, or nil while it goes by its
    /// breed's name.
    var petName: String? { BreakMove.buddyName(for: profile) }

    /// Today's glasses for the card, or nil when the water tally is off.
    var shownWater: Int? { preferences.tracksWater ? waterToday : nil }

    /// Records the shared focus clock at `now`: ends a moment whose break is
    /// over (the next focus started, or the clock stopped), and plans one
    /// for a break that just began.
    func observe(_ focus: ProvidedFocus?, at now: Date) {
        let previous = lastFocus
        lastFocus = .some(focus)
        if let moment {
            let breakGoesOn = focus.map { $0.phase == .rest && $0.isActive } ?? false
            if (!breakGoesOn && !outlivesBreak) || moment.endsAt <= now { end() }
        }
        // Snapshots show fixed moments; the first clock seen is never a
        // fresh break, since it may have been running before launch.
        guard !runMode.isSnapshot, case .some(let before) = previous, let focus,
              let rest = BreakBuddyPlanner.Break(focus) else { return }
        // Resuming a paused break is not a new one.
        let wasOnBreak = before.map { $0.phase == .rest && $0.isActive } ?? false
        guard !wasOnBreak, abs(now.timeIntervalSince(rest.startedAt)) <= Self.freshWindow,
              let plan = BreakBuddyPlanner.plan(for: rest, preferences: preferences, at: now) else { return }
        update(plan.preferences)
        start(plan.moment)
    }

    // MARK: The card's buttons

    /// The user did the move: it is logged, the pet hops for joy, and the
    /// moment goes once the hop has played.
    func done() {
        guard let moment, !isFinishing else { return }
        let now = clock()
        if !runMode.isSnapshot { activityLog.record(WaterTally.move(moment.move, at: now)) }
        isFinishing = true
        cardPet?.send(.hop, at: now)
        let hop = cardPet?.clips[.hop].duration ?? 0
        schedule(end: now.addingTimeInterval(hop))
    }

    /// The user would rather not: the moment just ends. Nothing is logged.
    func skip() {
        guard moment != nil else { return }
        end()
    }

    /// Logs a glass of water.
    func addWater() {
        guard !runMode.isSnapshot else { return }
        activityLog.record(WaterTally.water(at: clock()))
    }

    // MARK: Settings

    func setOn(_ isOn: Bool) {
        var next = preferences
        next.isOn = isOn
        update(next)
        if !isOn { end() }
    }

    func setMove(_ move: BreakMove, enabled: Bool) {
        var next = preferences
        next.setEnabled(move, enabled)
        update(next)
    }

    func setTracksWater(_ tracksWater: Bool) {
        var next = preferences
        next.tracksWater = tracksWater
        update(next)
    }

    /// Snapshot runs only: shows `moment` (or none) without planning or saving.
    func showForSnapshot(_ moment: BreakMoment?) {
        guard runMode.isSnapshot else { return }
        if let moment { start(moment, outlivesBreak: true) } else { end() }
    }

    // MARK: Private

    private func update(_ next: BreakBuddyPreferences) {
        guard next != preferences else { return }
        preferences = next
        storage?.save(next)
    }

    private func start(_ moment: BreakMoment, outlivesBreak: Bool = false) {
        let now = clock()
        self.moment = moment
        self.outlivesBreak = outlivesBreak
        isDemoSample = false
        isFinishing = false
        // Started with the moment, so the card's pet moves in step with the
        // closed notch's.
        cardPet = PetPlayer(profile: profile, activity: .guiding(props.animation(for: moment.move)),
                            at: min(moment.startedAt, now))
        schedule(end: moment.endsAt)
    }

    private func end() {
        endTask?.cancel()
        endTask = nil
        outlivesBreak = false
        isDemoSample = false
        guard moment != nil || cardPet != nil else { return }
        moment = nil
        isFinishing = false
        cardPet = nil
    }

    /// Ends the moment at `date`, unless another one starts before then.
    private func schedule(end date: Date) {
        endTask?.cancel()
        let delay = max(date.timeIntervalSince(clock()), 0)
        let moment = moment
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.moment == moment else { return }
            self.end()
        }
    }

    private func recountWater() {
        let today = PlannerDayKey(date: clock(), calendar: calendar)
        let count = WaterTally.glasses(in: activityLog.records(on: today), on: today, calendar: calendar)
        if count != waterToday { waterToday = count }
    }
}

extension ModuleContext {
    /// The one break buddy, beside the pet that models the moves. It
    /// follows the shared focus clock, so Study's and Focus' breaks both get
    /// a moment; the Closet passes the moment to the closed notch, and the
    /// Study and Focus tabs show its card.
    var breakBuddy: BreakBuddyController {
        shared.resolve {
            let pet = studyPet
            let buddy = BreakBuddyController(runMode: runMode, activityLog: activityLog, profile: pet.profile)
            buddy.follow(focus: providers.$snapshot.map(\.focus).eraseToAnyPublisher())
            buddy.follow(profiles: pet.profiles)
            return buddy
        }
    }
}
