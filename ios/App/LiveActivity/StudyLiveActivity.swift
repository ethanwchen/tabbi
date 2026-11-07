import ActivityKit
import Foundation
import TabbiKitCore

/// Keeps one Live Activity in step with the study session.
///
/// It starts when a phase starts (always from the foreground, as ActivityKit
/// requires), updates when the session changes (pause, resume, the next
/// phase), and ends when the session goes idle. A running countdown needs no
/// updates: the extension draws it from dates. While the app is suspended,
/// the activity's `staleDate` at the phase end lets the extension show that
/// the phase is done until the app is opened again and moves it on.
///
/// `Activity` is not `Sendable`, so the main actor keeps only its id, and
/// the async calls look it up again off the main actor.
@MainActor
final class StudyLiveActivity {
    private typealias Content = ActivityContent<StudyActivityAttributes.ContentState>

    private var activityID: String?
    private var shown: StudyActivityAttributes.ContentState?

    init() {
        // Adopt the activity a previous launch started, ending any extras.
        let running = Activity<StudyActivityAttributes>.activities.filter { $0.activityState != .ended }.map(\.id)
        activityID = running.first
        for extra in running.dropFirst() {
            Task { await Self.end(id: extra) }
        }
    }

    /// Whether the activity with `id` can still be updated.
    private static func isLive(_ id: String) -> Bool {
        Activity<StudyActivityAttributes>.activities.contains {
            $0.id == id && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    private nonisolated static func update(id: String, with content: Content) async {
        for activity in Activity<StudyActivityAttributes>.activities where activity.id == id {
            await activity.update(content)
        }
    }

    private nonisolated static func end(id: String, final content: Content? = nil,
                                        policy: ActivityUIDismissalPolicy = .immediate) async {
        for activity in Activity<StudyActivityAttributes>.activities where activity.id == id {
            await activity.end(content, dismissalPolicy: policy)
        }
    }

    /// How long a "done" activity stays on the Lock Screen when the phase
    /// ran out while the app was away (the HIG suggests 15 to 30 minutes).
    static let doneLinger: TimeInterval = 20 * 60

    /// Shows `session` at `now` with `pet`, starting, updating or ending
    /// the activity as needed. `finishedAway` says the session just went
    /// idle because its phase ran out while the app was not on screen: the
    /// activity then ends on its done line and stays a while, so someone who
    /// glances at the Lock Screen still learns the block is done.
    func sync(_ session: StudySession, pet: PetProfile, at now: Date, finishedAway: Bool = false) {
        guard let state = StudyActivityAttributes.ContentState(session, at: now) else {
            if finishedAway, let activityID, var last = shown {
                last.isDone = true
                self.activityID = nil
                shown = nil
                let content = Content(state: last, staleDate: nil)
                let policy = ActivityUIDismissalPolicy.after(now.addingTimeInterval(Self.doneLinger))
                Task { await Self.end(id: activityID, final: content, policy: policy) }
            } else {
                end()
            }
            return
        }
        let content = Content(state: state, staleDate: state.endsAt)
        if let activityID, Self.isLive(activityID) {
            guard state != shown else { return }
            shown = state
            Task { await Self.update(id: activityID, with: content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activityID = try Activity.request(attributes: StudyActivityAttributes(pet: pet), content: content).id
            shown = state
        } catch {
            // Too many activities, or Live Activities are off: the app and
            // the notifications still work without it.
            activityID = nil
            shown = nil
        }
    }

    /// Takes down done activities left on the Lock Screen: the app is open
    /// and shows the result itself.
    func clearFinished() {
        Task { await Self.clearEnded() }
    }

    private nonisolated static func clearEnded() async {
        for activity in Activity<StudyActivityAttributes>.activities where activity.activityState == .ended {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends the activity at once: the session was stopped, or the app is open.
    func end() {
        guard let activityID else { return }
        self.activityID = nil
        shown = nil
        Task { await Self.end(id: activityID) }
    }
}
