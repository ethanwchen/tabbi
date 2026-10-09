import SwiftUI
import TabbiKitCore
import TabbiKit

/// The End-of-Day Review, shown in place of the checklist: a header with
/// Done, the AI's short summary (a shimmer until it arrives) over today's
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
                    DayReviewStats(stats: DayReviewer.stats(for: review))
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
            .motion(Theme.Motion.content, value: review)
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
                .foregroundStyle(TodayModule.descriptor.accentColor)
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
                            .foregroundStyle(isDone ? TodayModule.descriptor.accentColor : Theme.Palette.tertiaryText)
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

/// Today's figures in one caption row: study or focus time, shared goals
/// such as cards reviewed, and points earned.
private struct DayReviewStats: View {
    let stats: [DayReviewStat]

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                // Tighter than `Label` so four figures fit the column.
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: stat.symbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(stat.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // The first figure (study time) gives way before the short counts.
                .layoutPriority(index == 0 ? 0 : 1)
                .help(stat.help)
            }
        }
        .font(Theme.Typography.caption.monospacedDigit())
        .foregroundStyle(Theme.Palette.tertiaryText)
    }
}

/// Two placeholder lines where the summary goes, with the shared skeleton
/// shimmer while the AI writes.
private struct DayReviewShimmer: View {
    private static let widths: [CGFloat] = [0.92, 0.6]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Self.widths.indices, id: \.self) { index in
                SkeletonLine(fraction: Self.widths[index])
            }
        }
        .padding(.top, Theme.Spacing.xs)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Writing a summary")
        .help("Writing a short summary of your day")
    }
}
