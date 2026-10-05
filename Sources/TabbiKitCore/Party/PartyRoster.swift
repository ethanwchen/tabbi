import Foundation

/// How friends and party members read in the Party panel: who's studying,
/// how long they have left, and a stable order that puts active people first.
public enum PartyRoster {
    /// The status to show: the server's presence, or offline when the user
    /// isn't online or never sent a heartbeat.
    public static func status(_ presence: PartyPresence?, online: Bool) -> PartyStatus {
        guard online, let presence else { return .offline }
        return presence.status
    }

    /// Seconds left in the current focus or break phase, counted down
    /// locally from `phaseEndsAt`; nil when there's no running phase.
    public static func timeLeft(_ presence: PartyPresence?, online: Bool, at now: Date) -> TimeInterval? {
        switch status(presence, online: online) {
        case .studying, .onBreak:
            guard let end = presence?.phaseEndsAt else { return nil }
            return max(end.timeIntervalSince(now), 0)
        case .idle, .offline:
            return nil
        }
    }

    /// One short line, e.g. "Studying · 18 min left", "On a break",
    /// "Online" or "Offline".
    public static func statusLine(_ presence: PartyPresence?, online: Bool, at now: Date) -> String {
        let status = status(presence, online: online)
        let left = timeLeft(presence, online: online, at: now).map { " · \(minutesLeft($0))" } ?? ""
        switch status {
        case .studying: return "Studying" + left
        case .onBreak: return "On a break" + left
        case .idle: return "Online"
        case .offline: return "Offline"
        }
    }

    /// The same status in a narrow row: "Studying · 18m", "Break · 4m",
    /// "Online" or "Offline". A phase that already ended drops its count.
    public static func compactStatusLine(_ presence: PartyPresence?, online: Bool, at now: Date) -> String {
        let status = status(presence, online: online)
        let minutes = timeLeft(presence, online: online, at: now).map { Int(($0 / 60).rounded(.up)) } ?? 0
        let left = minutes > 0 ? " · \(minutes)m" : ""
        switch status {
        case .studying: return "Studying" + left
        case .onBreak: return "Break" + left
        case .idle: return "Online"
        case .offline: return "Offline"
        }
    }

    /// "18 min left", rounding up so a phase reads "1 min left" until it ends.
    public static func minutesLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded(.up))
        return minutes <= 0 ? "ending" : "\(minutes) min left"
    }

    /// Study time as "45m" or "1h 20m".
    public static func duration(minutes: Int) -> String {
        let minutes = max(minutes, 0)
        guard minutes >= 60 else { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }

    /// Friends ordered studying, on a break, online, then offline; by name
    /// within each group so rows don't jump between refreshes.
    public static func sorted(_ friends: [PartyFriend]) -> [PartyFriend] {
        friends.sorted { lhs, rhs in
            let left = rank(status(lhs.presence, online: lhs.online))
            let right = rank(status(rhs.presence, online: rhs.online))
            if left != right { return left < right }
            return order(lhs.profile, rhs.profile)
        }
    }

    /// Party members with the host first, then by name, so the pets stand
    /// in the same place on every refresh.
    public static func sorted(_ members: [PartyMember]) -> [PartyMember] {
        members.sorted { lhs, rhs in
            if lhs.host != rhs.host { return lhs.host }
            return order(lhs.profile, rhs.profile)
        }
    }

    private static func rank(_ status: PartyStatus) -> Int {
        switch status {
        case .studying: 0
        case .onBreak: 1
        case .idle: 2
        case .offline: 3
        }
    }

    private static func order(_ lhs: PartyProfile, _ rhs: PartyProfile) -> Bool {
        switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.code < rhs.code
        }
    }
}
