import XCTest
@testable import TabbiKitCore

final class SyncDocumentMergeTests: XCTestCase {
    private let early = Date(timeIntervalSince1970: 1_800_000_000)
    private let late = Date(timeIntervalSince1970: 1_800_000_600)

    private func pet(_ name: String, _ breed: PetBreed = .britishShorthair, at date: Date) -> SyncedPet {
        SyncedPet(profile: PetProfile(name: name, breed: breed), updatedAt: date)
    }

    private var samples: [SyncDocument] {
        [
            .empty,
            SyncDocument(
                pet: pet("Mochi", at: early),
                tallies: ["a": SyncTally(earned: 120, spent: 30)],
                unlocks: ["accessory.beanie"],
                studyDays: ["2027-01-01", "2027-01-02"]
            ),
            SyncDocument(
                pet: pet("Biscuit", .goldenRetriever, at: late),
                tallies: ["a": SyncTally(earned: 90, spent: 45), "b": SyncTally(earned: 40)],
                unlocks: ["accessory.roundGlasses", "accessory.fromTheFuture"],
                studyDays: ["2027-01-03"],
                longestStreak: 9
            ),
            SyncDocument(
                pet: pet("Tofu", at: late),
                tallies: ["c": SyncTally(earned: 5)],
                studyDays: ["2026-12-31"]
            ),
        ]
    }

    func testMergeIsCommutativeAssociativeAndIdempotent() {
        for a in samples {
            XCTAssertEqual(a.merged(with: a), a)
            for b in samples {
                XCTAssertEqual(a.merged(with: b), b.merged(with: a))
                for c in samples {
                    XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
                }
            }
        }
    }

    func testMergeNeverLosesProgress() {
        let merged = samples[1].merged(with: samples[2])
        XCTAssertEqual(merged.tallies["a"], SyncTally(earned: 120, spent: 45))
        XCTAssertEqual(merged.tallies["b"], SyncTally(earned: 40))
        XCTAssertEqual(merged.earned, 160)
        XCTAssertEqual(merged.spent, 45)
        XCTAssertEqual(merged.unlocks, ["accessory.beanie", "accessory.roundGlasses", "accessory.fromTheFuture"])
        XCTAssertEqual(merged.studyDays, ["2027-01-01", "2027-01-02", "2027-01-03"])
        XCTAssertEqual(merged.longestStreak, 9)
    }

    func testNewestPetLookWins() {
        let merged = samples[1].merged(with: samples[2])
        XCTAssertEqual(merged.pet?.profile.name, "Biscuit")
        XCTAssertEqual(merged.pet?.profile.breed, .goldenRetriever)
        XCTAssertEqual(SyncDocument.empty.merged(with: samples[1]).pet?.profile.name, "Mochi")
    }

    func testEqualTimestampsPickTheSamePetEitherWay() {
        let first = SyncDocument(pet: pet("Alpha", at: early))
        let second = SyncDocument(pet: pet("Beta", at: early))
        XCTAssertEqual(first.merged(with: second).pet, second.merged(with: first).pet)
    }

    func testLedgerSumsMacsAndSkipsUnknownItems() {
        let ledger = samples[2].ledger
        XCTAssertEqual(ledger.earned, 130)
        XCTAssertEqual(ledger.spent, 45)
        XCTAssertEqual(ledger.purchased, [.accessory(.roundGlasses)])
    }
}

