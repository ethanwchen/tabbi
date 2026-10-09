import SwiftUI
import TabbiKitCore
import TabbiKit

/// Plan My Day, shown in place of the checklist: a header with the plan's
/// actions over the proposed blocks, a shimmer while Claude thinks, or a
/// short message with Retry when something went wrong.
struct DayPlanView: View {
    @ObservedObject var plan: DayPlanStore

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            DayPlanHeader(plan: plan)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .motion(Theme.Motion.content, value: plan.phase)
        .motion(Theme.Motion.content, value: plan.isRefining)
    }

    @ViewBuilder
    private var content: some View {
        switch plan.phase {
        case .idle:
            EmptyView()
        case .planning:
            DayPlanShimmer(help: plan.settings.planMode == .claude
                           ? "Claude is fitting your tasks around today's events"
                           : "Fitting your work and breaks around today's events")
                .transition(.opacity)
        case .proposal(let proposal):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(proposal.pending) { block in
                    DayPlanBlockRow(block: block, rest: proposal.breakAfter(block),
                                    add: { withMotion(Theme.Motion.snappy) { plan.add(block.id) } },
                                    dismiss: { withMotion(Theme.Motion.snappy) { plan.dismiss(block.id) } })
                        .transition(.motionRow(from: .leading))
                }
                .disabled(plan.isRefining)
                .opacity(plan.isRefining ? 0.5 : 1)
                Spacer(minLength: Theme.Spacing.xs)
                DayPlanFooter(plan: plan, proposal: proposal)
            }
        case .noFreeTime:
            PlannerMessage(symbol: "moon.stars.fill", tint: TodayModule.descriptor.accentColor,
                           title: "Nothing left to plan",
                           detail: "There's no free time worth a block before the evening.")
                .frame(maxHeight: .infinity)
        case .failed(let failure):
            PlannerMessage(symbol: "exclamationmark.triangle.fill", tint: Theme.Palette.warning,
                           title: failure.title, detail: failure.detail) {
                if failure.canRetry {
                    PlannerPillButton(title: "Retry", symbol: "arrow.clockwise", help: "Ask Claude again") {
                        plan.retry()
                    }
                } else if failure.opensConnections {
                    PlannerPillButton(title: failure == .claudeNotFound ? "Set up Claude" : "Connect calendar",
                                      symbol: "link", help: "Open Connections to finish setting this up") {
                        ConnectionsStore.shared.showHub()
                    }
                } else if failure == .calendarOff {
                    PlannerPillButton(title: "Open Settings", symbol: "gearshape",
                                      help: "Open Privacy & Security to allow Calendar access") {
                        plan.openPrivacySettings()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: Header

private struct DayPlanHeader: View {
    @ObservedObject var plan: DayPlanStore

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TodayModule.descriptor.accentColor)
                .symbolEffect(.pulse, isActive: plan.phase == .planning || plan.isRefining)
                .frame(width: 20)
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            if plan.writeFailed {
                Label("Not added", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warning)
                    .lineLimit(1)
                    .help("The calendar didn't accept the events. Check Calendar access and try again.")
            }
            PlannerTextButton(title: isFinal ? "Done" : "Cancel",
                              help: isFinal ? "Back to the checklist" : "Discard the plan and show the checklist") {
                plan.cancel()
            }
            if case .proposal = plan.phase {
                PlannerPillButton(title: "Add all", symbol: "calendar.badge.plus", isProminent: true,
                                  help: "Add every block to your default calendar") {
                    withMotion(Theme.Motion.snappy) { plan.add() }
                }
                .disabled(plan.isRefining)
                .opacity(plan.isRefining ? 0.5 : 1)
                .transition(.motionPop)
            }
        }
        .frame(height: 20)
        .padding(.horizontal, Theme.Spacing.s)
    }

    private var title: String {
        switch plan.phase {
        case .planning: "Planning your day…"
        case .proposal: "Your plan"
        default: "Plan my day"
        }
    }

    /// Nothing to discard, so the way out reads as "Done".
    private var isFinal: Bool { plan.phase == .noFreeTime }
}

// MARK: Footer

/// The caption under the rows (where blocks go, what happened so far) and
/// the optional "Refine with Claude", offered once per on-device plan.
private struct DayPlanFooter: View {
    @ObservedObject var plan: DayPlanStore
    let proposal: DayPlanProposal

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(caption)
                .font(Theme.Typography.caption)
                .foregroundStyle(plan.refineFailed ? Theme.Palette.warning : Theme.Palette.tertiaryText)
                .lineLimit(1)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsRefine {
                PlannerPillButton(title: "Refine", symbol: "wand.and.stars",
                                  help: "Refine with Claude: ask Claude for suggestions on this plan (optional)") {
                    plan.refine()
                }
                .transition(.opacity)
            }
        }
        .frame(height: 20)
        // Lines up with the time column.
        .padding(.leading, Theme.Spacing.s + 20 + Theme.Spacing.s)
        .padding(.trailing, Theme.Spacing.s)
    }

    private var caption: String {
        if plan.isRefining { return "Claude is looking over this plan…" }
        if plan.refineFailed { return "Claude couldn't refine it. This plan still works." }
        return DayPlanFormat.footer(proposal)
    }

    private var showsRefine: Bool {
        plan.canRefine && !plan.isRefining && !plan.refineFailed && proposal.refinement == nil
    }
}

