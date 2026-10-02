import XCTest
import NotchDeckCore

final class TickerSourcesTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ title: String, startsIn minutes: Double, length: Double = 30, link: Bool = false) -> UpcomingEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return UpcomingEvent(
            id: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(length * 60),
            meetingLink: link ? MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/1")!) : nil
        )
    }

    private func runningFocus(remaining: TimeInterval) -> FocusTimer {
        var timer = FocusTimer(config: FocusTimerConfig(focusDuration: 25 * 60))
        timer.start(at: now.addingTimeInterval(remaining - 25 * 60))
        return timer
    }

    func testNoDataMeansNoItems() {
        XCTAssertEqual(TickerSources().items(at: now), [])
    }

    func testItemsComeInRotationOrder() {
        let sources = TickerSources(
            events: [event("Standup", startsIn: 30)],
            isMusicPlaying: true,
            focus: runningFocus(remaining: 600),
            tasksRemaining: 3,
            usage: ClaudeRateLimitSnapshot(status: nil, fiveHour: ClaudeUsageWindow(utilization: 0.85, resetsAt: nil), sevenDay: nil)
        )
        XCTAssertEqual(sources.items(at: now).map(\.kind), [.meeting, .nowPlaying, .focus, .tasks, .claudeUsage])
    }

    func testDisabledKindsAreSkipped() {
        let sources = TickerSources(isMusicPlaying: true, tasksRemaining: 2)
        XCTAssertEqual(sources.items(at: now, enabled: [.tasks]), [.tasks(remaining: 2)])
        XCTAssertEqual(sources.items(at: now, enabled: []), [])
    }

    func testMeetingCountsDownAndReportsJoinLink() {
        let sources = TickerSources(events: [event("Standup", startsIn: 3.5, link: true)])
        XCTAssertEqual(sources.items(at: now), [
            .meeting(TickerMeeting(title: "Standup", timing: .startsIn(minutes: 4), canJoin: true)),
        ])
    }

    func testMeetingInProgressReadsNow() {
        let sources = TickerSources(events: [event("Design review", startsIn: -10)])
        XCTAssertEqual(sources.items(at: now), [
            .meeting(TickerMeeting(title: "Design review", timing: .now, canJoin: false)),
        ])
    }

    func testImminentMeetingBeatsOneAlreadyUnderWay() {
        let focusBlock = event("Focus block", startsIn: -57, length: 120)
        let standup = event("Standup", startsIn: 3)
        XCTAssertEqual(TickerSources(events: [focusBlock, standup]).items(at: now), [
            .meeting(TickerMeeting(title: "Standup", timing: .startsIn(minutes: 3), canJoin: false)),
        ])
        let later = event("Standup", startsIn: 20)
        XCTAssertEqual(TickerSources(events: [focusBlock, later]).items(at: now), [
            .meeting(TickerMeeting(title: "Focus block", timing: .now, canJoin: false)),
        ])
    }

    func testNothingTimedMeansNoWake() {
        XCTAssertNil(TickerSources(isMusicPlaying: true, tasksRemaining: 3).nextChange(after: now))
    }

    func testNextChangeFollowsTheMeetingCountdown() {
        let soon = TickerSources(events: [event("Standup", startsIn: 3.5)])
        let wake = try! XCTUnwrap(soon.nextChange(after: now))
        XCTAssertEqual(wake, now.addingTimeInterval(30))
        XCTAssertNotEqual(soon.items(at: now), soon.items(at: wake))
        XCTAssertEqual(soon.items(at: now), soon.items(at: wake.addingTimeInterval(-1)))

        let started = TickerSources(events: [event("Review", startsIn: -10, length: 30)])
        XCTAssertEqual(started.nextChange(after: now), now.addingTimeInterval(20 * 60))

        let distant = TickerSources(events: [event("Later", startsIn: 90)])
        let entry = try! XCTUnwrap(distant.nextChange(after: now))
        XCTAssertEqual(entry, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(distant.items(at: entry).map(\.kind), [.meeting])
        XCTAssertEqual(distant.nextChange(after: now, enabled: [.tasks]), nil)
    }

    func testNextChangeCoversFocusEndAndUsageReset() {
        let focus = TickerSources(focus: runningFocus(remaining: 600))
        XCTAssertEqual(focus.nextChange(after: now), now.addingTimeInterval(600))

        let reset = now.addingTimeInterval(900)
        let usage = TickerSources(usage: ClaudeRateLimitSnapshot(
            status: nil, fiveHour: ClaudeUsageWindow(utilization: 0.9, resetsAt: reset), sevenDay: nil))
        XCTAssertEqual(usage.nextChange(after: now), reset)
        XCTAssertEqual(usage.items(at: reset), [])
    }

    func testMeetingsBeyondTheHorizonAndAllDayEventsAreHidden() {
        var allDay = event("Offsite", startsIn: 0, length: 24 * 60)
        allDay.isAllDay = true
        XCTAssertEqual(TickerSources(events: [event("Later", startsIn: 61), allDay]).items(at: now), [])
        XCTAssertEqual(TickerSources(events: [event("Soon", startsIn: 60)]).items(at: now).count, 1)
    }

    func testOnlyAnActiveFocusSessionShows() {
        XCTAssertEqual(TickerSources(focus: FocusTimer()).items(at: now), [])

        XCTAssertEqual(TickerSources(focus: runningFocus(remaining: 600)).items(at: now),
                       [.focus(phase: .focus, remaining: 600, isRunning: true)])

        var paused = runningFocus(remaining: 600)
        paused.pause(at: now)
        XCTAssertEqual(TickerSources(focus: paused).items(at: now),
                       [.focus(phase: .focus, remaining: 600, isRunning: false)])
    }

    func testFinishedTaskListShowsNothing() {
        XCTAssertEqual(TickerSources(tasksRemaining: 0).items(at: now), [])
    }

    func testUsageShowsOnlyAboveEightyPercentAndPicksTheFullerWindow() {
        func usage(_ fiveHour: Double?, _ weekly: Double?) -> [TickerItem] {
            TickerSources(usage: ClaudeRateLimitSnapshot(
                status: nil,
                fiveHour: fiveHour.map { ClaudeUsageWindow(utilization: $0, resetsAt: nil) },
                sevenDay: weekly.map { ClaudeUsageWindow(utilization: $0, resetsAt: nil) }
            )).items(at: now)
        }
        XCTAssertEqual(usage(0.8, 0.5), [])
        XCTAssertEqual(usage(nil, nil), [])
        XCTAssertEqual(usage(0.81, 0.5), [.claudeUsage(window: .fiveHour, utilization: 0.81)])
        XCTAssertEqual(usage(0.4, 0.93), [.claudeUsage(window: .weekly, utilization: 0.93)])
        XCTAssertEqual(usage(0.9, 0.9), [.claudeUsage(window: .fiveHour, utilization: 0.9)])
    }

    func testUsageFromAWindowThatHasResetIsIgnored() {
        let snapshot = ClaudeRateLimitSnapshot(
            status: nil,
            fiveHour: ClaudeUsageWindow(utilization: 0.95, resetsAt: now.addingTimeInterval(-60)),
            sevenDay: ClaudeUsageWindow(utilization: 0.85, resetsAt: now.addingTimeInterval(3600))
        )
        XCTAssertEqual(TickerSources(usage: snapshot).items(at: now),
                       [.claudeUsage(window: .weekly, utilization: 0.85)])
        XCTAssertEqual(TickerSources(usage: snapshot).items(at: now.addingTimeInterval(7200)), [])
    }

    func testOnlyImminentOrCurrentMeetingsPin() {
        func pinned(startsIn minutes: Double) -> Bool {
            TickerSources(events: [event("M", startsIn: minutes)]).items(at: now).first?.isPinned ?? false
        }
        XCTAssertTrue(pinned(startsIn: -5))
        XCTAssertTrue(pinned(startsIn: 0))
        XCTAssertTrue(pinned(startsIn: 5))
        XCTAssertFalse(pinned(startsIn: 5.5))
        XCTAssertFalse(TickerItem.tasks(remaining: 1).isPinned)
    }

    func testEveryKindOpensItsModule() {
        XCTAssertEqual(TickerKind.meeting.module, .planner)
        XCTAssertEqual(TickerKind.focus.module, .planner)
        XCTAssertEqual(TickerKind.tasks.module, .planner)
        XCTAssertEqual(TickerKind.nowPlaying.module, .spotify)
        XCTAssertEqual(TickerKind.claudeUsage.module, .claudeUsage)
    }
}

