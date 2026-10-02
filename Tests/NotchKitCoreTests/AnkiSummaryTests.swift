import XCTest
import NotchKitCore

/// Replays canned AnkiConnect replies keyed by action; `cardReviews` replies
/// are keyed by deck name.
private final class SummaryTransport: AnkiConnectTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let replies: [String: String]
    private let reviewsByDeck: [String: String]
    private var actions: [String] = []
    private var reviewParams: [[String: Any]] = []

    init(_ replies: [String: String], reviewsByDeck: [String: String] = [:]) {
        self.replies = replies
        self.reviewsByDeck = reviewsByDeck
    }

    var sentActions: [String] { lock.withLock { actions } }
    var sentReviewParams: [[String: Any]] { lock.withLock { reviewParams } }

    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        let action = object["action"] as? String ?? ""
        let params = object["params"] as? [String: Any] ?? [:]
        let text: String = lock.withLock {
            actions.append(action)
            if action == "multi" {
                // Like AnkiConnect: one inner `{result, error}` per batched action.
                let inner = (params["actions"] as? [[String: Any]] ?? []).map { item -> String in
                    actions.append(item["action"] as? String ?? "")
                    let itemParams = item["params"] as? [String: Any] ?? [:]
                    reviewParams.append(itemParams)
                    return reviewsByDeck[itemParams["deck"] as? String ?? ""] ?? #"{"result":[],"error":null}"#
                }
                return #"{"result":[\#(inner.joined(separator: ","))],"error":null}"#
            }
            return replies[action] ?? #"{"result":null,"error":"unsupported action"}"#
        }
        return AnkiConnectHTTPResponse(statusCode: 200, body: Data(text.utf8))
    }
}