// MARK: Rows

/// One proposed block: a kind marker, the time range, the title, the break
/// that follows it, and buttons to add it to the calendar or drop it.
private struct DayPlanBlockRow: View {
    let block: PlanBlock
    /// The planned rest before the next block, if any.
    let rest: DateInterval?
    let add: () -> Void
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            DayPlanKindMarker(kind: block.kind)
            Text(DayPlanFormat.range(block))
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .frame(width: DayPlanFormat.rangeWidth, alignment: .leading)
            Text(block.title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(block.title)
            if let rest {
                DayPlanBreakLabel(rest: rest)
                    .transition(.opacity)
            }
            HStack(spacing: Theme.Spacing.xxs) {
                DayPlanRowButton(symbol: "checkmark", tint: TodayModule.descriptor.accentColor, isTinted: true,
                                 help: "Add this block to your calendar", action: add)
                DayPlanRowButton(symbol: "xmark", tint: Theme.Palette.danger,
                                 help: "Leave this block out", action: dismiss)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: PlannerList.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering ? Theme.Palette.surface : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The leading marker: a symbol for review and study blocks, so the
/// day's rhythm reads at a glance, or the plain accent tick for Claude's
/// focus blocks.
private struct DayPlanKindMarker: View {
    let kind: PlanBlockKind

    var body: some View {
        Group {
            if let symbol = DayPlanFormat.symbol(for: kind) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .help(kind == .reviews ? "Review block" : "Study block")
            } else {
                Capsule().frame(width: 3, height: 14)
            }
        }
        .foregroundStyle(TodayModule.descriptor.accentColor)
        .frame(width: 20)
    }
}

/// The rest after a block, in quiet metadata type: a cup and "5m".
private struct DayPlanBreakLabel: View {
    let rest: DateInterval

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(DayPlanFormat.breakLength(rest))
                .font(Theme.Typography.caption.monospacedDigit())
        }
        .foregroundStyle(Theme.Palette.tertiaryText)
        .lineLimit(1)
        .fixedSize()
        .help("Then a break until \(UpcomingEventFormat.startTime(rest.end))")
    }
}

private struct DayPlanRowButton: View {
    let symbol: String
    let tint: Color
    /// Shows the tint at rest too, for the positive action.
    var isTinted = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering || isTinted ? tint : Theme.Palette.tertiaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? tint.opacity(0.16) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Placeholder rows shaped like proposal rows (stripe, time, title), with
/// the shared skeleton shimmer while Claude plans.
private struct DayPlanShimmer: View {
    let help: String

    private static let widths: [CGFloat] = [0.72, 0.54, 0.64]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.widths.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.s) {
                    SkeletonLine(width: 3, height: 14).frame(width: 20)
                    SkeletonLine(width: DayPlanFormat.rangeWidth - Theme.Spacing.s)
                    SkeletonLine(fraction: Self.widths[index])
                }
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: PlannerList.rowHeight)
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planning")
        .help(help)
    }
}

/// Time labels for proposal rows, in the user's clock style.
enum DayPlanFormat {
    /// Fits "10:45–11:30" in the caption font.
    static let rangeWidth: CGFloat = 76

    /// Review and study blocks get a symbol; Claude's focus blocks don't.
    static func symbol(for kind: PlanBlockKind) -> String? {
        switch kind {
        case .focus: nil
        case .reviews: "rectangle.stack.fill"
        case .study: "book.fill"
        }
    }

    /// "5 min", "17 min", "1h 30m", the same style as every other duration.
    static func breakLength(_ rest: DateInterval) -> String {
        DurationFormat.minutes(Int((rest.duration / 60).rounded()))
    }

    static func range(_ block: PlanBlock) -> String {
        "\(UpcomingEventFormat.startTime(block.start))–\(UpcomingEventFormat.startTime(block.end))"
    }

    /// The caption under the rows: where blocks go, then what happened to
    /// the ones accepted so far, including any that no longer fit.
    static func footer(_ proposal: DayPlanProposal) -> String {
        var parts: [String] = []
        if proposal.addedCount > 0 { parts.append("\(proposal.addedCount) added to your calendar") }
        if proposal.skippedCount > 0 { parts.append("\(proposal.skippedCount) no longer fit") }
        guard parts.isEmpty else { return parts.joined(separator: " · ") }
        switch proposal.refinement {
        case .changed: return "Refined with Claude."
        case .unchanged: return "Claude suggests no changes."
        case nil: return "Blocks go to your calendar."
        }
    }
}

// MARK: Shared controls

/// Capsule button for the Today panel's calls to action. Prominent ones are
/// filled with the accent; the rest are tinted.
struct PlannerPillButton: View {
    let title: String
    var symbol: String?
    var isProminent = false
    var height: CGFloat = 22
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = TodayModule.descriptor.accentColor
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                }
                Text(title).font(Theme.Typography.caption)
            }
            .foregroundStyle(isProminent ? Theme.Palette.background : accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
            .frame(height: height)
            .background(Capsule().fill(isProminent ? accent.opacity(hovering ? 1 : 0.9)
                                       : accent.opacity(hovering ? 0.28 : 0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Quiet text button for secondary actions such as Cancel.
struct PlannerTextButton: View {
    let title: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 20)
                .background(Capsule().fill(hovering ? Theme.Palette.surface : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