final class TickerRotationTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let music = TickerItem.nowPlaying
    private let tasks = TickerItem.tasks(remaining: 3)
    private let focus = TickerItem.focus(phase: .focus, remaining: 600, isRunning: true)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func meeting(_ timing: EventTiming) -> TickerItem {
        .meeting(TickerMeeting(title: "Standup", timing: timing, canJoin: false))
    }

    func testNothingAvailableShowsNothing() {
        var rotation = TickerRotation(interval: 8)
        XCTAssertNil(rotation.update(items: [], at: start))
        XCTAssertNil(rotation.currentKind)
    }

    func testHoldsEachItemForTheIntervalThenWrapsAround() {
        var rotation = TickerRotation(interval: 8)
        let items = [music, focus, tasks]
        XCTAssertEqual(rotation.update(items: items, at: at(0)), music)
        XCTAssertEqual(rotation.update(items: items, at: at(7.9)), music)
        XCTAssertEqual(rotation.update(items: items, at: at(8)), focus)
        XCTAssertEqual(rotation.update(items: items, at: at(15)), focus)
        XCTAssertEqual(rotation.update(items: items, at: at(16)), tasks)
        XCTAssertEqual(rotation.update(items: items, at: at(24)), music)
    }

    func testReturnsFreshDataForTheItemOnScreen() {
        var rotation = TickerRotation(interval: 8)
        _ = rotation.update(items: [focus], at: at(0))
        let later = TickerItem.focus(phase: .focus, remaining: 597, isRunning: true)
        XCTAssertEqual(rotation.update(items: [later], at: at(3)), later)
    }

    func testASingleItemStaysAndRestartsItsHold() {
        var rotation = TickerRotation(interval: 5)
        XCTAssertEqual(rotation.update(items: [tasks], at: at(0)), tasks)
        XCTAssertEqual(rotation.update(items: [tasks], at: at(5)), tasks)
        XCTAssertEqual(rotation.shownSince, at(5))
    }

    func testAVanishedItemHandsOverToItsSuccessorImmediately() {
        var rotation = TickerRotation(interval: 8)
        XCTAssertEqual(rotation.update(items: [music, focus, tasks], at: at(0)), music)
        XCTAssertEqual(rotation.update(items: [focus, tasks], at: at(2)), focus)
        XCTAssertEqual(rotation.shownSince, at(2))
    }

    func testANewItemJoinsTheRotationInOrder() {
        var rotation = TickerRotation(interval: 8)
        _ = rotation.update(items: [music, tasks], at: at(0))
        XCTAssertEqual(rotation.update(items: [music, focus, tasks], at: at(8)), focus)
    }

    func testAnImminentMeetingPinsAndRotationResumesAfterIt() {
        var rotation = TickerRotation(interval: 8)
        _ = rotation.update(items: [music, tasks], at: at(0))

        let soon = meeting(.startsIn(minutes: 4))
        XCTAssertEqual(rotation.update(items: [soon, music, tasks], at: at(2)), soon)
        XCTAssertEqual(rotation.update(items: [soon, music, tasks], at: at(60)), soon)
        let live = meeting(.now)
        XCTAssertEqual(rotation.update(items: [live, music, tasks], at: at(300)), live)
        XCTAssertEqual(rotation.shownSince, at(2), "the pin keeps its original start")

        // The meeting ends; rotation picks up with the item after it.
        XCTAssertEqual(rotation.update(items: [music, tasks], at: at(2000)), music)
        XCTAssertEqual(rotation.update(items: [music, tasks], at: at(2008)), tasks)
    }

    func testADistantMeetingRotatesLikeAnyOtherItem() {
        var rotation = TickerRotation(interval: 8)
        let later = meeting(.startsIn(minutes: 30))
        XCTAssertEqual(rotation.update(items: [later, music], at: at(0)), later)
        XCTAssertEqual(rotation.update(items: [later, music], at: at(8)), music)
    }

    func testChangingTheIntervalAppliesToTheItemOnScreen() {
        var rotation = TickerRotation(interval: 12)
        _ = rotation.update(items: [music, tasks], at: at(0))
        rotation.interval = 5
        XCTAssertEqual(rotation.update(items: [music, tasks], at: at(5)), tasks)
    }

    func testEverythingDisappearingClearsTheRotation() {
        var rotation = TickerRotation(interval: 8)
        _ = rotation.update(items: [music], at: at(0))
        XCTAssertNil(rotation.update(items: [], at: at(1)))
        XCTAssertNil(rotation.currentKind)
        XCTAssertEqual(rotation.update(items: [tasks], at: at(2)), tasks)
    }
}

final class TickerFormatTests: XCTestCase {
    func testMeetingLines() {
        let soon = TickerMeeting(title: "Standup", timing: .startsIn(minutes: 4), canJoin: true)
        let live = TickerMeeting(title: "Design review", timing: .now, canJoin: false)
        XCTAssertEqual(TickerFormat.meetingSummary(soon), "Standup in 4 min")
        XCTAssertEqual(TickerFormat.meetingSummary(live), "Design review now")
        XCTAssertEqual(TickerFormat.meetingCountdown(.startsIn(minutes: 4)), "in 4 min")
    }

    func testTasksLeftPluralizes() {
        XCTAssertEqual(TickerFormat.tasksLeft(1), "1 task left")
        XCTAssertEqual(TickerFormat.tasksLeft(3), "3 tasks left")
    }

    func testFocusAndUsage() {
        XCTAssertEqual(TickerFormat.focusClock(18 * 60 + 42), "18:42")
        XCTAssertEqual(TickerFormat.usage(window: .fiveHour, utilization: 0.842), "5h 84%")
        XCTAssertEqual(TickerFormat.usage(window: .weekly, utilization: 0.91), "Week 91%")
    }
}