final class AnkiSummaryTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-01 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_866_800)
    private let today = AnkiDay(year: 2026, month: 10, day: 1)

    private func stats(_ id: Int64, _ name: String, new: Int = 0, learn: Int = 0, review: Int = 0) -> AnkiDeckStats {
        AnkiDeckStats(deckID: id, name: name, newCount: new, learnCount: learn, reviewCount: review, totalInDeck: 100)
    }

    private func review(_ id: Int64, secondsAgo: TimeInterval, ease: Int = 3, kind: AnkiReview.Kind = .review, durationMs: Int = 5_000) -> AnkiReview {
        AnkiReview(
            id: Int64((now.timeIntervalSince1970 - secondsAgo) * 1000) + id % 1000,
            cardID: id, ease: ease, interval: 10, lastInterval: 4, factor: 2500,
            durationMilliseconds: durationMs, kind: kind
        )
    }

    private func summary(
        deckStats: [AnkiDeckStats] = [],
        reviewedToday: Int = 0,
        byDay: [AnkiDayCount] = [],
        reviews: [AnkiReview] = [],
        historyDays: Int = 14
    ) -> AnkiSummary {
        AnkiSummary(
            deckStats: deckStats, reviewedToday: reviewedToday, reviewsByDay: byDay, reviews: reviews,
            now: now, today: today, rolloverHour: 4, calendar: utc, historyDays: historyDays
        )
    }

    private func days(_ countsNewestFirst: [Int]) -> [AnkiDayCount] {
        countsNewestFirst.enumerated().map { AnkiDayCount(day: today.adding(days: -$0.offset), count: $0.element) }
    }

    // MARK: Due counts

    func testDueTotalsSumTopLevelDecksOnly() {
        let result = summary(deckStats: [
            stats(1, "Step1", new: 20, learn: 5, review: 100),
            stats(2, "Step1::Cardio", new: 8, learn: 2, review: 40),
            stats(3, "Step1::Cardio::Arrhythmia", new: 1, learn: 0, review: 9),
            stats(4, "Pharm", new: 10, learn: 1, review: 30),
        ])
        XCTAssertEqual(result.newDue, 30)
        XCTAssertEqual(result.learnDue, 6)
        XCTAssertEqual(result.reviewDue, 130)
        XCTAssertEqual(result.dueTotal, 166)
        XCTAssertEqual(result.decks.count, 4, "per-deck rows keep every deck")
    }

    func testChildCountsWhenItsParentIsNotFetched() {
        let result = summary(deckStats: [
            stats(2, "Step1::Cardio", new: 8, review: 40),
            stats(5, "Step1::Renal", new: 2, review: 10),
        ])
        XCTAssertEqual(result.dueTotal, 60)
    }

    func testSimilarlyPrefixedDeckIsNotTreatedAsAChild() {
        let result = summary(deckStats: [stats(1, "Step", review: 10), stats(2, "Step1", review: 5)])
        XCTAssertEqual(result.reviewDue, 15)
    }

    func testDuplicateDeckIsCountedOnce() {
        let result = summary(deckStats: [stats(1, "Step1", review: 10), stats(1, "Step1", review: 10)])
        XCTAssertEqual(result.reviewDue, 10)
    }

    func testEmptyCollection() {
        let result = summary()
        XCTAssertEqual(result.dueTotal, 0)
        XCTAssertEqual(result.reviewedToday, 0)
        XCTAssertFalse(result.hasReviewedToday)
        XCTAssertEqual(result.streak, 0)
        XCTAssertNil(result.retention)
        XCTAssertEqual(result.retentionSampleSize, 0)
        XCTAssertEqual(result.studyTimeToday, 0)
        XCTAssertEqual(result.history.count, 14)
        XCTAssertTrue(result.history.allSatisfy { $0.count == 0 })
    }

    // MARK: Today and history

    func testReviewedTodayTakesTheLargerOfTheTwoSources() {
        XCTAssertEqual(summary(reviewedToday: 50, byDay: days([42])).reviewedToday, 50)
        XCTAssertEqual(summary(reviewedToday: 40, byDay: days([42])).reviewedToday, 42)
        XCTAssertTrue(summary(reviewedToday: 1).hasReviewedToday)
    }

    func testHistoryIsOldestFirstZeroFilledAndEndsToday() {
        let byDay = [
            AnkiDayCount(day: today, count: 12),
            AnkiDayCount(day: today.adding(days: -2), count: 30),
            AnkiDayCount(day: today.adding(days: -20), count: 99),
        ]
        let result = summary(reviewedToday: 12, byDay: byDay)
        XCTAssertEqual(result.history.count, 14)
        XCTAssertEqual(result.history.first?.day, today.adding(days: -13))
        XCTAssertEqual(result.history.last, AnkiDayCount(day: today, count: 12))
        XCTAssertEqual(result.history.map(\.count).suffix(3), [30, 0, 12])
        XCTAssertFalse(result.history.contains { $0.count == 99 }, "days outside the window are dropped")
    }

    func testHistoryCrossesMonthBoundary() {
        let result = summary(historyDays: 3)
        XCTAssertEqual(result.history.map(\.day.description), ["2026-09-29", "2026-09-30", "2026-10-01"])
    }

    func testHistoryIgnoresInputOrderAndMergesRepeatedDays() {
        let byDay = [
            AnkiDayCount(day: today.adding(days: -1), count: 5),
            AnkiDayCount(day: today, count: 3),
            AnkiDayCount(day: today.adding(days: -1), count: 2),
        ]
        XCTAssertEqual(summary(byDay: byDay, historyDays: 2).history.map(\.count), [7, 3])
    }

    // MARK: Streak

    func testStreakCountsBackFromToday() {
        XCTAssertEqual(summary(byDay: days([10, 20, 30, 0, 40])).streak, 3)
    }

    func testStreakStaysAliveBeforeTodaysFirstReview() {
        let result = summary(byDay: days([0, 20, 30, 15]))
        XCTAssertEqual(result.streak, 3)
        XCTAssertFalse(result.hasReviewedToday)
    }

    func testStreakIsZeroAfterAMissedDay() {
        XCTAssertEqual(summary(byDay: days([0, 0, 30, 15])).streak, 0)
    }

    func testStreakIsNotCappedByTheHistoryWindow() {
        XCTAssertEqual(summary(byDay: days(Array(repeating: 5, count: 40))).streak, 40)
    }

    func testTodaysCountAloneStartsAStreak() {
        XCTAssertEqual(summary(reviewedToday: 3, byDay: days([0, 0])).streak, 1)
    }

    // MARK: Retention

    func testRetentionIsShareOfMatureReviewsNotAnsweredAgain() {
        let passes = (0..<36).map { review(Int64($0), secondsAgo: 3_600, ease: $0 % 2 == 0 ? 3 : 4) }
        let lapses = (100..<104).map { review(Int64($0), secondsAgo: 3_600, ease: 1) }
        let result = summary(reviews: passes + lapses)
        XCTAssertEqual(result.retentionSampleSize, 40)
        XCTAssertEqual(try XCTUnwrap(result.retention), 0.9, accuracy: 0.0001)
    }

    func testRetentionIgnoresLearningRelearningFilteredAndManualRows() {
        let reviews = (0..<20).map { review(Int64($0), secondsAgo: 60) }
            + [AnkiReview.Kind.learn, .relearn, .filtered, .manual, .unknown].enumerated().map {
                review(Int64(500 + $0.offset), secondsAgo: 60, ease: 1, kind: $0.element)
            }
            + [review(900, secondsAgo: 60, ease: 0)]
        let result = summary(reviews: reviews)
        XCTAssertEqual(result.retentionSampleSize, 20)
        XCTAssertEqual(result.retention, 1)
    }

    func testRetentionOnlyUsesTheWindow() {
        let recent = (0..<20).map { review(Int64($0), secondsAgo: 86_400) }
        let old = (100..<120).map { review(Int64($0), secondsAgo: 31 * 86_400, ease: 1) }
        let future = [review(200, secondsAgo: -60, ease: 1)]
        let result = summary(reviews: recent + old + future)
        XCTAssertEqual(result.retentionSampleSize, 20)
        XCTAssertEqual(result.retention, 1)
    }

    func testRetentionIsNilBelowTheMinimumSample() {
        let reviews = (0..<(AnkiSummary.minimumRetentionSample - 1)).map { review(Int64($0), secondsAgo: 60) }
        let result = summary(reviews: reviews)
        XCTAssertNil(result.retention)
        XCTAssertEqual(result.retentionSampleSize, AnkiSummary.minimumRetentionSample - 1)
    }

    func testDuplicateReviewRowsAreCountedOnce() {
        let reviews = (0..<20).map { review(Int64($0), secondsAgo: 60) }
        let lapse = review(77, secondsAgo: 60, ease: 1)
        let result = summary(reviews: reviews + [lapse, lapse, lapse])
        XCTAssertEqual(result.retentionSampleSize, 21)
        XCTAssertEqual(try XCTUnwrap(result.retention), 20.0 / 21.0, accuracy: 0.0001)
    }

    // MARK: Study time

    func testStudyTimeSumsTodaysReviewsAfterRollover() {
        // now is 15:00 UTC; rollover is 04:00, so 11h ago (04:00) is today
        // and 12h ago (03:00) belongs to yesterday.
        let reviews = [
            review(1, secondsAgo: 60, kind: .learn, durationMs: 6_000),
            review(2, secondsAgo: 11 * 3_600, durationMs: 4_000),
            review(3, secondsAgo: 12 * 3_600, durationMs: 90_000),
        ]
        XCTAssertEqual(summary(reviews: reviews).studyTimeToday, 10)
    }

    // MARK: Codable and demo

    func testSummaryRoundTripsThroughCodable() throws {
        let original = summary(
            deckStats: [stats(1, "Step1", new: 3, review: 9)],
            reviewedToday: 4, byDay: days([4, 2]),
            reviews: (0..<25).map { review(Int64($0), secondsAgo: 60, ease: $0 == 0 ? 1 : 3) }
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AnkiSummary.self, from: data), original)
    }

    func testDemoLooksLikeAStudyingMedStudent() {
        let demo = AnkiSummary.demo(now: now, calendar: utc)
        XCTAssertEqual(demo.dueTotal, 320, "child deck rolled into its parent")
        XCTAssertEqual(demo.reviewedToday, 112)
        XCTAssertEqual(demo.streak, 12)
        XCTAssertEqual(demo.history.count, 14)
        XCTAssertEqual(try XCTUnwrap(demo.retention), 0.9, accuracy: 0.03)
        XCTAssertGreaterThan(demo.studyTimeToday, 0)
    }

    // MARK: Fetching

    func testClientSummaryFetchesEveryDeckAndAggregates() async throws {
        let startMs = Int64((now.timeIntervalSince1970 - 3_600) * 1000)
        let row = { (offset: Int64, ease: Int) in "[\(startMs + offset),1,-1,\(ease),10,4,2500,5000,1]" }
        let step1Rows = (0..<15).map { row(Int64($0), 3) }.joined(separator: ",")
        let cardioRows = (100..<104).map { row(Int64($0), 3) }.joined(separator: ",") + "," + row(200, 1)
        let transport = SummaryTransport(
            [
                "deckNamesAndIds": #"{"result":{"Step1":1,"Step1::Cardio":2},"error":null}"#,
                "getDeckStats": #"{"result":{"1":{"deck_id":1,"name":"Step1","new_count":20,"learn_count":3,"review_count":80,"total_in_deck":900},"2":{"deck_id":2,"name":"Step1::Cardio","new_count":5,"learn_count":1,"review_count":30,"total_in_deck":200}},"error":null}"#,
                "getNumCardsReviewedToday": #"{"result":20,"error":null}"#,
                "getNumCardsReviewedByDay": #"{"result":[["2026-10-01",20],["2026-09-30",64],["2026-09-29",12]],"error":null}"#,
            ],
            reviewsByDeck: [
                "Step1": #"{"result":[\#(step1Rows)],"error":null}"#,
                "Step1::Cardio": #"{"result":[\#(cardioRows)],"error":null}"#,
            ]
        )
        let client = AnkiConnectClient(transport: transport)
        let result = try await client.summary(now: now, calendar: utc)

        XCTAssertEqual(result.dueTotal, 103)
        XCTAssertEqual(result.reviewedToday, 20)
        XCTAssertEqual(result.streak, 3)
        XCTAssertEqual(result.retentionSampleSize, 20)
        XCTAssertEqual(try XCTUnwrap(result.retention), 0.95, accuracy: 0.0001)
        XCTAssertEqual(result.studyTimeToday, 100)

        XCTAssertEqual(
            transport.sentActions,
            ["deckNamesAndIds", "getDeckStats", "getNumCardsReviewedToday", "getNumCardsReviewedByDay", "multi", "cardReviews", "cardReviews"],
            "every deck's review log is fetched in one batched request"
        )
        let params = transport.sentReviewParams
        XCTAssertEqual(params.compactMap { $0["deck"] as? String }.sorted(), ["Step1", "Step1::Cardio"])
        let expectedStart = Int64((now.timeIntervalSince1970 - 30 * 86_400) * 1000)
        XCTAssertTrue(params.allSatisfy { ($0["startID"] as? NSNumber)?.int64Value == expectedStart })
    }

    func testClientSummaryPropagatesTypedErrors() async {
        let client = AnkiConnectClient(transport: SummaryTransport([:]))
        do {
            _ = try await client.summary(now: now, calendar: utc)
            XCTFail("Expected an error")
        } catch let error as AnkiConnectError {
            XCTAssertEqual(error, .unsupportedAction("deckNamesAndIds"))
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
