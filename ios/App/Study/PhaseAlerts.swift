import Foundation
import TabbiKitCore
import UserNotifications

/// One local notification for a phase end that is still ahead.
struct PhaseAlert: Equatable {
    var id: String
    var fireAt: Date
    var title: String
    var body: String

    /// How many upcoming phase ends get a notification. A focus block runs
    /// straight into its break, so a phone left in a pocket still hears
    /// both ends; a break ends into an idle focus block, which stops the chain.
    static let lookahead = 4
    static let idPrefix = "dev.tabbi.ios.phaseEnd"

    /// The notifications for every phase end `session` will reach without
    /// another tap, soonest first, worded like the Mac's focus timer. Empty
    /// while it is idle, paused or counting up.
    ///
    /// When `filming`, the focus block under way has the Pet Cam armed, and
    /// its end says only that the block is done and the tape is ready.
    static func upcoming(for session: StudySession, filming: Bool = false) -> [PhaseAlert] {
        var future = session
        var alerts: [PhaseAlert] = []
        while alerts.count < lookahead, let end = future.endsAt {
            guard let ended = future.advance(to: end).last else { break }
            let (title, body) = filming && alerts.isEmpty && ended.phase == .focus ? tapeReady
                : message(after: ended, next: future)
            alerts.append(PhaseAlert(id: "\(idPrefix).\(Int64(end.timeIntervalSinceReferenceDate * 1000))",
                                     fireAt: end, title: title, body: body))
        }
        return alerts
    }

    /// The end of a filmed block: nothing about the room, just that it is
    /// done and there is something to watch. English only for now (see
    /// ios/README.md, Pet Cam strings).
    /// Teases without spoiling: the pet always strikes, so this is always
    /// true and never says catch or miss.
    static let tapeReady = (title: "Tape ready", body: "Something happened while you were out.")

    /// The Mac's wording (`FocusTimerFormat.completionMessage`): "Focus
    /// session done" and the break ahead, "Break's over" and the next
    /// block, and for the plain Timer its name and a cheer.
    static func message(after ended: StudyPhaseRecord, next: StudySession) -> (title: String, body: String) {
        let minutes = Int(((next.phaseDuration ?? 0) / 60).rounded())
        if ended.phase.isBreak {
            let body = next.phaseDuration == nil
                ? String(localized: "Focus again", bundle: .tabbi)
                : String(localized: "Ready for another \(minutes)-minute focus session?", bundle: .tabbi)
            return (String(localized: "Break's over", bundle: .tabbi), body)
        }
        if ended.method == .timer {
            return (StudyTimerFormat.phaseName(ended.phase, method: next.method),
                    String(localized: "Session done. Nice work!", bundle: .tabbi))
        }
        if !next.phase.isBreak {
            // A question block's focus runs into its review.
            return (String(localized: "Focus session done", bundle: .tabbi),
                    StudyTimerFormat.phaseName(next.phase, method: next.method))
        }
        return (String(localized: "Focus session done", bundle: .tabbi),
                String(localized: "Time for a \(minutes)-minute break.", bundle: .tabbi))
    }
}

/// Schedules the phase-end notifications with the system. The app cannot
/// run while it is suspended, so these are what tell someone a block is done.
@MainActor
final class PhaseAlertScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    /// What should be pending, and what was handed to the system.
    private var wanted: [PhaseAlert] = []
    private var scheduled: [PhaseAlert] = []

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    /// Asks once, the first time a session starts: that is when the user
    /// can see why Tabbi wants to alert them. Declining changes nothing else.
    /// The system refuses requests added before the answer, so the wanted
    /// alerts are added again once it is yes.
    func requestAuthorizationIfNeeded() {
        let center = center
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            scheduled = []
            apply(now: Date())
        }
    }

    /// Replaces the pending notifications with `alerts`.
    func schedule(_ alerts: [PhaseAlert], now: Date) {
        wanted = alerts
        apply(now: now)
    }

    private func apply(now: Date) {
        guard wanted != scheduled else { return }
        center.removePendingNotificationRequests(withIdentifiers: scheduled.map(\.id))
        scheduled = wanted
        for alert in wanted where alert.fireAt > now {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(alert.fireAt.timeIntervalSince(now), 1),
                                                            repeats: false)
            center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }
    }

    /// In the foreground the banner still shows: it is the phase-end sound.
    /// A filmed block's end is the exception: the tape plays at once, so a
    /// banner would only cover its burn-in.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        if content.title == PhaseAlert.tapeReady.title, content.body == PhaseAlert.tapeReady.body { return [.list] }
        return [.banner, .sound, .list]
    }
}
