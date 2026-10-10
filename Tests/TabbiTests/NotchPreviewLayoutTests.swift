import XCTest
import TabbiKitCore
import TabbiKit

/// The closed-notch meeting preview stays narrow and balanced: its text is
/// split across both wings instead of one wide line beside an empty wing.
@MainActor
final class NotchPreviewLayoutTests: XCTestCase {
    private func meeting(_ title: String, _ timing: EventTiming = .startsIn(minutes: 4)) -> TickerItem {
        .meeting(TickerMeeting(title: title, timing: timing, canJoin: true))
    }

    func testMeetingWingFitsTheLongerHalfNotTheWholeLine() {
        let wing = NotchPreviewLayout.wingWidth(for: meeting("Design standup"))
        let titleOnly = NotchPreviewLayout.wingWidth(for: .highlight(TickerHighlight(id: "h", source: "today", text: "Design standup")))
        let wholeLine = NotchPreviewLayout.wingWidth(for: .highlight(TickerHighlight(id: "h", source: "today", text: "Design standup in 4 min")))
        XCTAssertEqual(wing, titleOnly, "a title longer than the countdown sizes the wing")
        XCTAssertLessThan(wing, wholeLine)
    }

    func testShortTitleStillLeavesRoomForIconAndCountdown() {
        let short = NotchPreviewLayout.wingWidth(for: meeting("1:1"))
        let iconOnly = NotchPreviewLayout.wingWidth(for: .tasks(remaining: 0))
        XCTAssertGreaterThan(short, NotchPreviewLayout.iconSize + NotchPreviewLayout.outerInset)
        XCTAssertGreaterThanOrEqual(short, iconOnly)
    }

    func testLongTitlesAreCapped() {
        let wing = NotchPreviewLayout.wingWidth(for: meeting("Quarterly planning with the whole design and research team"))
        XCTAssertEqual(wing, NotchPreviewLayout.maxWingWidth)
    }

    func testTheChargingLineFitsBesideTheSippingPet() {
        let pet = TickerPet(profile: .starter(.cat), mood: .onBreak)
        var sipping = pet
        sipping.cheer = PetCheer(kind: .sip, id: 1, startedAt: Date())
        let wing = NotchPreviewLayout.wingWidth(for: .pet(sipping))
        XCTAssertGreaterThan(wing, NotchPreviewLayout.wingWidth(for: .pet(pet)), "room for the bolt and Charging")
        XCTAssertLessThan(wing, NotchPreviewLayout.maxWingWidth, "never truncated")
    }
}
