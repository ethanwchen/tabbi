import SwiftUI
import NotchKitCore
import NotchKit

/// The panel's primary area: the party's pets side by side with the shared
/// session below, or, outside a party, ways to start or join one.
struct PartyStage: View {
    @ObservedObject var store: PartyStore
    var focus: FocusState<PartyField?>.Binding

    var body: some View {
        Card {
            Group {
                if let party = store.state.party {
                    PartyRoom(party: party, store: store)
                } else {
                    PartyLobby(store: store, focus: focus)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(Theme.Motion.content, value: store.state.party?.code)
    }
}

// MARK: - In a party

/// The party I'm in: its code, everyone's pets, and the shared session.
private struct PartyRoom: View {
    let party: Party
    @ObservedObject var store: PartyStore

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            header
            members
                .frame(maxHeight: .infinity)
            PartySessionBar(party: party, store: store)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Party")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
            PartyCopyCode(code: party.code, help: "The party code. Click to copy it, then send it to friends.")
            Text("\(party.members.count) of \(party.maxMembers)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.tertiaryText)
                .help("Members in this party")
            Spacer(minLength: Theme.Spacing.s)
            PartyTextButton(title: "Leave", isBusy: store.pending == .leaveParty,
                            help: store.state.isHost && party.members.count > 1
                                ? "Leave the party; the next member becomes host" : "Leave the party") {
                store.leaveParty()
            }
        }
    }

    private var members: some View {
        // Roomy columns while they fit; a full party of eight narrows them
        // so everyone still stands in one row.
        GeometryReader { proxy in
            let count = CGFloat(max(party.members.count, 1))
            let spacing = Theme.Spacing.xs
            let width = min(Self.roomyWidth, ((proxy.size.width - spacing * (count - 1)) / count).rounded(.down))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(party.members) { member in
                    PartyMemberView(member: member, isMe: member.profile.code == store.state.friendCode,
                                    width: width, now: store.now)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(Theme.Motion.snappy, value: party.members.map(\.id))
    }

    private static let roomyWidth: CGFloat = 72
}

/// One member: their pet with name and status underneath. Narrow columns
/// (a crowded party) get the smaller pet and only the countdown.
private struct PartyMemberView: View {
    let member: PartyMember
    let isMe: Bool
    let width: CGFloat
    let now: Date

    private var roomy: Bool { width >= 60 }

    var body: some View {
        let status = PartyRoster.status(member.presence, online: member.online)
        VStack(spacing: Theme.Spacing.xxs) {
            PartyPet(profile: member.profile, asleep: status == .offline, pixelSize: roomy ? 1.5 : 1)
                .frame(width: width)
                .overlay(alignment: .topLeading) {
                    // No room beside a narrow name, so the crown sits on the pet.
                    if member.host && !roomy { crown }
                }
            HStack(spacing: Theme.Spacing.xxs) {
                if member.host && roomy { crown }
                Text(isMe ? "You" : member.profile.name)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .minimumScaleFactor(roomy ? 1 : 0.8)
            }
            HStack(spacing: Theme.Spacing.xs) {
                if roomy || shortStatus(status) == nil {
                    Circle()
                        .fill(PartyStyle.color(for: status))
                        .frame(width: 5, height: 5)
                }
                if let text = shortStatus(status) {
                    // Narrow columns drop the dot and color the countdown instead.
                    Text(text)
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(roomy ? Theme.Palette.tertiaryText : PartyStyle.color(for: status))
                }
            }
            .frame(height: 13)
        }
        .lineLimit(1)
        .frame(width: width)
        .help(help(status))
    }

    private var crown: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.Palette.warning)
    }

    /// Fits under a pet: the countdown while studying, otherwise the
    /// status; in a narrow column only a countdown, or nil for just the dot.
    private func shortStatus(_ status: PartyStatus) -> String? {
        let left = PartyRoster.timeLeft(member.presence, online: member.online, at: now)
        guard roomy else {
            return left.map { "\(Int(($0 / 60).rounded(.up)))m" }
        }
        switch status {
        case .studying: return left.map { PartyRoster.minutesLeft($0) } ?? "Studying"
        case .onBreak: return "Break"
        case .idle: return "Online"
        case .offline: return "Offline"
        }
    }

    private func help(_ status: PartyStatus) -> String {
        var parts = ["\(isMe ? "You" : member.profile.name) with \(member.profile.petName)"]
        parts.append(PartyRoster.statusLine(member.presence, online: member.online, at: now))
        if let minutes = member.presence?.todayMinutes, minutes > 0 {
            parts.append("\(PartyRoster.duration(minutes: minutes)) today")
        }
        return parts.joined(separator: " · ")
    }
}

/// The shared session: its countdown, with End for the host; or, with none
/// running, Start buttons for the host and a waiting line for everyone else.
private struct PartySessionBar: View {
    let party: Party
    @ObservedObject var store: PartyStore

    /// Shared focus lengths the host can start with one click.
    private static let lengths = [25, 50]

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let session = party.session, session.phaseEndsAt > store.now {
                running(session)
            } else if store.state.isHost {
                Text(party.session == nil ? "Focus together" : "Focus again")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize()
                Spacer(minLength: Theme.Spacing.s)
                ForEach(Self.lengths, id: \.self) { minutes in
                    PartyPillButton(title: "\(minutes) min", symbol: minutes == Self.lengths[0] ? "play.fill" : nil,
                                    isProminent: minutes == Self.lengths[0], isBusy: store.pending == .session,
                                    help: "Start a \(minutes)-minute focus session for everyone in the party") {
                        store.startSession(minutes: minutes)
                    }
                }
            } else {
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Text("Waiting for \(hostName) to start a session")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .frame(height: 24)
    }

    @ViewBuilder
    private func running(_ session: PartySession) -> some View {
        let total = max(session.phaseEndsAt.timeIntervalSince(session.startedAt), 1)
        let left = max(session.phaseEndsAt.timeIntervalSince(store.now), 0)
        Image(systemName: "timer")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PartyStyle.accent)
        Text(Self.clock(left))
            .font(Theme.Typography.metricSmall)
            .foregroundStyle(Theme.Palette.primaryText)
            .contentTransition(.numericText(countsDown: true))
        Text("shared focus")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.tertiaryText)
            .fixedSize()
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.surface)
                Capsule().fill(PartyStyle.accent)
                    .frame(width: proxy.size.width * (1 - left / total))
            }
        }
        .frame(height: 4)
        .help("\(PartyRoster.minutesLeft(left)) in the party's shared session")
        if store.state.isHost {
            PartyTextButton(title: "End", isBusy: store.pending == .session,
                            help: "End the shared session for everyone") {
                store.endSession()
            }
        }
    }

    private var hostName: String {
        party.members.first { $0.host }?.profile.name ?? "the host"
    }

    /// "18:20" for a phase's remaining time.
    private static func clock(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Not in a party

/// Outside a party: my pet with an invitation to start one or join by code.
private struct PartyLobby: View {
    @ObservedObject var store: PartyStore
    var focus: FocusState<PartyField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                if let profile = store.state.profile {
                    PartyPet(profile: profile, pixelSize: 1.5)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Study together")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text("Start a party and share its code, or join a friend's. Your pets sit side by side while you focus.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                PartyPillButton(title: "Start a party", symbol: "plus", isProminent: true,
                                isBusy: store.pending == .createParty,
                                help: "Create a party and get a code to share") {
                    store.createParty()
                }
                PartyCodeField(placeholder: "Party code", symbol: "number",
                               length: PartyCode.partyCodeLength, field: .partyCode, focus: focus,
                               help: "Have a code? Type the \(PartyCode.partyCodeLength)-character party code and press Return to join") {
                    store.joinParty(code: $0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
