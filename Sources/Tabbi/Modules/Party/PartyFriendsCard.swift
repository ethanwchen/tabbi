import SwiftUI
import TabbiKitCore
import TabbiKit

/// The right column: my friend code to share, friends with their pets and
/// what they're doing, and a field to add one by code.
struct PartyFriendsCard: View {
    @ObservedObject var store: PartyStore
    var focus: FocusState<PartyField?>.Binding

    private var state: PartyState { store.state }

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                header
                    .padding(.leading, Theme.Spacing.xs)
                list
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                PartyCodeField(placeholder: String(localized: "Friend's code", bundle: .tabbi), symbol: "person.badge.plus",
                               length: PartyCode.friendCodeLength, field: .friendCode, focus: focus,
                               help: String(localized: "Type or paste a friend's \(PartyCode.friendCodeLength)-character code and press Return", bundle: .tabbi)) {
                    store.addFriend(code: $0)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("Friends", bundle: .tabbi)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .fixedSize()
            if let error = state.staleError {
                Button(action: store.retry) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.warning)
                }
                .buttonStyle(.plain)
                .help(String(localized: "\(error.message) Showing the last known status. Click to retry.", bundle: .tabbi))
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let code = state.friendCode {
                // "Copy" is spelled out while the column has room for it.
                ViewThatFits(in: .horizontal) {
                    shareCode(code, showsLabel: true)
                    shareCode(code, showsLabel: false)
                }
            }
        }
    }

    private func shareCode(_ code: String, showsLabel: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            PartyCopyCode(code: code, showsLabel: showsLabel,
                          help: String(localized: "Your friend code. Copy it and send it to a friend.", bundle: .tabbi))
            PartyShareInvite(invite: .addFriend(code: code),
                             help: String(localized: "Share an invite link. A friend who opens it can add you in one click.", bundle: .tabbi))
        }
        .fixedSize()
    }

    @ViewBuilder
    private var list: some View {
        if !state.friendsLoaded {
            Color.clear
        } else if state.friends.isEmpty {
            emptyFriends
        } else {
            scrollingRows
                // Rows fade out at the bottom edge instead of being cut off.
                .edgeFade(.bottom, length: Self.fadeHeight)
        }
    }

    private static let fadeHeight = Theme.Spacing.m

    @ViewBuilder
    private var scrollingRows: some View {
        if PartyStyle.isSnapshot {
            // Takes the space offered rather than the rows' full height.
            Color.clear
                .overlay(alignment: .top) { rows }
                .clipped()
        } else {
            ScrollView(.vertical) { rows }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                // A margin as tall as the fade, so the last row can scroll clear of it.
                .contentMargins(.bottom, Self.fadeHeight, for: .scrollContent)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(state.friends) { friend in
                PartyFriendRow(friend: friend, store: store)
            }
        }
        .motion(Theme.Motion.snappy, value: state.friends.map(\.id))
    }

    private var emptyFriends: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "person.2")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PartyStyle.accent)
                .padding(.bottom, Theme.Spacing.xxs)
            Text("No friends yet", bundle: .tabbi)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.primaryText)
            Text("Share your code above, or add theirs below.", bundle: .tabbi)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One friend: their pet, name, what they're doing, and Join when they're
/// in a party I'm not in. Right-click to remove, report or block.
private struct PartyFriendRow: View {
    let friend: PartyFriend
    @ObservedObject var store: PartyStore
    @State private var hovering = false

    var body: some View {
        let status = PartyRoster.status(friend.presence, online: friend.online)
        HStack(spacing: Theme.Spacing.xs) {
            PartyPet(profile: friend.profile, asleep: status == .offline)
            VStack(alignment: .leading, spacing: 0) {
                Text(friend.profile.name)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(status == .offline ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(PartyStyle.color(for: status))
                        .frame(width: 5, height: 5)
                    Text(PartyRoster.compactStatusLine(friend.presence, online: friend.online, at: store.now))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            trailing
        }
        .padding(.trailing, Theme.Spacing.xxs)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering ? Theme.Palette.surface : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .help(help)
        .contextMenu {
            Button(String(localized: "Remove \(friend.profile.name)", bundle: .tabbi), role: .destructive) {
                store.removeFriend(code: friend.profile.code)
            }
            PartyModerationMenu(profile: friend.profile, store: store)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let party = friend.party, party.code == store.state.party?.code {
            Image(systemName: "person.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PartyStyle.accent.opacity(0.7))
                .frame(width: 20)
                .help(String(localized: "\(friend.profile.name) is in your party", bundle: .tabbi))
        } else if friend.canJoin {
            PartyPillButton(title: String(localized: "Join", bundle: .tabbi), isBusy: store.pending == .joinFriend(friend.profile.code), height: 20,
                            help: String(localized: "Join \(friend.profile.name)'s party", bundle: .tabbi)) {
                store.join(friend: friend.profile.code)
            }
            // The row's own tooltip hides this one from VoiceOver, so name whose party.
            .accessibilityLabel(String(localized: "Join \(friend.profile.name)'s party", bundle: .tabbi))
        }
    }

    private var help: String {
        var parts = [String(localized: "\(friend.profile.name) with \(friend.profile.petName)", bundle: .tabbi)]
        if let presence = friend.presence, friend.online, presence.todayMinutes > 0 {
            let studied = PartyRoster.duration(minutes: presence.todayMinutes)
            parts.append(String(localized: "\(studied) studied today", bundle: .tabbi))
        }
        if let presence = friend.presence, presence.streakDays > 1 {
            parts.append(String(localized: "\(presence.streakDays)-day streak", bundle: .tabbi))
        }
        return parts.joined(separator: " · ") + ". " + String(localized: "Right-click to remove, report or block.", bundle: .tabbi)
    }
}
