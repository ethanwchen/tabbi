import SwiftUI
import NotchKitCore
import NotchKit

/// The Today panel's "Up next" card: the next few events today with a timing
/// badge and a Join button for video calls, or a compact state explaining why
/// there's nothing to show.
struct UpNextCard: View {
    @ObservedObject var store: UpNextStore
    /// The kit's name for what the calendar holds (`TodayPlanSettings.upNextEvents`).
    let upNextEvents: String

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Up next")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .padding(.horizontal, Theme.Spacing.xs)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(Theme.Motion.content, value: store.events)
        .animation(Theme.Motion.content, value: store.emptySituation)
    }

    @ViewBuilder
    private var content: some View {
        if let situation = store.emptySituation {
            let state = UpNextEmptyState(situation, upNextEvents: upNextEvents, appName: Edition.current.name)
            UpNextMessage(state: state) { perform($0) }
        } else {
            VStack(spacing: 0) {
                ForEach(store.events) { event in
                    UpNextRow(event: event, now: store.now) { store.join($0) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func perform(_ action: UpNextEmptyState.Action) {
        switch action {
        case .requestAccess: store.requestAccess()
        case .openPrivacySettings: store.openPrivacySettings()
        case .openInternetAccounts: store.openInternetAccounts()
        }
    }
}

/// One event: color dot and title, then start time and badge, with a Join
/// button on the right when the event has a video-call link.
private struct UpNextRow: View {
    let event: UpcomingEvent
    let now: Date
    let join: (MeetingLink) -> Void
    @State private var hovering = false

    var body: some View {
        let timing = event.timing(at: now)
        HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(UpcomingEventFormat.title(event))
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(UpcomingEventFormat.startTime(event.start))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                    Text(UpcomingEventFormat.badge(timing))
                        .foregroundStyle(timing == .now ? accent : Theme.Palette.secondaryText)
                        .contentTransition(.numericText())
                }
                .font(Theme.Typography.caption.monospacedDigit())
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let link = event.meetingLink {
                UpNextJoinButton(link: link, isLive: timing == .now) { join(link) }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering ? Theme.Palette.surface : .clear)
        )
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .help("\(UpcomingEventFormat.title(event)), \(event.start.formatted(date: .omitted, time: .shortened))")
    }

    private var accent: Color { TodayModule.descriptor.accentColor }

    private var dotColor: Color {
        guard let color = event.calendarColor else { return accent }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

/// Round video button; filled with the accent while the call is under way.
private struct UpNextJoinButton: View {
    let link: MeetingLink
    let isLive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = TodayModule.descriptor.accentColor
        Button(action: action) {
            Image(systemName: "video.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isLive ? Theme.Palette.background : accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isLive ? accent.opacity(hovering ? 1 : 0.9)
                                          : accent.opacity(hovering ? 0.28 : 0.16)))
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Join \(link.provider.displayName) call")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

/// Icon, title, detail, and an optional action, sized for the narrow card.
private struct UpNextMessage: View {
    let state: UpNextEmptyState
    let perform: (UpNextEmptyState.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: state.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TodayModule.descriptor.accentColor)
                    // Badged symbols run taller; a fixed box keeps every state's height alike.
                    .frame(width: 16, height: 16)
                Text(state.title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
            }
            Text(state.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let action = state.action {
                PlannerPillButton(title: state.actionTitle, help: state.actionHelp) { perform(action) }
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        // Centered in the space under the caption, nudged up so it sits
        // near the card's optical middle instead of hanging off the top.
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
