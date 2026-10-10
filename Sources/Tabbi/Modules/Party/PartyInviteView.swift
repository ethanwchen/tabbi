import SwiftUI
import TabbiKitCore
import TabbiKit

/// What an invite link opens: the whole notch asks "Add a friend?" or
/// "Join this party?" (turning Party on first if it's off) and says how it
/// went. `PartyInviteFlow` decides the step and its words; this draws them.
enum PartyInviteViews {
    @MainActor
    static func takeover(store: PartyStore, turnOnParty: @escaping () -> Void) -> NotchTakeover {
        NotchTakeover(
            leading: { AnyView(PartyInviteTitle()) },
            trailing: { AnyView(EmptyView()) },
            body: { AnyView(PartyInviteBody(store: store, turnOnParty: turnOnParty)) }
        )
    }
}

/// "Party invite" where the tab bar usually sits.
private struct PartyInviteTitle: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: PartyModule.descriptor.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PartyStyle.accent)
            Text("Party invite")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
        }
    }
}

/// One card: a pet or symbol on the left, the question or answer beside it,
/// and its buttons underneath.
private struct PartyInviteBody: View {
    @ObservedObject var store: PartyStore
    let turnOnParty: () -> Void
    @EnvironmentObject private var notch: NotchViewModel

    var body: some View {
        if let flow = store.invite {
            Card(padding: Theme.Spacing.xl) {
                HStack(spacing: Theme.Spacing.l) {
                    artwork(flow)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(flow.title)
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.Palette.primaryText)
                                .lineLimit(1)
                            Text(flow.message)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        buttons(flow)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .motion(Theme.Motion.content, value: flow.stage)
        }
    }

    @ViewBuilder
    private func artwork(_ flow: PartyInviteFlow) -> some View {
        if let person = flow.person {
            PartyPet(profile: person, pixelSize: 2)
        } else {
            switch flow.stage {
            case .needsParty, .connecting:
                PartyPet(pet: store.pet, pixelSize: 2)
            case .unavailable:
                symbol("wifi.slash")
            case .refused:
                symbol("exclamationmark.circle.fill")
            case .finished:
                symbol("checkmark")
            case .confirming, .working:
                switch flow.invite {
                case .addFriend: symbol("person.badge.plus")
                case .joinParty: symbol(PartyModule.descriptor.symbol)
                }
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(PartyStyle.accent)
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(PartyStyle.accent.opacity(0.16)))
    }

    private func buttons(_ flow: PartyInviteFlow) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            if let title = flow.primaryTitle {
                PartyPillButton(title: title, isProminent: true, isBusy: flow.stage == .working,
                                help: primaryHelp(flow)) {
                    primary(flow)
                }
            }
            if flow.primaryTitle == nil {
                // Nothing left but closing, so closing is the main button.
                PartyPillButton(title: flow.dismissTitle, isProminent: true, help: "Close the invite") {
                    close(flow)
                }
            } else {
                PartyTextButton(title: flow.dismissTitle, help: "Close the invite without doing anything") {
                    close(flow)
                }
            }
            if flow.stage == .connecting || flow.stage == .working {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
        }
    }

    private func primary(_ flow: PartyInviteFlow) {
        switch flow.stage {
        case .needsParty: turnOnParty()
        case .unavailable: store.retryInviteConnection()
        default: store.confirmInvite()
        }
    }

    private func primaryHelp(_ flow: PartyInviteFlow) -> String {
        switch flow.stage {
        case .needsParty: "Add the Party tab and connect to the party server"
        case .unavailable, .refused: "Try again now"
        default:
            switch flow.invite {
            case .addFriend: "Send a friend request with this code"
            case .joinParty: "Join this party now"
            }
        }
    }

    /// Closing after a friend was added or a party joined goes on to the
    /// Party tab, where they now show.
    private func close(_ flow: PartyInviteFlow) {
        let showParty: Bool
        if case .finished = flow.stage { showParty = true } else { showParty = false }
        store.dismissInvite()
        if showParty, notch.layout.isEnabled(PartyModule.descriptor.id) {
            notch.selected = PartyModule.descriptor.id
        }
    }
}
