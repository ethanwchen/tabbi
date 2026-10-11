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

/// Nothing the closed-notch pet draws is ever cut off by the bar: not its
/// sleep "z"s, its hat in a hop, a falling petal, a sparkle or the bond's
/// glow. Every pixel of every frame (and every tick of an item's own loop)
/// stays inside the bar with room to spare, for every breed and every item.
@MainActor
final class NotchPetBoundsTests: XCTestCase {
    /// Everything the pet beside the notch can play: it always sits beside,
    /// so it never peeks in or out of the notch.
    nonisolated private static let animations = PetAnimation.allCases.filter { $0 != .peekIn && $0 != .peekOut }

    private func effectRows(_ canvas: PetCanvas) -> [Int] {
        (0..<canvas.height).filter { y in
            (0..<canvas.width).contains { canvas[$0, y] == .effect || canvas[$0, y] == .effectFaint }
        }
    }

    private func assertInsideBar(_ rows: ClosedRange<Int>, margin: CGFloat, _ label: @autoclosure () -> String) {
        XCTAssertGreaterThanOrEqual(NotchPreviewLayout.petRowTop(rows.lowerBound), margin, label())
        XCTAssertLessThanOrEqual(NotchPreviewLayout.petRowTop(rows.upperBound + 1),
                                 NotchPreviewLayout.barHeight - margin, label())
    }

    func testEveryZOfTheSleepLoopIsWellInsideTheBar() {
        // The "z"s keep 2 pt clear of the top, for the user's pet and for
        // party pets, in every frame and in the still frame Reduce Motion holds.
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.sleep, for: breed, ceiling: NotchPreviewLayout.petCeilingRow)
            for (index, frame) in (clip.frames + [clip.stillFrame]).enumerated() {
                for row in effectRows(frame.canvas) {
                    assertInsideBar(row...row, margin: 2, "\(breed) frame \(index) row \(row)")
                    XCTAssertGreaterThanOrEqual(NotchPreviewLayout.partyPetRowTop(row), 2, "\(breed) party pet row \(row)")
                }
            }
        }
    }

    func testEveryItemOnEveryBreedStaysInsideTheBar() {
        // Every breed in every outfit, every accessory and every distinct
        // bond look (the collars and the sparkle), in every animation. The
        // combinations compose in parallel; that is thousands of clips.
        var looks: [Look] = [Look(name: "no costume")]
        looks += PetOutfit.allCases.map { Look(name: "\($0)", outfit: $0) }
        looks += PetAccessory.allCases.map { Look(name: "\($0)", accessories: [$0]) }
        let bonds = Set((2...PetBond.maxLevel).map(PetBondLook.init(level:))).subtracting([.none])
        looks += bonds.map { Look(name: "\($0.collar) collar\($0.sparkle ? ", sparkle" : "")", bond: $0) }
        let jobs = PetBreed.allCases.flatMap { breed in looks.map { (breed, $0) } }
        let report = FailureReport()
        let ceiling = NotchPreviewLayout.petCeilingRow
        let top = NotchPreviewLayout.petRowTop(0)
        let (margin, bar) = (NotchPreviewLayout.petMargin, NotchPreviewLayout.barHeight)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let (breed, look) = jobs[index]
            for animation in Self.animations {
                let clip = PetComposer.clip(animation, for: breed, outfit: look.outfit, accessories: look.accessories,
                                            bond: look.bond, ceiling: ceiling)
                for (frameIndex, frame) in clip.frames.enumerated() {
                    for (tick, canvas) in ([frame.canvas] + frame.itemFrames).enumerated() {
                        guard let bounds = canvas.opaqueBounds else { continue }
                        // Rows are 1 pt apart (`NotchPetWing.pixelSize`).
                        let (upper, lower) = (top + CGFloat(bounds.minY), top + CGFloat(bounds.maxY + 1))
                        if upper < margin || lower > bar - margin {
                            report.add("\(breed) in \(look.name), \(animation) frame \(frameIndex) tick \(tick): "
                                       + "\(upper)...\(lower) pt in a \(bar) pt bar")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(NotchPreviewLayout.petRowTop(1) - NotchPreviewLayout.petRowTop(0), 1, "one point per row")
        XCTAssertEqual(report.failures, [], "\(report.failures.count) frames reach outside the bar")
    }

    func testPartyPetsSitInsideTheBarWhateverTheyWear() {
        // Smaller and lower, a party pet's whole frame fits: no ceiling needed.
        XCTAssertGreaterThanOrEqual(NotchPreviewLayout.partyPetRowTop(0), NotchPreviewLayout.petMargin)
        XCTAssertLessThanOrEqual(NotchPreviewLayout.partyPetRowTop(PetComposer.frameSize),
                                 NotchPreviewLayout.barHeight - NotchPreviewLayout.petMargin)
    }

    func testTheCeilingIsTheFirstRowClearOfTheTopEdge() {
        let ceiling = NotchPreviewLayout.petCeilingRow
        XCTAssertGreaterThanOrEqual(NotchPreviewLayout.petRowTop(ceiling), NotchPreviewLayout.petMargin)
        XCTAssertLessThan(NotchPreviewLayout.petRowTop(ceiling - 1), NotchPreviewLayout.petMargin)
    }
}

/// One costume to check, for `NotchPetBoundsTests`.
private struct Look: Sendable {
    var name: String
    var outfit: PetOutfit = .none
    var accessories: [PetAccessory] = []
    var bond: PetBondLook = .none
}

/// Failures collected from parallel work, read once it is all done.
private final class FailureReport: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [String] = []

    func add(_ failure: String) {
        lock.lock()
        collected.append(failure)
        lock.unlock()
    }

    var failures: [String] {
        lock.lock()
        defer { lock.unlock() }
        return collected.sorted()
    }
}