final class SyncDocumentLocalStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func save(earned: Int, spent: Int = 0, purchased: Set<PetItem> = [], name: String = "Mochi") -> PetSave {
        PetSave(
            profile: PetProfile(name: name, breed: .britishShorthair),
            ledger: PetPointsLedger(earned: earned, spent: spent, purchased: purchased)
        )
    }

    func testFirstSignInMergesProgressFromBothMacs() {
        // Mac A has local progress; the account already has Mac B's.
        let server = SyncDocument.empty.recording(save(earned: 50, name: "Tofu"), changedAt: now, device: "b")
        let local = SyncDocument.empty.recording(
            save(earned: 100, spent: 30, purchased: [.accessory(.beanie)]),
            changedAt: now.addingTimeInterval(-60), device: "a"
        )
        let merged = local.merged(with: server)
        let adopted = merged.applied(to: save(earned: 100, spent: 30, purchased: [.accessory(.beanie)]))
        XCTAssertEqual(adopted.ledger.earned, 150)
        XCTAssertEqual(adopted.ledger.spent, 30)
        XCTAssertTrue(adopted.ledger.owns(.accessory(.beanie)))
        XCTAssertEqual(adopted.profile.name, "Tofu", "the newer look wins")
    }

    func testLaterRecordingCountsOnlyWhatThisMacAdded() {
        let base = SyncDocument(tallies: ["a": SyncTally(earned: 100), "b": SyncTally(earned: 50)])
        // The Mac adopted 150 points, then earned 10 more.
        let next = base.recording(save(earned: 160), changedAt: nil, device: "a")
        XCTAssertEqual(next.tallies["a"], SyncTally(earned: 110))
        XCTAssertEqual(next.tallies["b"], SyncTally(earned: 50))
        XCTAssertEqual(next.earned, 160)
    }

    func testOfflineProgressOnTwoMacsAddsUp() {
        let base = SyncDocument(tallies: ["a": SyncTally(earned: 100), "b": SyncTally(earned: 50)])
        let fromA = base.recording(save(earned: 170), changedAt: nil, device: "a")
        let fromB = base.recording(save(earned: 175), changedAt: nil, device: "b")
        XCTAssertEqual(fromA.merged(with: fromB).earned, 150 + 20 + 25)
    }

    func testLimitedItemsSyncAsGrantedNotBought() {
        var local = save(earned: 40)
        local.ledger.grant(.accessory(.flameHeadband))
        let document = SyncDocument.empty.recording(local, changedAt: nil, device: "a")
        XCTAssertTrue(document.unlocks.contains(PetItem.accessory(.flameHeadband).id))

        let otherMac = document.applied(to: save(earned: 0))
        XCTAssertEqual(otherMac.ledger.granted, [.accessory(.flameHeadband)])
        XCTAssertTrue(otherMac.ledger.purchased.isEmpty)
        XCTAssertEqual(otherMac.ledger.spent, 0, "a limited item costs nothing on any Mac")
    }

    func testServerGrantedEventItemArrivesThroughUnlocks() {
        let server = SyncDocument(unlocks: [PetItem.accessory(.backwardsCap).id])
        let adopted = server.applied(to: save(earned: 10))
        XCTAssertTrue(adopted.ledger.owns(.accessory(.backwardsCap)))
    }

    func testApplyingADocumentNeverTakesAGrantBack() {
        var local = save(earned: 0)
        local.ledger.grant(.accessory(.teamMedal))
        let adopted = SyncDocument.empty.applied(to: local)
        XCTAssertTrue(adopted.ledger.owns(.accessory(.teamMedal)))
    }

    func testRecordingWithoutAChangeKeepsTheSyncedLook() {
        let base = SyncDocument(pet: SyncedPet(profile: PetProfile(name: "Tofu", breed: .calico), updatedAt: now))
        let next = base.recording(save(earned: 0), changedAt: nil, device: "a")
        XCTAssertEqual(next.pet?.profile.name, "Tofu")
    }

    func testAppliedKeepsLocalFocusBookkeepingAndRestrictsTheLook() {
        var local = save(earned: 0)
        local.creditedFocusCount = 4
        local.creditedFocusSource = "focus"
        let wearing = PetProfile(name: "Tofu", breed: .calico, accessories: [.roundGlasses])
        let document = SyncDocument(pet: SyncedPet(profile: wearing, updatedAt: now))
        let applied = document.applied(to: local)
        XCTAssertEqual(applied.creditedFocusCount, 4)
        XCTAssertEqual(applied.creditedFocusSource, "focus")
        XCTAssertEqual(applied.profile.accessories, [], "glasses that are not owned come off")
    }

    func testSignedOutSaveIsUntouchedWithoutASyncedPet() {
        let local = save(earned: 42, name: "Pip")
        let applied = SyncDocument.empty.recording(local, changedAt: nil, device: "a").applied(to: local)
        XCTAssertEqual(applied, local)
    }
}

