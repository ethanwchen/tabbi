import Foundation

/// Everything the Anki card shows, aggregated from a handful of
/// AnkiConnect replies. Built by the pure `init(deckStats:...)` so the math
/// is testable without a transport; `AnkiConnectClient.summary` fetches it.
public struct AnkiSummary: Hashable, Sendable, Codable {
    /// Due today, summed over top-level decks only (Anki rolls children up).
    public let newDue: Int
    public let learnDue: Int
    public let reviewDue: Int
    /// Reviews (button presses) since today's rollover.
    public let reviewedToday: Int
    /// Consecutive days with at least one review, ending today, or ending
    /// yesterday when today has no reviews yet (the streak is still alive).
    public let streak: Int
    /// One entry per day, oldest first, ending today, zero-filled.
    public let history: [AnkiDayCount]
    /// True retention over `retentionWindowDays`: the share of review-card
    /// answers that were not Again. Nil when there are too few reviews to say.
    public let retention: Double?
    /// How many review answers `retention` is based on.
    public let retentionSampleSize: Int
    /// Time spent answering today's reviews in the fetched decks.
    public let studyTimeToday: TimeInterval
    /// Per-deck counts, in the order given.
    public let decks: [AnkiDeckStats]

    /// Days of history kept for the sparkline.
    public static let defaultHistoryDays = 14
    /// Window for the retention estimate.
    public static let defaultRetentionWindowDays = 30
    /// Below this many answers a retention percentage is mostly noise.
    public static let minimumRetentionSample = 20

    public var dueTotal: Int { newDue + learnDue + reviewDue }

    /// Whether at least one card has been answered today.
    public var hasReviewedToday: Bool { reviewedToday > 0 }

    /// Aggregates raw AnkiConnect data.
    /// - Parameters:
    ///   - deckStats: `getDeckStats` for any set of decks; a deck whose
    ///     ancestor is also present is left out of the totals.
    ///   - reviewedToday: `getNumCardsReviewedToday`.
    ///   - reviewsByDay: `getNumCardsReviewedByDay`, any order.
    ///   - reviews: `cardReviews` rows from any decks; duplicates are ignored.
    ///   - now: the current instant, for the retention window.
    ///   - today: the current Anki day (already shifted by the rollover hour).
    public init(
        deckStats: [AnkiDeckStats],
        reviewedToday: Int,
        reviewsByDay: [AnkiDayCount],
        reviews: [AnkiReview],
        now: Date,
        today: AnkiDay,
        rolloverHour: Int = 4,
        calendar: Calendar = .current,
        historyDays: Int = AnkiSummary.defaultHistoryDays,
        retentionWindowDays: Int = AnkiSummary.defaultRetentionWindowDays
    ) {
        let roots = Self.rootDecks(deckStats)
        newDue = roots.reduce(0) { $0 + $1.newCount }
        learnDue = roots.reduce(0) { $0 + $1.learnCount }
        reviewDue = roots.reduce(0) { $0 + $1.reviewCount }
        decks = deckStats

        var counts: [AnkiDay: Int] = [:]
        for entry in reviewsByDay { counts[entry.day, default: 0] += entry.count }
        // The two actions are separate queries; trust the larger number for
        // today so a review landing between them never reads as zero.
        counts[today] = max(counts[today] ?? 0, reviewedToday)
        self.reviewedToday = counts[today] ?? 0

        history = (0..<max(historyDays, 0)).reversed().map { back in
            let day = today.adding(days: -back)
            return AnkiDayCount(day: day, count: counts[day] ?? 0)
        }

        var run = 0
        var day = (counts[today] ?? 0) > 0 ? today : today.adding(days: -1)
        while (counts[day] ?? 0) > 0 {
            run += 1
            day = day.adding(days: -1)
        }
        streak = run

        var seen = Set<Int64>()
        let unique = reviews.filter { seen.insert($0.id).inserted }
        let windowStart = now.addingTimeInterval(-TimeInterval(retentionWindowDays) * 86_400)
        let graded = unique.filter { $0.kind == .review && $0.ease > 0 && $0.reviewedAt >= windowStart && $0.reviewedAt <= now }
        retentionSampleSize = graded.count
        if graded.count >= Self.minimumRetentionSample {
            let failures = graded.filter(\.isFailure).count
            retention = 1 - Double(failures) / Double(graded.count)
        } else {
            retention = nil
        }

        let todaysReviews = unique.filter { AnkiDay(date: $0.reviewedAt, rolloverHour: rolloverHour, calendar: calendar) == today }
        studyTimeToday = TimeInterval(todaysReviews.reduce(0) { $0 + $1.durationMilliseconds }) / 1000
    }

    /// Decks with no ancestor in the list. `getDeckStats` already includes
    /// children in a parent's counts, so summing both would double count.
    static func rootDecks(_ stats: [AnkiDeckStats]) -> [AnkiDeckStats] {
        let names = Set(stats.map(\.name))
        var seenIDs = Set<Int64>()
        return stats.filter { deck in
            guard seenIDs.insert(deck.deckID).inserted else { return false }
            let parts = deck.name.components(separatedBy: "::")
            return !(1..<max(parts.count, 1)).contains { names.contains(parts.prefix($0).joined(separator: "::")) }
        }
    }
}

