import SwiftUI
import TabbiKitCore
import TabbiKit

/// Onboarding's party step: the profile friends will see (my pet and a
/// name to edit in place), going invisible in one tap, and beside it my
/// friend code to share and a field to add a friend's. While the server
/// hasn't answered yet it says so, with a retry when it can't be reached.
struct PartyOnboardingView: View {
    @ObservedObject var store: PartyStore
    @FocusState private var focus: PartyField?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PartySetupProfileCard(store: store)
                .frame(width: 252)
            PartySetupFriendsCard(store: store, focus: $focus)
        }
        .motion(Theme.Motion.content, value: store.state.connection)
        .motion(Theme.Motion.snappy, value: store.notice)
        // Visible like the panel, so friends load and a failed connect retries.
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
        .task(id: store.notice) {
            guard store.notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            store.clearNotice()
        }
    }
}

/// My pet, the name friends see (click to rename) and the connection
/// status, what is shared, and the invisible switch.
private struct PartySetupProfileCard: View {
    @ObservedObject var store: PartyStore
    @State private var isRenaming = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    PartyPet(pet: store.pet, pixelSize: 1.5)
                        .frame(width: 36, height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        nameRow
                        statusLine
                            .padding(.leading, Theme.Spacing.xs)
                    }
                }
                Text("Friends see your name, your pet and when you're studying. Nothing about your cards or decks leaves your Mac.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                PartySetupVisibilityButton(invisible: store.settings.invisible) {
                    var settings = store.settings
                    settings.invisible.toggle()
                    store.update(settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The name as friends will see it, or the server's until one is typed.
    private var name: String? {
        store.settings.cleanedName ?? store.state.profile?.name
    }

    @ViewBuilder private var nameRow: some View {
        if isRenaming {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.primaryText)
                .focused($nameFocused)
                .onAppear { nameFocused = true }
                .onSubmit(commit)
                .onExitCommand { isRenaming = false }
                .onChange(of: nameFocused) { _, focused in if !focused { commit() } }
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .fill(Theme.Palette.surfaceHover)
                )
        } else {
            PartySetupNameButton(name: name) {
                draft = name ?? ""
                isRenaming = true
            }
        }
    }

    private func commit() {
        guard isRenaming else { return }
        var settings = store.settings
        settings.name = String(draft.prefix(PartySettings.maxNameLength * 2))
        store.update(settings)
        isRenaming = false
    }

    private var statusLine: some View {
        let status = self.status
        return HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .contentTransition(.opacity)
        }
        .lineLimit(1)
    }

    private var status: (text: String, color: Color) {
        switch store.state.connection {
        case .connected where store.settings.invisible:
            ("Invisible to friends", Theme.Palette.tertiaryText)
        case .connected:
            ("Online", Theme.Palette.success)
        case .connecting:
            ("Joining the party server", Theme.Palette.tertiaryText)
        case .unreachable, .invalidServer:
            ("Offline", Theme.Palette.warning)
        }
    }
}

/// The name with a pencil that brightens on hover; a prompt when there is
/// no name yet.
private struct PartySetupNameButton: View {
    let name: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(name ?? "Add your name")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(name == nil ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(hovering ? Theme.Palette.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("The name friends see, up to \(PartySettings.maxNameLength) characters. Click to change it.")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// One tap between visible and invisible; the label says what friends see.
private struct PartySetupVisibilityButton: View {
    let invisible: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: invisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(invisible ? Theme.Palette.secondaryText : PartyStyle.accent)
                    .frame(width: 14)
                    .contentTransition(.symbolEffect(.replace))
                Text(invisible ? "Invisible: friends see you as away" : "Visible: friends see when you study")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 24)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(invisible ? "Show friends when you study again" : "Go invisible. Your study minutes still count.")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: invisible)
    }
}

/// My friend code to share and a field to add a friend's, once the server
/// answers; until then, what is happening with the connection.
private struct PartySetupFriendsCard: View {
    @ObservedObject var store: PartyStore
    var focus: FocusState<PartyField?>.Binding

    private var state: PartyState { store.state }

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Your friend code")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                    Spacer(minLength: Theme.Spacing.xs)
                    if let code = state.friendCode {
                        PartyCopyCode(code: code, showsLabel: true,
                                      help: "Your friend code. Copy it and send it to a friend.")
                    }
                }
                .frame(height: 20)
                .padding(.leading, Theme.Spacing.xs)
                content
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if state.connection == .connected {
                    PartyCodeField(placeholder: "Friend's code", symbol: "person.badge.plus",
                                   length: PartyCode.friendCodeLength, field: .friendCode, focus: focus,
                                   help: "Type or paste a friend's \(PartyCode.friendCodeLength)-character code and press Return") {
                        store.addFriend(code: $0)
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch state.connection {
        case .connected:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                message(symbol: "person.2.fill", title: friendsTitle,
                        detail: store.notice ?? (state.friends.isEmpty
                            ? "Share your code, or add theirs below. Start a party from the Party tab."
                            : nil),
                        isNotice: store.notice != nil)
                if !state.friends.isEmpty {
                    friendPets
                }
            }
        case .connecting:
            message(symbol: "antenna.radiowaves.left.and.right", title: "Joining the party server",
                    detail: "Signing you in so friends can find you. Your code shows here in a moment.")
        case .unreachable:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                message(symbol: "wifi.slash", title: "Can't reach the party server",
                        detail: "Check your internet connection. You can also set up Party later in its tab.")
                PartyPillButton(title: "Try Again", symbol: "arrow.clockwise",
                                help: "Connect to the party server now") { store.retry() }
            }
        case .invalidServer(let message):
            self.message(symbol: "exclamationmark.triangle.fill", title: "Check the party server",
                         detail: message + " Fix it in Settings > Tabs > Party > Options.")
        }
    }

    /// The first few friends' pets, dozing when they're away.
    private var friendPets: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(state.friends.prefix(Self.shownPets)) { friend in
                PartyPet(profile: friend.profile, asleep: !friend.online)
                    .help(friend.online ? friend.profile.name : "\(friend.profile.name) is away")
            }
            if state.friends.count > Self.shownPets {
                Text("+\(state.friends.count - Self.shownPets)")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
    }

    private static let shownPets = 6

    private var friendsTitle: String {
        guard state.friendsLoaded, !state.friends.isEmpty else { return "No friends yet" }
        return state.friends.count == 1 ? "1 friend" : "\(state.friends.count) friends"
    }

    private func message(symbol: String, title: String, detail: String?, isNotice: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PartyStyle.accent)
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
            }
            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isNotice ? Theme.Palette.warning : Theme.Palette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .padding(.top, Theme.Spacing.xxs)
    }
}
