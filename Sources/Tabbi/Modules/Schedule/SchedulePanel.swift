import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Schedule panel: a header with the date and today's free time, the
/// day's timeline (events, planned blocks, now-line), and a line under it
/// with what is on now or the details of the block tapped.
struct SchedulePanel: View {
    @ObservedObject var store: ScheduleStore

    var body: some View {
        let layout = store.dayLayout
        VStack(spacing: Theme.Spacing.s) {
            ScheduleHeader(layout: layout, now: store.now, showsFreeTime: store.emptySituation == nil)
            if let situation = store.emptySituation {
                ScheduleAccessMessage(situation: situation, store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScheduleTimeline(layout: layout, now: store.now, selectedID: store.selectedID) { store.select($0) }
                    .frame(maxHeight: .infinity)
                ScheduleDetailStrip(layout: layout, now: store.now, selected: store.selectedItem,
                                    join: { store.join($0) }, close: { store.select(nil) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .motion(Theme.Motion.content, value: store.emptySituation)
        .motion(Theme.Motion.snappy, value: store.selectedID)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }
}

private var accent: Color { ScheduleModule.descriptor.accentColor }

/// "Today" with the date, then the free time left and any all-day events.
private struct ScheduleHeader: View {
    let layout: ScheduleDayLayout
    let now: Date
    let showsFreeTime: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text("Today")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
            Text(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
            Spacer(minLength: Theme.Spacing.s)
            ForEach(layout.allDay.prefix(1)) { item in
                Label(ScheduleFormat.title(item), systemImage: "sun.max")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .help("All day: \(ScheduleFormat.title(item))")
            }
            if showsFreeTime {
                Text(layout.freeMinutes > 0 ? "\(ScheduleFormat.duration(minutes: layout.freeMinutes)) free"
                                            : "No free time left")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(layout.freeMinutes > 0 ? accent : Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Free time left in your working day, with a buffer around each event")
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }
}

/// Hour marks across the top and the day's items below them, stacked in
/// rows where they overlap, with a line at the current time.
private struct ScheduleTimeline: View {
    let layout: ScheduleDayLayout
    let now: Date
    let selectedID: ScheduleItem.ID?
    let select: (ScheduleItem.ID) -> Void

    private static let labelHeight: CGFloat = 16
    private static let laneGap: CGFloat = 2

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let trackHeight = max(geometry.size.height - Self.labelHeight, 24)
                let hourWidth = width / CGFloat(max(layout.hours.count - 1, 1))
                // Every hour when there's room for its label, else every other one.
                let labelEvery = hourWidth >= 34 ? 1 : 2
                ZStack(alignment: .topLeading) {
                    if let nowX = layout.position(of: now) {
                        // The past is dimmed so what's left of the day stands out.
                        Rectangle()
                            .fill(Theme.Palette.background.opacity(0.35))
                            .frame(width: width * nowX, height: trackHeight)
                            .offset(y: Self.labelHeight)
                    }
                    ForEach(Array(layout.hours.enumerated()), id: \.offset) { index, hour in
                        let x = width * (layout.position(of: hour) ?? 1)
                        Rectangle()
                            .fill(Theme.Palette.stroke)
                            .frame(width: 1, height: trackHeight)
                            .offset(x: x, y: Self.labelHeight)
                        if index % labelEvery == 0, index < layout.hours.count - 1 {
                            Text(hour.formatted(.dateTime.hour()))
                                .font(Theme.Typography.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.tertiaryText)
                                .lineLimit(1)
                                .fixedSize()
                                .offset(x: x + 3, y: -1)
                        }
                    }
                    ForEach(layout.placed) { placed in
                        let laneHeight = (trackHeight - CGFloat(placed.lanes - 1) * Self.laneGap)
                            / CGFloat(placed.lanes)
                        ScheduleBlock(item: placed.item, isPast: placed.item.end <= now,
                                      isSelected: placed.id == selectedID, height: laneHeight) {
                            select(placed.id)
                        }
                        .frame(width: max(width * placed.width - 1, 3), height: laneHeight)
                        .offset(x: width * placed.x + 0.5,
                                y: Self.labelHeight + CGFloat(placed.lane) * (laneHeight + Self.laneGap))
                    }
                    if let nowX = layout.position(of: now) {
                        ScheduleNowLine(height: trackHeight + 4)
                            .offset(x: width * nowX - 3, y: Self.labelHeight - 4)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

/// One event or planned block. Events take their calendar's color; planned
/// blocks are outlined in the module's accent.
private struct ScheduleBlock: View {
    let item: ScheduleItem
    let isPast: Bool
    let isSelected: Bool
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.s - 2, style: .continuous)
        Button(action: action) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(color).frame(width: 2.5)
                    if geometry.size.width >= 40 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ScheduleFormat.title(item))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.primaryText)
                                .lineLimit(height >= 48 ? 2 : 1)
                            if height >= 34, geometry.size.width >= 48 {
                                Text(UpcomingEventFormat.startTime(item.start))
                                    .font(Theme.Typography.caption.monospacedDigit())
                                    .foregroundStyle(Theme.Palette.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.top, height >= 20 ? 3 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: height >= 20 ? .topLeading : .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
            // An opaque base keeps the hour lines from showing through.
            .background(shape.fill(color.opacity(hovering || isSelected ? 0.42 : 0.28)))
            .background(shape.fill(Theme.Palette.background))
            .overlay {
                if item.kind == .planned {
                    shape.strokeBorder(color.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .overlay {
                if isSelected { shape.strokeBorder(Theme.Palette.primaryText, lineWidth: 1.5) }
            }
            .clipShape(shape)
            .opacity(isPast && !isSelected ? 0.5 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .help("\(ScheduleFormat.title(item)), \(ScheduleFormat.range(item.start, item.end))")
    }

    private var color: Color {
        if item.kind == .planned { return accent }
        guard let color = item.calendarColor else { return Theme.Palette.secondaryText }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

/// The current time: a dot above a thin line through the track.
private struct ScheduleNowLine: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Not the accent, which planned blocks already wear.
            Circle().fill(Theme.Palette.primaryText).frame(width: 6, height: 6)
            Rectangle().fill(Theme.Palette.primaryText).frame(width: 1.5, height: height - 6)
        }
        .frame(width: 6)
    }
}

/// Under the timeline: the tapped block's details, or what is on now.
private struct ScheduleDetailStrip: View {
    let layout: ScheduleDayLayout
    let now: Date
    let selected: ScheduleItem?
    let join: (MeetingLink) -> Void
    let close: () -> Void

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                if let selected {
                    details(selected)
                } else {
                    status
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
    }

    @ViewBuilder
    private func details(_ item: ScheduleItem) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(blockColor(item))
            .frame(width: 3, height: 28)
        VStack(alignment: .leading, spacing: 0) {
            Text(ScheduleFormat.title(item))
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.primaryText)
            Text(detailLine(item))
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        if let link = item.meetingLink {
            ScheduleJoinButton(link: link) { join(link) }
        }
        IconButton(symbol: "xmark", size: 22, help: "Close details", action: close)
    }

    private var status: some View {
        let status = layout.status(at: now)
        return HStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol(status))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)
            Text(ScheduleFormat.status(status, now: now))
                .font(Theme.Typography.body.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if layout.placed.isEmpty {
                Text("Nothing on your calendar today")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private func symbol(_ status: ScheduleDayLayout.Status) -> String {
        switch status {
        case .busy: "record.circle"
        case .free: "leaf"
        case .dayOver: "moon.stars"
        }
    }

    private func detailLine(_ item: ScheduleItem) -> String {
        var parts = [ScheduleFormat.range(item.start, item.end), ScheduleFormat.duration(minutes: item.minutes)]
        if item.kind == .planned { parts.append(item.reason ?? "Planned with \(Edition.current.name)") }
        return parts.joined(separator: ", ")
    }

    private func blockColor(_ item: ScheduleItem) -> Color {
        guard item.kind == .event, let color = item.calendarColor else {
            return item.kind == .planned ? accent : Theme.Palette.secondaryText
        }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

/// A small "Join" pill for an event with a video-call link.
private struct ScheduleJoinButton: View {
    let link: MeetingLink
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label("Join", systemImage: "video.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(accent)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 22)
                .background(Capsule().fill(accent.opacity(hovering ? 0.28 : 0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Join \(link.provider.displayName) call")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Why there's no timeline yet (access not asked, off, or unavailable), with
/// the one action that fixes it.
private struct ScheduleAccessMessage: View {
    let situation: UpNextEmptyState.Situation
    @ObservedObject var store: ScheduleStore
    @State private var hovering = false

    var body: some View {
        let state = Self.state(for: situation)
        Card {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: state.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(height: 22)
                Text(state.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(state.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 340)
                if let action = state.action {
                    Button { perform(action) } label: {
                        Text(state.actionTitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.background)
                            .padding(.horizontal, Theme.Spacing.m)
                            .frame(height: 24)
                            .background(Capsule().fill(accent.opacity(hovering ? 1 : 0.9)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(state.actionHelp)
                    .onHover { hovering = $0 }
                    .motion(Theme.Motion.snappy, value: hovering)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Up next's states, with the first one worded for a whole day.
    private static func state(for situation: UpNextEmptyState.Situation) -> UpNextEmptyState {
        var state = UpNextEmptyState(situation, upNextEvents: "events", appName: Edition.current.name)
        if situation == .notAsked {
            state.title = "See your day at a glance"
            state.detail = "Today's events and the free time between them. "
                + "Google calendars show up once added in Internet Accounts."
        }
        return state
    }

    private func perform(_ action: UpNextEmptyState.Action) {
        switch action {
        case .requestAccess: store.requestAccess()
        case .openPrivacySettings: store.openPrivacySettings()
        case .openInternetAccounts: store.openInternetAccounts()
        case .openConnections: ConnectionsStore.shared.showHub()
        }
    }
}