final class SyncDocumentStreakTests: XCTestCase {
    func testCurrentStreakEndsTodayOrYesterday() {
        let document = SyncDocument(studyDays: ["2027-02-27", "2027-02-28", "2027-03-01", "2027-02-20"])
        XCTAssertEqual(document.currentStreak(today: "2027-03-01"), 3)
        XCTAssertEqual(document.currentStreak(today: "2027-03-02"), 3)
        XCTAssertEqual(document.currentStreak(today: "2027-03-03"), 0)
        XCTAssertEqual(document.longestStreak, 3)
    }

    func testDaysFromTwoMacsJoinIntoOneStreak() {
        let macA = SyncDocument(studyDays: ["2027-01-01", "2027-01-03"])
        let macB = SyncDocument(studyDays: ["2027-01-02"])
        let merged = macA.merged(with: macB)
        XCTAssertEqual(merged.currentStreak(today: "2027-01-03"), 3)
        XCTAssertEqual(merged.longestStreak, 3)
    }

    func testOldDaysAreTrimmedButTheLongestStreakStays() {
        var document = SyncDocument()
        let start = SyncDays.date(of: "2025-01-01")!
        let days = (0..<(SyncDocument.keptStudyDays + 50)).map {
            SyncDays.string(of: start.addingTimeInterval(Double($0) * 86_400))
        }
        document.addStudyDays(days)
        XCTAssertEqual(document.studyDays.count, SyncDocument.keptStudyDays)
        XCTAssertEqual(document.longestStreak, SyncDocument.keptStudyDays + 50)
        XCTAssertTrue(document.studyDays.contains(days.last!))
    }

    func testInvalidDaysAreIgnored() {
        let document = SyncDocument(studyDays: ["2027-02-30", "yesterday", "2027-1-01", "2027-01-05"])
        XCTAssertEqual(document.studyDays, ["2027-01-05"])
    }
}

final class SyncDocumentCodingTests: XCTestCase {
    func testRoundTripsWithASchemaVersion() throws {
        let document = SyncDocument(
            pet: SyncedPet(profile: PetProfile(name: "Mochi", breed: .tuxedo, accessories: [.scarf]),
                           updatedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            tallies: ["a": SyncTally(earned: 12, spent: 3)],
            unlocks: ["accessory.beanie", "hat.fromTheFuture"],
            studyDays: ["2027-01-01"]
        )
        let data = try document.encoded()
        XCTAssertEqual(VersionedJSON.version(of: data), SyncDocument.schema.current)
        XCTAssertEqual(try SyncDocument.decode(data), document)
    }

    func testABadFieldKeepsTheRest() throws {
        let json = """
        {"schemaVersion": 1, "pet": {"profile": {"breed": "notABreed"}}, "tallies": {"a": {"earned": 7, "spent": 0}},
         "unlocks": "oops", "studyDays": ["2027-01-01"], "somethingNew": true}
        """
        let document = try SyncDocument.decode(Data(json.utf8))
        XCTAssertNil(document.pet)
        XCTAssertEqual(document.earned, 7)
        XCTAssertEqual(document.unlocks, [])
        XCTAssertEqual(document.studyDays, ["2027-01-01"])
    }

    func testAnEmptyObjectDecodesAsEmpty() throws {
        XCTAssertEqual(try SyncDocument.decode(Data("{}".utf8)), .empty)
    }
}
