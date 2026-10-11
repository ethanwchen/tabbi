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

    func testTheWingHasRoomForExploringInABlockWithAnAdventure() {
        var profile = PetProfile.starter(.cat)
        profile.rename("Mochi")
        let home = TickerPet(profile: profile, mood: .studying)
        var adventurous = home
        let now = Date()
        adventurous.adventure = PetAdventure(departsAt: now, returnsAt: now.addingTimeInterval(600),
                                             endsAt: now.addingTimeInterval(603))
        XCTAssertGreaterThan(NotchPreviewLayout.wingWidth(for: .pet(adventurous)),
                             NotchPreviewLayout.wingWidth(for: .pet(home)), "room for Mochi exploring")
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

/// A dozing pet's drifting "z"s stay whole inside the closed notch: every z
/// pixel of every frame of the sleep loop, for every breed and in the
/// still frame Reduce Motion holds, lands at least 2 pt below the bar's top
/// edge, for the user's pet and for party pets alike.
@MainActor
final class NotchSleepZBoundsTests: XCTestCase {
    private static let margin: CGFloat = 2

    private func zRows(_ canvas: PetCanvas) -> [Int] {
        (0..<canvas.height).filter { y in
            (0..<canvas.width).contains { canvas[$0, y] == .effect || canvas[$0, y] == .effectFaint }
        }
    }

    func testEveryZOfTheSleepLoopIsInsideTheBar() {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.sleep, for: breed)
            for (index, frame) in (clip.frames + [clip.stillFrame]).enumerated() {
                for row in zRows(frame.canvas) {
                    for (who, top, size) in [("pet", NotchPreviewLayout.petRowTop(row), CGFloat(1)),
                                             ("party pet", NotchPreviewLayout.partyPetRowTop(row),
                                              NotchPreviewLayout.partyPetPixelSize)] {
                        XCTAssertGreaterThanOrEqual(top, Self.margin, "\(breed) \(who) frame \(index) row \(row)")
                        XCTAssertLessThanOrEqual(top + size, NotchPreviewLayout.barHeight,
                                                 "\(breed) \(who) frame \(index) row \(row)")
                    }
                }
            }
        }
    }

    func testTheBarShowsThePetFromRowThreeDown() {
        // The snapshot's pet: the frame's bottom row sits 3 pt above the
        // bar's bottom edge, so row 3 is the first one inside the bar.
        XCTAssertEqual(NotchPreviewLayout.petRowTop(3), 0)
        XCTAssertEqual(NotchPreviewLayout.petRowTop(PetComposer.frameSize), NotchPreviewLayout.barHeight - 3)
    }
}
