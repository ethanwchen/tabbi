import SwiftUI
import TabbiKitCore
import TabbiKit

/// Onboarding's calendar step: what Today does with the calendar, one tap
/// to allow access (or the way back to it when it's off), and beside it the
/// day as Up next will show it. Before access it shows the kit's sample day,
/// marked as an example, so the step explains itself.
struct TodayCalendarSetupView: View {
    @ObservedObject var store: PlannerStore

    var body: some View {
        TodayCalendarSetupContent(upNext: store.upNext, settings: store.planSettings)
    }
}

private var accent: Color { TodayModule.descriptor.accentColor }

private struct TodayCalendarSetupContent: View {
    @ObservedObject var upNext: UpNextStore
    let settings: TodayPlanSettings

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: statusSymbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(accent.opacity(0.16)))
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Today's calendar")
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.primaryText)
                            Text(statusText)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(upNext.access == .granted ? accent : Theme.Palette.secondaryText)
                                .contentTransition(.opacity)
                        }
                        .lineLimit(1)
                    }
                    Text("Up next shows your \(settings.upNextEvents) as the day goes, and Plan my day fits work around them.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack(spacing: Theme.Spacing.s) {
                        action
                        Spacer(minLength: 0)
                        Label("Stays on this Mac", systemImage: "lock.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .labelStyle(TodayCalendarSetupLabelStyle())
                            .lineLimit(1)
                            .help("\(Edition.current.name) reads your events on this Mac and never uploads them")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 252)
            Card(padding: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Up next")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                        Spacer(minLength: 0)
                        if !showsRealDay {
                            Text("Example")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                                .padding(.horizontal, Theme.Spacing.xs + Theme.Spacing.xxs)
                                .frame(height: 16)
                                .background(Capsule().fill(Theme.Palette.surface))
                                .help("A sample day. Your own events show here once the calendar is connected.")
                        }
                    }
                    .frame(height: 16)
                    .padding(.horizontal, Theme.Spacing.xs)
                    day
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .motion(Theme.Motion.content, value: upNext.access)
        .motion(Theme.Motion.content, value: upNext.events)
        // Visible like the panel, so access and events are read fresh.
        .onAppear { upNext.setVisible(true) }
        .onDisappear { upNext.setVisible(false) }
    }

    /// The user's own day once access is on; a sample day before.
    private var showsRealDay: Bool { upNext.access == .granted }

    @ViewBuilder private var day: some View {
        if showsRealDay, let situation = upNext.emptySituation {
            let state = UpNextEmptyState(situation, upNextEvents: settings.upNextEvents, appName: Edition.current.name)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
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
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.top, Theme.Spacing.xs)
        } else {
            let events = showsRealDay ? upNext.events : sampleEvents
            VStack(spacing: 0) {
                ForEach(events) { event in
                    UpNextRow(event: event, now: upNext.now) { upNext.join($0) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .opacity(showsRealDay ? 1 : 0.6)
            .allowsHitTesting(showsRealDay)
        }
    }

    private var sampleEvents: [UpcomingEvent] {
        UpcomingEvent.upNext(from: UpcomingEvent.samples(now: upNext.now, kind: settings.sampleDay), at: upNext.now)
    }

    @ViewBuilder private var action: some View {
        switch upNext.access {
        case .notDetermined:
            PlannerPillButton(title: "Allow Access", symbol: "calendar", isProminent: true, height: 24,
                              help: "Allow \(Edition.current.name) to read your calendars. macOS asks once.") {
                Task { _ = await upNext.ensureAccess() }
            }
        case .denied:
            PlannerPillButton(title: "Open Settings", symbol: "gear", height: 24,
                              help: "Open Calendars privacy settings to turn access on") {
                upNext.openPrivacySettings()
            }
        case .granted where upNext.emptySituation == .noAccounts:
            PlannerPillButton(title: "Internet Accounts", symbol: "person.crop.circle.badge.plus", height: 24,
                              help: "Open Internet Accounts to add a Google, Exchange or iCloud calendar") {
                upNext.openInternetAccounts()
            }
        case .granted, .unavailable:
            EmptyView()
        }
    }

    private var statusSymbol: String {
        switch upNext.access {
        case .granted: "calendar.badge.checkmark"
        case .denied: "calendar.badge.exclamationmark"
        case .notDetermined, .unavailable: "calendar"
        }
    }

    private var statusText: String {
        switch upNext.access {
        case .notDetermined: "Not connected"
        case .granted: "Connected"
        case .denied: "Access is off"
        case .unavailable: "Open the \(Edition.current.name) app to connect"
        }
    }
}

/// A compact label: the icon close to its text.
private struct TodayCalendarSetupLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs + 1) {
            configuration.icon.font(.system(size: 8.5, weight: .bold))
            configuration.title
        }
    }
}
