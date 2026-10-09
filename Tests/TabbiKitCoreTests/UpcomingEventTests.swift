import XCTest
import TabbiKitCore

final class UpcomingEventTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(_ id: String, start: Double, end: Double, allDay: Bool = false, title: String? = nil) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: title ?? id,
            start: now.addingTimeInterval(start * 60),
            end: now.addingTimeInterval(end * 60),
            isAllDay: allDay
        )
    }

    func testUpNextDropsEndedAndAllDayEventsAndSortsBySoonest() {
        let events = [
            event("later", start: 90, end: 120),
            event("ended", start: -60, end: -1),
            event("holiday", start: -600, end: 800, allDay: true),
            event("current", start: -10, end: 20),
            event("soon", start: 12, end: 40),
            event("tonight", start: 300, end: 360),
        ]
        XCTAssertEqual(UpcomingEvent.upNext(from: events, at: now).map(\.id), ["current", "soon", "later"])
        XCTAssertEqual(UpcomingEvent.upNext(from: events, at: now, limit: 1).map(\.id), ["current"])
        XCTAssertEqual(UpcomingEvent.upNext(from: events, at: now, limit: 0), [])
    }

    func testUpNextTreatsEventEndingExactlyNowAsOver() {
        XCTAssertEqual(UpcomingEvent.upNext(from: [event("edge", start: -30, end: 0)], at: now), [])
    }

    func testUpNextBreaksStartTiesByEndThenTitle() {
        let events = [
            event("b", start: 10, end: 40, title: "Beta"),
            event("a", start: 10, end: 40, title: "Alpha"),
            event("short", start: 10, end: 20),
        ]
        XCTAssertEqual(UpcomingEvent.upNext(from: events, at: now).map(\.id), ["short", "a", "b"])
    }

    func testTimingRoundsUpToWholeMinutes() {
        XCTAssertEqual(event("x", start: -5, end: 5).timing(at: now), .now)
        XCTAssertEqual(event("x", start: 0, end: 5).timing(at: now), .now)
        XCTAssertEqual(event("x", start: 0.25, end: 5).timing(at: now), .startsIn(minutes: 1))
        XCTAssertEqual(event("x", start: 11.5, end: 30).timing(at: now), .startsIn(minutes: 12))
        XCTAssertEqual(event("x", start: 12, end: 30).timing(at: now), .startsIn(minutes: 12))
    }

    func testInProgressIsHalfOpen() {
        let meeting = event("x", start: 0, end: 30)
        XCTAssertTrue(meeting.isInProgress(at: now))
        XCTAssertFalse(meeting.isInProgress(at: now.addingTimeInterval(30 * 60)))
        XCTAssertFalse(meeting.isInProgress(at: now.addingTimeInterval(-1)))
    }

    func testBadgeText() {
        XCTAssertEqual(UpcomingEventFormat.badge(.now), "now")
        XCTAssertEqual(UpcomingEventFormat.badge(.startsIn(minutes: 1)), "in 1 min")
        XCTAssertEqual(UpcomingEventFormat.badge(.startsIn(minutes: 59)), "in 59 min")
        XCTAssertEqual(UpcomingEventFormat.badge(.startsIn(minutes: 60)), "in 1h")
        XCTAssertEqual(UpcomingEventFormat.badge(.startsIn(minutes: 125)), "in 2h 5m")
    }

    func testStartTimeFollowsLocaleClockWithoutDayPeriod() {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-09-20 21:05 UTC.
        let evening = Date(timeIntervalSince1970: 1_789_862_400 + 21 * 3600 + 300)
        XCTAssertEqual(UpcomingEventFormat.startTime(evening, locale: Locale(identifier: "en_US"), timeZone: utc), "9:05")
        XCTAssertEqual(UpcomingEventFormat.startTime(evening, locale: Locale(identifier: "de_DE"), timeZone: utc), "21:05")
    }

    func testTitleFallsBackForBlankTitles() {
        XCTAssertEqual(UpcomingEventFormat.title(event("x", start: 0, end: 1, title: "  Sync ")), "Sync")
        XCTAssertEqual(UpcomingEventFormat.title(event("x", start: 0, end: 1, title: " \n")), "Untitled event")
    }

    func testSamplesIncludeCurrentAndJoinableEvents() {
        for kind in PlannerSampleDay.allCases {
            let samples = UpcomingEvent.samples(now: now, kind: kind)
            let upNext = UpcomingEvent.upNext(from: samples, at: now)
            XCTAssertEqual(upNext.count, 3)
            XCTAssertEqual(upNext.first?.timing(at: now), .now)
            XCTAssertTrue(upNext.contains { $0.meetingLink != nil })
            XCTAssertTrue(upNext.contains { $0.meetingLink == nil })
            XCTAssertEqual(Set(samples.map(\.id)).count, samples.count)
            for (earlier, later) in zip(samples, samples.dropFirst()) {
                XCTAssertLessThan(earlier.start, later.start, "\(kind) samples are in order")
            }
        }
    }

    func testMedicineSamplesAreLecturesAndLabs() {
        let titles = UpcomingEvent.samples(now: now, kind: .medicine).map(\.title)
        XCTAssertEqual(titles, ["Cardiology lecture", "Anatomy lab: thorax", "Clinical skills session"])
    }

    func testSamplesStartOnFiveMinuteMarksAtAnyMoment() {
        // Every second across a five-minute window: the first event is always
        // live, the next is still ahead, and all starts are on clean times.
        for offset in stride(from: 0.0, to: 300, by: 1) {
            let moment = now.addingTimeInterval(offset)
            let upNext = UpcomingEvent.upNext(from: UpcomingEvent.samples(now: moment, kind: offset < 150 ? .work : .medicine), at: moment)
            XCTAssertEqual(upNext.count, 3)
            XCTAssertEqual(upNext.first?.timing(at: moment), .now)
            XCTAssertNotEqual(upNext[1].timing(at: moment), .now)
            for event in upNext {
                XCTAssertEqual(event.start.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 300), 0)
            }
        }
    }
}