extension AnkiSummary {
    /// Realistic sample data for `TABBI_DEMO=1`: a Step 1 student with a
    /// 12-day streak, built through the real aggregation so it stays honest.
    public static func demo(now: Date = Date(), rolloverHour: Int = 4, calendar: Calendar = .current) -> AnkiSummary {
        let today = AnkiDay(date: now, rolloverHour: rolloverHour, calendar: calendar)
        let stats = [
            AnkiDeckStats(deckID: 1, name: "AnKing Step 1", newCount: 30, learnCount: 12, reviewCount: 186, totalInDeck: 28_000),
            AnkiDeckStats(deckID: 2, name: "AnKing Step 1::Cardio", newCount: 10, learnCount: 4, reviewCount: 61, totalInDeck: 3_100),
            AnkiDeckStats(deckID: 7, name: "AnKing Step 1::Renal", newCount: 8, learnCount: 3, reviewCount: 44, totalInDeck: 2_400),
            AnkiDeckStats(deckID: 8, name: "AnKing Step 1::Renal::Acid Base", newCount: 0, learnCount: 1, reviewCount: 12, totalInDeck: 380),
            AnkiDeckStats(deckID: 3, name: "Pharm Sketchy", newCount: 15, learnCount: 3, reviewCount: 74, totalInDeck: 4_200),
            AnkiDeckStats(deckID: 9, name: "Pharm Sketchy::Antibiotics", newCount: 5, learnCount: 1, reviewCount: 26, totalInDeck: 900),
            AnkiDeckStats(deckID: 4, name: "Sketchy Micro", newCount: 0, learnCount: 2, reviewCount: 58, totalInDeck: 2_900),
            AnkiDeckStats(deckID: 5, name: "Pathoma", newCount: 5, learnCount: 0, reviewCount: 22, totalInDeck: 1_400),
            AnkiDeckStats(deckID: 6, name: "Boards and Beyond Biochem", newCount: 0, learnCount: 1, reviewCount: 17, totalInDeck: 1_100),
        ]
        // Oldest to newest; a missed day 12 days ago ends the earlier run.
        let counts = [180, 0, 240, 310, 205, 410, 380, 290, 455, 320, 365, 280, 430, 112]
        let byDay = counts.enumerated().map { offset, count in
            AnkiDayCount(day: today.adding(days: offset - (counts.count - 1)), count: count)
        }
        // 120 graded reviews today, 11 of them Again: about 91% retention.
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let reviews = (0..<120).map { (index: Int) -> AnkiReview in
            let ease = index % 11 == 0 ? 1 : 3
            return AnkiReview(
                id: nowMs - Int64(index) * 20_000, cardID: Int64(1_000 + index), ease: ease,
                interval: 12, lastInterval: 5, factor: 2500, durationMilliseconds: 8_000, kind: .review
            )
        }
        return AnkiSummary(
            deckStats: stats, reviewedToday: counts.last ?? 0, reviewsByDay: byDay, reviews: reviews,
            now: now, today: today, rolloverHour: rolloverHour, calendar: calendar
        )
    }
}

extension AnkiConnectClient {
    /// Fetches everything `AnkiSummary` needs: due counts for every deck,
    /// today's count, the per-day history, and the review log for the
    /// retention window. `cardReviews` does not include child decks, so every
    /// deck is asked for, batched into a single `multi` request.
    public func summary(
        now: Date = Date(),
        rolloverHour: Int = 4,
        calendar: Calendar = .current,
        historyDays: Int = AnkiSummary.defaultHistoryDays,
        retentionWindowDays: Int = AnkiSummary.defaultRetentionWindowDays
    ) async throws -> AnkiSummary {
        let allDecks = try await decks()
        let names = allDecks.map(\.name)
        let stats = try await deckStats(for: names)
        let reviewedToday = try await numCardsReviewedToday()
        let byDay = try await numCardsReviewedByDay()

        let startID = Int64((now.timeIntervalSince1970 - TimeInterval(retentionWindowDays) * 86_400) * 1000)
        let reviews = try await cardReviews(decks: names, startID: startID)

        return AnkiSummary(
            deckStats: stats,
            reviewedToday: reviewedToday,
            reviewsByDay: byDay,
            reviews: reviews,
            now: now,
            today: AnkiDay(date: now, rolloverHour: rolloverHour, calendar: calendar),
            rolloverHour: rolloverHour,
            calendar: calendar,
            historyDays: historyDays,
            retentionWindowDays: retentionWindowDays
        )
    }
}

extension AnkiSummary {
    /// Today's reviews as a shared progress goal: cards reviewed so far out
    /// of those plus the cards still due. Today and the ticker show it
    /// without knowing it came from Anki.
    public func progressItem(source: ModuleID = .anki) -> ProgressItem {
        ProgressItem(id: "reviews", source: source, title: "Anki reviews",
                     completed: reviewedToday, target: reviewedToday + dueTotal, unit: "cards")
    }
}
