import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Party tab: the party (or a way into one) on the left and friends on
/// the right once connected; before that, a single calm state for
/// connecting, an unreachable server, or a server setting that can't work.
struct PartyPanel: View {
    @ObservedObject var store: PartyStore
    @EnvironmentObject private var notch: NotchViewModel
    @FocusState private var focus: PartyField?

    /// Width of the friends column; the stage keeps the rest.
    static let friendsWidth: CGFloat = 212

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { report }
            .overlay(alignment: .bottom) { notice }
            .overlay(alignment: .top) { celebration }
            .motion(Theme.Motion.content, value: phase)
            .motion(Theme.Motion.snappy, value: store.celebration)
            .motion(Theme.Motion.snappy, value: store.notice)
            .motion(Theme.Motion.snappy, value: store.reporting)
            .onAppear { store.setVisible(true) }
            .onChange(of: focus) { _, field in notch.isPinned = field != nil }
            .onDisappear {
                notch.isPinned = false
                store.setVisible(false)
            }
            .task(id: store.notice) {
                // A notice is about the last click; let it go after a moment.
                guard store.notice != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                store.clearNotice()
            }
    }

    /// Which screen shows, for transitions between them.
    private var phase: Int {
        switch store.state.connection {
        case .invalidServer: 0
        case .connecting: 1
        case .unreachable: 2
        case .connected: 3
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state.connection {
        case .connected:
            HStack(spacing: Theme.Spacing.m) {
                PartyStage(store: store, focus: $focus)
                PartyFriendsCard(store: store, focus: $focus)
                    .frame(width: Self.friendsWidth)
            }
            .transition(.opacity)
        case .connecting:
            PartyMessage(symbol: nil, pet: store.pet, title: "Joining the party server…",
                         detail: "Signing you in so friends can find you.")
                .transition(.opacity)
        case .unreachable(.banned):
            PartyMessage(symbol: "hand.raised.fill", title: "Party isn't available",
                         detail: "This account can no longer use Party. If you think that's a mistake, write to \(SupportContact.email).") {
                PartyPillButton(title: "Email Support", symbol: "envelope", help: "Write to \(SupportContact.email)") {
                    NSWorkspace.shared.open(SupportContact.mailURL)
                }
            }
            .transition(.opacity)
        case .unreachable(let error):
            PartyMessage(symbol: "wifi.slash", title: "Can't reach the party server",
                         detail: Self.unreachableDetail(error)) {
                PartyPillButton(title: "Try again", symbol: "arrow.clockwise", help: "Connect to the party server now") {
                    store.retry()
                }
            }
            .transition(.opacity)
        case .invalidServer(let message):
            PartyMessage(symbol: "exclamationmark.triangle", title: "Check the party server",
                         detail: message + " Fix it in Settings > Tabs > Party > Options, or clear it to use the Tabbi server.")
                .transition(.opacity)
        }
    }

    /// The title already says the server can't be reached; this says why
    /// (when it's more than the network) and what happens next.
    private static func unreachableDetail(_ error: PartyError) -> String {
        switch error {
        case .unreachable, .timedOut, .transport:
            "Check your internet connection. Friends and parties show up once it's back."
        default:
            error.isTransient ? error.message + " Trying again in the background." : error.message
        }
    }

    @ViewBuilder
    private var celebration: some View {
        if let celebration = store.celebration {
            PartyCelebrationBanner(celebration: celebration, pets: celebratingPets) {
                store.clearCelebration()
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)
            .transition(.motionRow(from: .top))
        }
    }

    /// The members' pets as friends see them, mine first; just mine when
    /// the party is gone.
    private var celebratingPets: [PetProfile] {
        let members = store.state.party?.members ?? []
        let mine = members.filter { $0.profile.code == store.state.friendCode }
        let others = members.filter { $0.profile.code != store.state.friendCode }
        let pets = (mine + others).map { PartyPetAppearance.pet(for: $0.profile) }
        return pets.isEmpty ? [store.pet] : pets
    }

    @ViewBuilder
    private var report: some View {
        if let profile = store.reporting, store.state.connection == .connected {
            PartyReportCard(profile: profile, store: store, focus: $focus)
                .id(profile.code)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = store.notice {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: store.noticeConfirms ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(store.noticeConfirms ? Theme.Palette.success : Theme.Palette.warning)
                Text(notice)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
            }
            .font(Theme.Typography.caption)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 24)
            .background(Capsule().fill(Color(white: 0.16)))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
            .onTapGesture { store.clearNotice() }
            .help("Click to dismiss")
            .transition(.motionRow(from: .bottom))
        }
    }
}

/// A centered state for the whole panel: an icon (or my pet), a title, a
/// line of detail, and an optional action.
private struct PartyMessage<Action: View>: View {
    let symbol: String?
    var pet: PetProfile?
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    init(symbol: String?, pet: PetProfile? = nil, title: String, detail: String,
         @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.symbol = symbol
        self.pet = pet
        self.title = title
        self.detail = detail
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let pet {
                PartyPet(pet: pet, pixelSize: 1.5)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PartyStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(PartyStyle.accent.opacity(0.16)))
            }
            VStack(spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)
            action
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
