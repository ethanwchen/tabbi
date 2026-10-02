import SwiftUI
import NotchKitCore
import NotchKit

/// The End-of-Day Review, shown in place of the checklist: a header with
/// Done, Claude's short summary (a shimmer until it arrives) over today's
/// focus time, and what got done beside what carries over to tomorrow.
struct DayReviewView: View {
    @ObservedObject var store: DayReviewStore

    var body: some View {
        if let review = store.review {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                DayReviewHeader(store: store, review: review)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    summary(review)
                    // Pinned above the lists so it doesn't move when the summary arrives.
                    Spacer(minLength: 0)
                    Label(DayReviewFormat.focus(review), systemImage: "scope")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                        .help("Focus sessions completed today")
                }
                .padding(.horizontal, Theme.Spacing.s)
                .frame(maxHeight: .infinity, alignment: .top)
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    DayReviewList(title: "Done", titles: review.done, isDone: true,
                                  emptyText: "Nothing checked off")
                    DayReviewList(title: "Tomorrow", titles: review.carryingOver, isDone: false,
                                  emptyText: "Nothing carries over")
                }
                .padding(.horizontal, Theme.Spacing.s)
            }
            .animation(Theme.Motion.content, value: review)
        }
    }

    @ViewBuilder
    private func summary(_ review: DayReview) -> some View {
        if let text = review.summary {
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(3)
                .lineSpacing(Theme.Spacing.xxs)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(text)
                .transition(.opacity)
        } else {
            DayReviewShimmer()
                .transition(.opacity)
        }
    }
}

// MARK: Header

private struct DayReviewHeader: View {
    @ObservedObject var store: DayReviewStore
    let review: DayReview

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent(for: .planner))
                .symbolEffect(.pulse, isActive: store.isSummarizing)
                .frame(width: 20)
            Text("Wrap-up")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Theme.Spacing.s)
            if store.saveFailed {
                Label("Not saved", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warning)
                    .lineLimit(1)
                    .help("The review couldn't be written to disk. Try Done again.")
            }
            PlannerPillButton(title: "Done", isProminent: true,
                              help: "Save today's review and show the checklist") {
                store.done()
            }
        }
        .frame(height: 20)
        .padding(.horizontal, Theme.Spacing.s)
    }
}

// MARK: Lists

/// A short titled list of task names. Shows up to three rows, ending in
/// "+N more" when there are more, with the full list in the tooltip.
private struct DayReviewList: View {
    let title: String
    let titles: [String]
    let isDone: Bool
    let emptyText: String

    private static let visibleRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                Text("\(titles.count)").monospacedDigit()
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.tertiaryText)

            if titles.isEmpty {
                Text(emptyText)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
            } else {
                ForEach(shown, id: \.offset) { _, title in
                    HStack(spacing: Theme.Spacing.xs + Theme.Spacing.xxs) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "arrow.turn.down.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(isDone ? Theme.Palette.accent(for: .planner) : Theme.Palette.tertiaryText)
                            .frame(width: 12)
                        Text(title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(isDone ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if hidden > 0 {
                    Text("+\(hidden) more")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .padding(.leading, 12 + Theme.Spacing.xs + Theme.Spacing.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .help(titles.isEmpty ? emptyText : titles.joined(separator: "\n"))
    }

    /// Leaves the last row for "+N more" when the list overflows.
    private var shown: [(offset: Int, element: String)] {
        let limit = titles.count > Self.visibleRows ? Self.visibleRows - 1 : Self.visibleRows
        return Array(titles.prefix(limit).enumerated())
    }

    private var hidden: Int { titles.count - shown.count }
}

/// Two placeholder lines with a soft highlight sweeping across while Claude writes.
private struct DayReviewShimmer: View {
    @State private var phase: CGFloat = -1

    private static let widths: [CGFloat] = [0.92, 0.6]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Self.widths.indices, id: \.self) { index in
                GeometryReader { proxy in
                    Capsule().frame(width: proxy.size.width * Self.widths[index], height: 8)
                }
                .frame(height: 8)
            }
        }
        .padding(.top, Theme.Spacing.xs)
        .foregroundStyle(Theme.Palette.surfaceHover)
        .overlay {
            GeometryReader { proxy in
                LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 0.5)
                    .offset(x: proxy.size.width * phase)
            }
            .allowsHitTesting(false)
        }
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.5 }
        }
        .help("Claude is writing a short summary of your day")
    }
}

enum DayReviewFormat {
    /// "3 focus sessions · 1h 15m", or "No focus sessions today".
    static func focus(_ review: DayReview) -> String {
        guard review.focusSessions > 0 else { return "No focus sessions today" }
        let minutes = review.focusMinutes
        let time = minutes < 60 ? "\(minutes)m" : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m")
        let sessions = review.focusSessions == 1 ? "1 focus session" : "\(review.focusSessions) focus sessions"
        return "\(sessions) · \(time)"
    }
}