final class MeetingLinkTests: XCTestCase {
    func testRecognizesZoomMeetAndTeamsJoinLinks() {
        let cases: [(String, MeetingLink.Provider)] = [
            ("https://zoom.us/j/5551234567?pwd=abc", .zoom),
            ("https://us02web.zoom.us/j/8765?pwd=x", .zoom),
            ("https://acme.zoom.us/my/ana", .zoom),
            ("https://meet.google.com/abc-defg-hij", .googleMeet),
            ("https://meet.google.com/lookup/team-sync", .googleMeet),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0", .teams),
            ("https://teams.live.com/meet/9876543210", .teams),
        ]
        for (string, provider) in cases {
            XCTAssertEqual(MeetingLink.classify(URL(string: string)!)?.provider, provider, string)
        }
    }

    func testIgnoresNonJoinPagesOnTheSameHosts() {
        for string in [
            "https://zoom.us/pricing",
            "https://meet.google.com/",
            "https://teams.microsoft.com/l/chat/0/0",
            "https://docs.google.com/document/d/abc",
            "mailto:ana@example.com",
            "https://notzoom.us/j/123",
        ] {
            XCTAssertNil(MeetingLink.classify(URL(string: string)!), string)
        }
    }

    func testUpgradesPlainHTTPToHTTPS() {
        let link = MeetingLink.classify(URL(string: "http://zoom.us/j/123")!)
        XCTAssertEqual(link?.url.absoluteString, "https://zoom.us/j/123")
    }

    func testPrefersURLFieldThenLocationThenNotes() {
        let notes = "Agenda: https://docs.google.com/doc\nJoin: https://meet.google.com/abc-defg-hij"
        XCTAssertEqual(
            MeetingLink.detect(url: URL(string: "https://zoom.us/j/1"), location: "https://teams.live.com/meet/2", notes: notes)?.provider,
            .zoom
        )
        XCTAssertEqual(
            MeetingLink.detect(url: URL(string: "https://example.com"), location: "Room 4 / https://teams.live.com/meet/2", notes: notes)?.provider,
            .teams
        )
        XCTAssertEqual(MeetingLink.detect(location: "Room 4", notes: notes)?.provider, .googleMeet)
    }

    func testFindsLinksWrappedInInviteFormatting() {
        let notes = """
        ──────────
        Join Zoom Meeting
        <https://us06web.zoom.us/j/81234567890?pwd=AbC123>.

        Meeting ID: 812 3456 7890
        """
        let link = MeetingLink.detect(notes: notes)
        XCTAssertEqual(link?.provider, .zoom)
        XCTAssertEqual(link?.url.absoluteString, "https://us06web.zoom.us/j/81234567890?pwd=AbC123")
    }

    func testReturnsNilWithoutAnyMeetingLink() {
        XCTAssertNil(MeetingLink.detect())
        XCTAssertNil(MeetingLink.detect(location: "Cafe on 3rd", notes: "Bring the slides https://example.com/deck"))
    }
}
