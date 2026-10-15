import Foundation
import TabbiKitCore
import XCTest

/// Pins the Closet's economy, every item's price, tier, shelf and unlock
/// rule, how study turns into points, and what the Closet does with them
/// (buying, wearing, level-up awards, the next unlock, limited edition
/// milestones and seasonal events, extra streak freezes), to the golden
/// fixture `shared/fixtures/closet/closet.json`.
///
/// The Windows port reads its prices and rules from the same file and
/// replays the recorded inputs through its own Closet, so a pet costs and
/// earns the same on both platforms. Run with `TABBI_RECORD_FIXTURES=1` to
/// rewrite it after an intended change.
final class ClosetGoldenTests: XCTestCase {
    func testClosetMatchesGoldenFixture() throws {
        let url = ClosetGoldenFixture.url
        let current = ClosetGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(ClosetGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.rules, current.rules, "Points rules changed")
        XCTAssertEqual(stored.tiers, current.tiers, "Price tiers changed")
        XCTAssertEqual(stored.items.map(\.id), current.items.map(\.id), "Item order changed")
        for (old, new) in zip(stored.items, current.items) {
            XCTAssertEqual(old, new, "Item \(old.id)")
        }
        XCTAssertEqual(stored.catalog, current.catalog, "Shop order or shelves changed")
        XCTAssertEqual(stored.points, current.points, "Points per session changed")
        XCTAssertEqual(stored.sharedPoints, current.sharedPoints, "Shared session points changed")
        XCTAssertEqual(stored.pace, current.pace, "Typical pace changed")
        XCTAssertEqual(stored.tierLookups, current.tierLookups, "Tier lookups changed")
        Self.compare(stored.ledgers, current.ledgers, "Ledger", name: \.name)
        Self.compare(stored.unlockProgress, current.unlockProgress, "Unlock progress", name: \.name)
        XCTAssertEqual(stored.closets.map(\.name), current.closets.map(\.name))
        for (old, new) in zip(stored.closets, current.closets) {
            XCTAssertEqual(old.start, new.start, old.name)
            XCTAssertEqual(old.initial, new.initial, "Closet \(old.name), initial")
            XCTAssertEqual(old.steps.count, new.steps.count, old.name)
            for (index, (oldStep, newStep)) in zip(old.steps, new.steps).enumerated() {
                XCTAssertEqual(oldStep, newStep, "Closet \(old.name), step \(index) (\(oldStep.op.op))")
            }
        }
        Self.compare(stored.milestones, current.milestones, "Milestones", name: \.name)
        Self.compare(stored.freezes, current.freezes, "Streak freezes", name: \.name)
        Self.compare(stored.windows, current.windows, "Event windows") { "\($0.event) in \($0.timeZone)" }
        Self.compare(stored.moments, current.moments, "Limited shelves") { "\($0.timeZone) at \($0.at)" }
        Self.compare(stored.seasonalTallies, current.seasonalTallies, "Seasonal tally", name: \.name)
        XCTAssertEqual(stored, current, "The Closet no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(ClosetGoldenFixture.self, from: Data(contentsOf: ClosetGoldenFixture.url))
        typealias Fixture = ClosetGoldenFixture
        XCTAssertEqual(stored.points.map { Fixture.pointsCase(minutes: $0.minutes, completed: $0.completed) },
                       stored.points)
        XCTAssertEqual(stored.sharedPoints.map {
            Fixture.sharedPointsCase(minutes: $0.minutes, friends: $0.friends, finished: $0.finished)
        }, stored.sharedPoints)
        XCTAssertEqual(stored.pace.map { Fixture.paceCase(points: $0.points) }, stored.pace)
        XCTAssertEqual(stored.tierLookups.map { Fixture.tierLookup(cost: $0.cost) }, stored.tierLookups)
        for ledger in stored.ledgers {
            XCTAssertEqual(Fixture.decodeLedger(ledger.json), ledger.output, ledger.name)
        }
        for progress in stored.unlockProgress {
            XCTAssertEqual(Fixture.runUnlockProgress(progress.input), progress.output, progress.name)
        }
        for closet in stored.closets {
            let replayed = Fixture.runCloset(name: closet.name, start: closet.start, ops: closet.steps.map(\.op))
            XCTAssertEqual(replayed.initial, closet.initial, "Closet \(closet.name), initial")
            XCTAssertEqual(replayed.steps, closet.steps, "Closet \(closet.name)")
        }
        for milestone in stored.milestones {
            XCTAssertEqual(Fixture.runMilestones(milestone.input), milestone.output, milestone.name)
        }
        for freeze in stored.freezes {
            XCTAssertEqual(Fixture.runFreezes(freeze.input), freeze.output, freeze.name)
        }
        for window in stored.windows {
            XCTAssertEqual(Fixture.window(timeZone: window.timeZone, event: window.event, from: window.from,
                                          count: window.runs.count), window, "\(window.event) in \(window.timeZone)")
        }
        for moment in stored.moments {
            XCTAssertEqual(Fixture.moment(timeZone: moment.timeZone, at: moment.at), moment,
                           "\(moment.timeZone) at \(moment.at)")
        }
        for tally in stored.seasonalTallies {
            XCTAssertEqual(Fixture.seasonalTally(tally.input), tally.output, tally.name)
        }
    }

    private static func compare<Case: Equatable>(_ stored: [Case], _ current: [Case], _ section: String,
                                                 name: (Case) -> String) {
        XCTAssertEqual(stored.map(name), current.map(name), "\(section) cases changed")
        for (old, new) in zip(stored, current) {
            XCTAssertEqual(old, new, "\(section) \(name(old))")
        }
    }
}

/// Every Closet item with its price, tier and unlock rule, the points
/// rules, and sample evaluations of the shop, the ledger, awards, limited
/// edition milestones, seasonal events and streak freezes.
struct ClosetGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.closet.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/closet/closet.json")
    }

    // MARK: Catalog

    struct Rules: Codable, Equatable {
        var pointsPerMinute: Int
        var minimumMinutes: Int
        var completionBonus: Int
        var bonusMinutes: Int
        var sharedBonusPerFriend: Int
        var maxSharedBonus: Int
        var typicalBlocksPerDay: Int
        var typicalBlockMinutes: Int
        var typicalStudyDaysPerWeek: Int
        var pointsPerTypicalBlock: Int
        var pointsPerTypicalDay: Int
        var pointsPerTypicalWeek: Int
        var streakFreezeFreePerWeek: Int
        var streakFreezePrice: Int
        var streakFreezeMaxHeld: Int
        var unlockNearSessions: Int
        var minutesForStudyDay: Double
        var latestRelease: Int
        /// Each milestone's goal in its own unit: days, minutes or sessions.
        var milestoneGoals: [String: Int]
    }

    struct Tier: Codable, Equatable {
        var tier: String
        var minPrice: Int
        var maxPrice: Int
    }

    /// How a limited edition item is earned: `source` is `milestone` (with
    /// the milestone as `sourceID`), `event` (granted by the server for the
    /// event `sourceID`) or `season` (focus during the seasonal event
    /// `sourceID` for `seasonFocusMinutes`).
    struct Limited: Codable, Equatable {
        var edition: String
        var source: String
        var sourceID: String
        var milestoneGoal: Int?
        var seasonFocusMinutes: Int?
        var effect: String?
    }

    struct Item: Codable, Equatable {
        var id: String
        var kind: String
        var cost: Int
        var tier: String
        var theme: String
        var release: Int
        var isFree: Bool
        var isLimited: Bool
        var isNew: Bool
        /// Accessories only: the slot it takes, and whether it also covers
        /// the eyes (so no face item can be worn with it).
        var slot: String?
        var coversEyes: Bool?
        var limited: Limited?
    }

    struct Shelf: Codable, Equatable {
        var theme: String
        var items: [String]
    }

    struct Catalog: Codable, Equatable {
        /// Every item but the limited edition ones, cheapest first.
        var shopOrder: [String]
        /// The wardrobe grid: the shop without "no outfit".
        var wardrobe: [String]
        var limitedShelf: [String]
        var shelves: [Shelf]
    }

    // MARK: Points

    struct PointsCase: Codable, Equatable {
        var minutes: Int
        var completed: Bool
        var points: Int
    }

    struct SharedPointsCase: Codable, Equatable {
        var minutes: Int
        var friends: Int
        var finished: Bool
        var points: Int
    }

    struct PaceCase: Codable, Equatable {
        var points: Int
        var typicalBlocks: Int
        var typicalDays: Int
        var typicalWeeks: Int
        var studyToEarn: String
    }

    struct TierLookup: Codable, Equatable {
        var cost: Int
        var tier: String?
    }

    // MARK: Ledger

    struct LedgerOutput: Codable, Equatable {
        var earned: Int
        var spent: Int
        var balance: Int
        var purchased: [String]
        var granted: [String]
        var nextUnlock: String?
        /// The ledger encoded again, with sorted keys and no whitespace.
        var encoded: String
    }

    /// A stored ledger (`json`) decoded; no `output` when it does not decode.
    struct LedgerCase: Codable, Equatable {
        var name: String
        var json: String
        var output: LedgerOutput?
    }

    struct UnlockInput: Codable, Equatable {
        var balance: Int
        var earned: Int
        var purchased: [String]
        var pointsPerSession: Int?
    }

    struct UnlockOutput: Codable, Equatable {
        var item: String
        var cost: Int
        var balanceBefore: Int
        var balance: Int
        var pointsPerSession: Int
        var missing: Int
        var isReady: Bool
        var fractionBefore: Double
        var fraction: Double
        var sessionsLeft: Int
        var isNear: Bool
        var line: String
    }

    struct UnlockCase: Codable, Equatable {
        var name: String
        var input: UnlockInput
        var output: UnlockOutput?
    }

    // MARK: Closet

    struct ClosetStart: Codable, Equatable {
        var breed: String
        var outfit: String
        var accessories: [String]
        var earned: Int
        var spent: Int
        var purchased: [String]
        var granted: [String]
    }

    /// One thing done to the Closet: `study`, `gift`, `party`, `record`,
    /// `tap`, `buy` or `grant`, with the fields that operation reads.
    struct ClosetOp: Codable, Equatable {
        var op: String
        var item: String?
        var minutes: Int?
        var completed: Bool?
        var friends: Int?
        var finished: Bool?
        var points: Int?
        var ids: [String]?
        var recordID: String?
        var source: String?
        var outcome: String?
        var quantity: Double?
        var at: Double?
    }

    struct Award: Codable, Equatable {
        var completedSessions: Int
        var minutes: Int
        var points: Int
        var unlocked: [String]
        var isLevelUp: Bool
        var headline: String
        var unlockLine: String?
        var pointsText: String
    }

    struct ClosetOutcome: Codable, Equatable {
        var points: Int?
        var award: Award?
        var progress: UnlockOutput?
        var tap: String?
        var purchase: String?
        var missing: Int?
        var granted: [String]?
    }

    struct ClosetSnapshot: Codable, Equatable {
        var earned: Int
        var spent: Int
        var balance: Int
        var purchased: [String]
        var granted: [String]
        var outfit: String
        var accessories: [String]
        var nextUnlock: String?
        var nextUnlockMissing: Int?
        /// Every item's state: `wearing`, `owned`, `affordable`, `locked`
        /// (short of `cost - balance` points) or `unearned`.
        var states: [String: String]
    }

    struct ClosetStep: Codable, Equatable {
        var op: ClosetOp
        var outcome: ClosetOutcome
        var after: ClosetSnapshot
    }

    struct ClosetScenario: Codable, Equatable {
        var name: String
        var start: ClosetStart
        var initial: ClosetSnapshot
        var steps: [ClosetStep]
    }

    // MARK: Milestones and events

    /// An activity record; `quantity` is in `unit` and `outcome` is the
    /// `outcome` metadata.
    struct Record: Codable, Equatable {
        var id: String
        var source: String
        var kind: String
        var unit: String
        var start: Double
        var end: Double
        var quantity: Double?
        var outcome: String?
    }

    struct MilestoneInput: Codable, Equatable {
        var timeZone: String
        var today: Double
        var records: [Record]
    }

    struct LimitedProgress: Codable, Equatable {
        var value: Int
        var goal: Int
        var label: String
        var fraction: Double
    }

    struct MilestoneRow: Codable, Equatable {
        var milestone: String
        var value: Int
        var isReached: Bool
        var progress: LimitedProgress
    }

    struct MilestoneOutput: Codable, Equatable {
        var focusMinutes: Double
        var studyDays: [String]
        var finishedPartySessions: Int
        var longestStreak: Int
        var currentStreak: Int
        var milestones: [MilestoneRow]
        /// What `unlockMilestones` grants a closet that owns nothing yet.
        var unlocked: [String]
    }

    struct MilestoneCase: Codable, Equatable {
        var name: String
        var input: MilestoneInput
        var output: MilestoneOutput
    }

    struct FreezeInput: Codable, Equatable {
        var timeZone: String
        var firstWeekday: Int
        var earned: Int
        var studyDays: [String]
        /// When each purchase is tried, in order.
        var buys: [Double]
    }

    struct FreezeBuy: Codable, Equatable {
        var at: Double
        var result: String
        var missing: Int?
        var balance: Int
        var extraFreezes: Int
        var freezesReady: Int
    }

    struct FreezeCase: Codable, Equatable {
        var name: String
        var input: FreezeInput
        var output: [FreezeBuy]
    }

    /// One run of a seasonal event: local midnight of its first day to local
    /// midnight after its last.
    struct EventRun: Codable, Equatable {
        var event: String
        var id: String
        var start: Double
        var end: Double
    }

    /// The next `runs.count` runs of `event` after `from`, each found after
    /// the previous run's start.
    struct WindowCase: Codable, Equatable {
        var timeZone: String
        var event: String
        var from: Double
        var runs: [EventRun]
    }

    struct Featured: Codable, Equatable {
        var run: EventRun
        var isActive: Bool
    }

    struct LimitedShelfRow: Codable, Equatable {
        var kind: String
        var run: EventRun?
        var isActive: Bool?
        var items: [String]
    }

    struct MomentCase: Codable, Equatable {
        var timeZone: String
        var at: Double
        var active: [EventRun]
        var next: EventRun?
        var featured: Featured?
        var shelves: [LimitedShelfRow]
    }

    struct TallyInput: Codable, Equatable {
        var timeZone: String
        var records: [Record]
        var queries: [Double]
    }

    struct TallyRun: Codable, Equatable {
        var id: String
        var focusMinutes: Double
        var earned: [String]
        var nextReward: String?
    }

    struct ItemProgress: Codable, Equatable {
        var item: String
        var value: Int
        var goal: Int
        var label: String
    }

    struct TallyQuery: Codable, Equatable {
        var at: Double
        var items: [ItemProgress]
    }

    struct TallyOutput: Codable, Equatable {
        var earned: [String]
        var runs: [TallyRun]
        var progress: [TallyQuery]
        /// What `unlockSeasonal` grants a closet that owns nothing yet.
        var unlocked: [String]
    }

    struct TallyCase: Codable, Equatable {
        var name: String
        var input: TallyInput
        var output: TallyOutput
    }

    var schema = Self.schemaName
    var version = 1
    var rules: Rules
    var tiers: [Tier]
    var items: [Item]
    var catalog: Catalog
    var points: [PointsCase]
    var sharedPoints: [SharedPointsCase]
    var pace: [PaceCase]
    var tierLookups: [TierLookup]
    var ledgers: [LedgerCase]
    var unlockProgress: [UnlockCase]
    var closets: [ClosetScenario]
    var milestones: [MilestoneCase]
    var freezes: [FreezeCase]
    var windows: [WindowCase]
    var moments: [MomentCase]
    var seasonalTallies: [TallyCase]

    static func current() -> ClosetGoldenFixture {
        ClosetGoldenFixture(
            rules: Rules(
                pointsPerMinute: PetPointsRules.pointsPerMinute, minimumMinutes: PetPointsRules.minimumMinutes,
                completionBonus: PetPointsRules.completionBonus, bonusMinutes: PetPointsRules.bonusMinutes,
                sharedBonusPerFriend: PetPointsRules.sharedBonusPerFriend, maxSharedBonus: PetPointsRules.maxSharedBonus,
                typicalBlocksPerDay: PetEconomy.typicalBlocksPerDay, typicalBlockMinutes: PetEconomy.typicalBlockMinutes,
                typicalStudyDaysPerWeek: PetEconomy.typicalStudyDaysPerWeek,
                pointsPerTypicalBlock: PetEconomy.pointsPerTypicalBlock, pointsPerTypicalDay: PetEconomy.pointsPerTypicalDay,
                pointsPerTypicalWeek: PetEconomy.pointsPerTypicalWeek,
                streakFreezeFreePerWeek: StreakFreezeRules.freePerWeek, streakFreezePrice: StreakFreezeRules.price,
                streakFreezeMaxHeld: StreakFreezeRules.maxHeld, unlockNearSessions: UnlockProgress.nearSessions,
                minutesForStudyDay: PetMilestoneProgress.minutesForStudyDay, latestRelease: PetItem.latestRelease,
                milestoneGoals: Dictionary(uniqueKeysWithValues: PetMilestone.allCases.map { ($0.rawValue, $0.goal) })
            ),
            tiers: PetPriceTier.allCases.map {
                Tier(tier: tierName($0), minPrice: $0.priceRange.lowerBound, maxPrice: $0.priceRange.upperBound)
            },
            items: PetItem.allCases.map(itemRow),
            catalog: Catalog(
                shopOrder: PetItem.shopItems.map(\.id),
                wardrobe: PetCloset.wardrobe.map(\.id),
                limitedShelf: PetCloset.limitedShelf.map(\.id),
                shelves: PetCloset.shelves.map { Shelf(theme: $0.theme.rawValue, items: $0.items.map(\.id)) }
            ),
            points: [0, 1, 4, 5, 6, 24, 25, 26, 50, 90, 180].flatMap { minutes in
                [true, false].map { pointsCase(minutes: minutes, completed: $0) }
            },
            sharedPoints: sampleSharedPoints.map { sharedPointsCase(minutes: $0.0, friends: $0.1, finished: $0.2) },
            pace: [-5, 0, 1, 34, 35, 36, 70, 105, 106, 210, 524, 525, 526, 1050, 1051, 2100, 2101, 5000].map {
                paceCase(points: $0)
            },
            tierLookups: [-1, 0, 1, 104, 105, 106, 209, 210, 525, 526, 1049, 1050, 2100, 2101].map { tierLookup(cost: $0) },
            ledgers: sampleLedgers.map { LedgerCase(name: $0.0, json: $0.1, output: decodeLedger($0.1)) },
            unlockProgress: sampleUnlocks.map { UnlockCase(name: $0.0, input: $0.1, output: runUnlockProgress($0.1)) },
            closets: sampleClosets.map { runCloset(name: $0.0, start: $0.1, ops: $0.2) },
            milestones: sampleMilestones.map { MilestoneCase(name: $0.0, input: $0.1, output: runMilestones($0.1)) },
            freezes: sampleFreezes.map { FreezeCase(name: $0.0, input: $0.1, output: runFreezes($0.1)) },
            windows: sampleZones.flatMap { zone in
                SeasonalEventCatalog.bundled.events.map {
                    window(timeZone: zone, event: $0.id, from: local("UTC", 2025, 12, 1), count: 3)
                }
            },
            moments: sampleMoments.map { moment(timeZone: $0.0, at: $0.1) },
            seasonalTallies: sampleTallies.map { TallyCase(name: $0.0, input: $0.1, output: seasonalTally($0.1)) }
        )
    }

    // MARK: Running

    static func pointsCase(minutes: Int, completed: Bool) -> PointsCase {
        PointsCase(minutes: minutes, completed: completed,
                   points: PetPointsRules.points(forMinutes: minutes, completed: completed))
    }

    static func sharedPointsCase(minutes: Int, friends: Int, finished: Bool) -> SharedPointsCase {
        SharedPointsCase(minutes: minutes, friends: friends, finished: finished,
                         points: PetPointsRules.sharedPoints(forMinutes: minutes, friends: friends, finished: finished))
    }

    static func paceCase(points: Int) -> PaceCase {
        PaceCase(points: points, typicalBlocks: PetEconomy.typicalBlocks(toEarn: points),
                 typicalDays: PetEconomy.typicalDays(toEarn: points), typicalWeeks: PetEconomy.typicalWeeks(toEarn: points),
                 studyToEarn: PetEconomy.studyToEarn(points))
    }

    static func tierLookup(cost: Int) -> TierLookup {
        TierLookup(cost: cost, tier: PetPriceTier(cost: cost).map(tierName))
    }

    static func decodeLedger(_ json: String) -> LedgerOutput? {
        guard let ledger = try? JSONDecoder().decode(PetPointsLedger.self, from: Data(json.utf8)) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(ledger)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return LedgerOutput(earned: ledger.earned, spent: ledger.spent, balance: ledger.balance,
                            purchased: ledger.purchased.map(\.id).sorted(), granted: ledger.granted.map(\.id).sorted(),
                            nextUnlock: ledger.nextUnlock?.id, encoded: encoded)
    }

    static func runUnlockProgress(_ input: UnlockInput) -> UnlockOutput? {
        let ledger = PetPointsLedger(earned: input.balance, purchased: Set(input.purchased.map(petItem)))
        return UnlockProgress(balance: input.balance, earned: input.earned, ledger: ledger,
                              pointsPerSession: input.pointsPerSession).map(unlockOutput)
    }

    static func runCloset(name: String, start: ClosetStart, ops: [ClosetOp]) -> ClosetScenario {
        let profile = PetProfile(name: "Kit", breed: PetBreed(rawValue: start.breed)!,
                                 outfit: PetOutfit(rawValue: start.outfit)!,
                                 accessories: start.accessories.map { PetAccessory(rawValue: $0)! })
        let ledger = PetPointsLedger(earned: start.earned, spent: start.spent,
                                     purchased: Set(start.purchased.map(petItem)), granted: Set(start.granted.map(petItem)))
        var closet = PetCloset(save: PetSave(profile: profile, ledger: ledger))
        let initial = snapshot(closet)
        var steps: [ClosetStep] = []
        for op in ops {
            var outcome = ClosetOutcome()
            switch op.op {
            case "study":
                outcome.points = closet.recordStudy(minutes: op.minutes!, completed: op.completed!)
            case "gift":
                closet.receiveGift(points: op.points!)
            case "party":
                let end = op.at!
                let session = PartySessionCompletion(method: "pomodoro", joinedAt: date(end - Double(op.minutes!) * 60),
                                                     endedAt: date(end), friendCount: op.friends!, finished: op.finished!)
                if let award = closet.credit(session) {
                    outcome.award = awardOutput(award)
                    outcome.progress = UnlockProgress(after: award, closet: closet).map(unlockOutput)
                }
            case "record":
                let end = op.at!
                let quantity = op.quantity!
                let record = ActivityRecord(
                    id: UUID(uuidString: op.recordID!)!, source: ModuleID(op.source!), kind: .focusCompleted,
                    start: date(end - quantity * 60), end: date(end), quantity: quantity, unit: .minutes,
                    metadata: op.outcome.map { [ActivityMetadata.outcome: $0] } ?? [:]
                )
                if let award = closet.credit(record) {
                    outcome.award = awardOutput(award)
                    outcome.progress = UnlockProgress(after: award, closet: closet).map(unlockOutput)
                }
            case "tap":
                switch closet.tap(petItem(op.item!)) {
                case .wore: outcome.tap = "wore"
                case .tookOff: outcome.tap = "tookOff"
                case .boughtAndWore: outcome.tap = "boughtAndWore"
                case .needsPoints(let missing):
                    outcome.tap = "needsPoints"
                    outcome.missing = missing
                case .notEarnedYet: outcome.tap = "notEarnedYet"
                }
            case "buy":
                var save = closet.save
                do {
                    try save.ledger.buy(petItem(op.item!))
                    outcome.purchase = "bought"
                } catch {
                    switch error {
                    case .alreadyOwned: outcome.purchase = "alreadyOwned"
                    case .notForSale: outcome.purchase = "notForSale"
                    case .notEnoughPoints(let missing):
                        outcome.purchase = "notEnoughPoints"
                        outcome.missing = missing
                    }
                }
                closet = PetCloset(save: save)
            case "grant":
                outcome.granted = closet.applyGrants(op.ids!).map(\.id)
            default:
                preconditionFailure("Unknown closet op \(op.op)")
            }
            steps.append(ClosetStep(op: op, outcome: outcome, after: snapshot(closet)))
        }
        return ClosetScenario(name: name, start: start, initial: initial, steps: steps)
    }

    static func runMilestones(_ input: MilestoneInput) -> MilestoneOutput {
        let calendar = zoneCalendar(input.timeZone)
        let today = date(input.today)
        let progress = PetMilestoneProgress(records: input.records.map(activityRecord), calendar: calendar)
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo)))
        let unlocked = closet.unlockMilestones(progress, calendar: calendar)
        return MilestoneOutput(
            focusMinutes: progress.focusMinutes,
            studyDays: progress.studyDays.map(\.rawValue),
            finishedPartySessions: progress.finishedPartySessions,
            longestStreak: progress.longestStreak(calendar: calendar),
            currentStreak: progress.currentStreak(today: today, calendar: calendar),
            milestones: PetMilestone.allCases.map { milestone in
                let value = progress.value(of: milestone, today: today, calendar: calendar)
                return MilestoneRow(milestone: milestone.rawValue, value: value,
                                    isReached: progress.isReached(milestone, calendar: calendar),
                                    progress: limitedProgress(milestone.progress(value: value)))
            },
            unlocked: unlocked.map(\.id)
        )
    }

    static func runFreezes(_ input: FreezeInput) -> [FreezeBuy] {
        let calendar = zoneCalendar(input.timeZone, firstWeekday: input.firstWeekday)
        let days = input.studyDays.map { PlannerDayKey(rawValue: $0)! }
        var ledger = PetPointsLedger(earned: input.earned)
        return input.buys.map { at in
            let streak = StudyStreak(studyDays: days, freezePurchases: ledger.streakFreezes, today: date(at),
                                     calendar: calendar)
            var result = "bought"
            var missing: Int?
            do throws(StreakFreezePurchaseError) {
                try ledger.buyStreakFreeze(for: streak, at: date(at))
            } catch {
                switch error {
                case .holdingLimit: result = "holdingLimit"
                case .notEnoughPoints(let short):
                    result = "notEnoughPoints"
                    missing = short
                }
            }
            let after = StudyStreak(studyDays: days, freezePurchases: ledger.streakFreezes, today: date(at),
                                    calendar: calendar)
            return FreezeBuy(at: at, result: result, missing: missing, balance: ledger.balance,
                             extraFreezes: after.extraFreezes, freezesReady: after.freezesReady)
        }
    }

    static func window(timeZone: String, event id: String, from: Double, count: Int) -> WindowCase {
        let calendar = zoneCalendar(timeZone)
        let event = SeasonalEventCatalog.bundled.event(id: id)!
        var runs: [EventRun] = []
        var after = date(from)
        for _ in 0..<count {
            guard let occurrence = event.nextOccurrence(after: after, calendar: calendar) else { break }
            runs.append(eventRun(occurrence, calendar: calendar))
            after = occurrence.start
        }
        return WindowCase(timeZone: timeZone, event: id, from: from, runs: runs)
    }

    static func moment(timeZone: String, at: Double) -> MomentCase {
        let calendar = zoneCalendar(timeZone)
        let catalog = SeasonalEventCatalog.bundled
        let now = date(at)
        let featured = catalog.featured(at: now, calendar: calendar)
        return MomentCase(
            timeZone: timeZone, at: at,
            active: catalog.active(at: now, calendar: calendar).map { eventRun($0, calendar: calendar) },
            next: catalog.next(after: now, calendar: calendar).map { eventRun($0, calendar: calendar) },
            featured: featured.map { Featured(run: eventRun($0.occurrence, calendar: calendar), isActive: $0.isActive) },
            shelves: catalog.limitedShelves(at: now, calendar: calendar).map { shelfRow($0, calendar: calendar) }
        )
    }

    static func shelfRow(_ shelf: PetLimitedShelf, calendar: Calendar) -> LimitedShelfRow {
        let items = shelf.items.map(\.id)
        switch shelf.kind {
        case .event(let occurrence, let isActive):
            return LimitedShelfRow(kind: "event", run: eventRun(occurrence, calendar: calendar), isActive: isActive,
                                   items: items)
        case .milestones:
            return LimitedShelfRow(kind: "milestones", items: items)
        case .laterEvents:
            return LimitedShelfRow(kind: "laterEvents", items: items)
        }
    }

    static func seasonalTally(_ input: TallyInput) -> TallyOutput {
        let calendar = zoneCalendar(input.timeZone)
        let tally = SeasonalEventTally(catalog: .bundled, calendar: calendar, records: input.records.map(activityRecord))
        let seasonalItems = SeasonalEventCatalog.bundled.events.flatMap { $0.rewards.map(\.item) }
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo)))
        let unlocked = closet.unlockSeasonal(tally)
        return TallyOutput(
            earned: tally.earned.map(\.id),
            runs: tally.runs.sorted { $0.key < $1.key }.map {
                TallyRun(id: $0.key, focusMinutes: $0.value.focusMinutes, earned: $0.value.earned.map(\.id),
                         nextReward: $0.value.nextReward?.item.id)
            },
            progress: input.queries.map { at in
                TallyQuery(at: at, items: seasonalItems.compactMap { item in
                    tally.progress(of: item, at: date(at)).map {
                        ItemProgress(item: item.id, value: $0.value, goal: $0.goal, label: $0.label)
                    }
                })
            },
            unlocked: unlocked.map(\.id)
        )
    }

    // MARK: Conversions

    static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    static func zoneCalendar(_ timeZone: String, firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// Seconds since 1970 of a wall-clock time in `timeZone`.
    static func local(_ timeZone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                      _ second: Int = 0) -> Double {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return zoneCalendar(timeZone).date(from: components)!.timeIntervalSince1970
    }

    static func petItem(_ id: String) -> PetItem { PetItem(id: id)! }

    static func tierName(_ tier: PetPriceTier) -> String {
        switch tier {
        case .free: "free"
        case .starter: "starter"
        case .midTier: "midTier"
        case .showpiece: "showpiece"
        }
    }

    static func slotName(_ slot: PetAccessorySlot) -> String {
        switch slot {
        case .neck: "neck"
        case .face: "face"
        case .head: "head"
        case .back: "back"
        case .aura: "aura"
        }
    }

    static func itemRow(_ item: PetItem) -> Item {
        var row = Item(id: item.id, kind: "outfit", cost: item.cost, tier: tierName(item.tier), theme: item.theme.rawValue,
                       release: item.release, isFree: item.isFree, isLimited: item.isLimited, isNew: item.isNew)
        if case .accessory(let accessory) = item {
            row.kind = "accessory"
            row.slot = slotName(accessory.slot)
            row.coversEyes = accessory.coversEyes
        }
        if let edition = item.limitedEdition {
            let source: (String, String) = switch edition.source {
            case .milestone(let milestone): ("milestone", milestone.rawValue)
            case .event(let id): ("event", id)
            case .season(let id): ("season", id)
            }
            row.limited = Limited(edition: edition.rawValue, source: source.0, sourceID: source.1,
                                  milestoneGoal: edition.milestone?.goal,
                                  seasonFocusMinutes: edition.seasonalReward?.focusMinutes,
                                  effect: edition.effect?.rawValue)
        }
        return row
    }

    static func unlockOutput(_ progress: UnlockProgress) -> UnlockOutput {
        UnlockOutput(item: progress.item.id, cost: progress.cost, balanceBefore: progress.balanceBefore,
                     balance: progress.balance, pointsPerSession: progress.pointsPerSession, missing: progress.missing,
                     isReady: progress.isReady, fractionBefore: progress.fractionBefore, fraction: progress.fraction,
                     sessionsLeft: progress.sessionsLeft, isNear: progress.isNear, line: progress.line)
    }

    static func awardOutput(_ award: PetStudyAward) -> Award {
        Award(completedSessions: award.completedSessions, minutes: award.minutes, points: award.points,
              unlocked: award.unlocked.map(\.id), isLevelUp: award.isLevelUp, headline: award.headline,
              unlockLine: award.unlockLine, pointsText: award.pointsText)
    }

    static func limitedProgress(_ progress: PetLimitedProgress) -> LimitedProgress {
        LimitedProgress(value: progress.value, goal: progress.goal, label: progress.label, fraction: progress.fraction)
    }

    static func stateName(_ state: PetClosetItemState) -> String {
        switch state {
        case .wearing: "wearing"
        case .owned: "owned"
        case .affordable: "affordable"
        case .locked: "locked"
        case .unearned: "unearned"
        }
    }

    static func snapshot(_ closet: PetCloset) -> ClosetSnapshot {
        let ledger = closet.save.ledger
        var states: [String: String] = [:]
        for item in PetItem.allCases {
            states[item.id] = stateName(closet.state(of: item))
        }
        let next = closet.nextUnlock
        return ClosetSnapshot(
            earned: ledger.earned, spent: ledger.spent, balance: ledger.balance,
            purchased: ledger.purchased.map(\.id).sorted(), granted: ledger.granted.map(\.id).sorted(),
            outfit: closet.profile.outfit.rawValue, accessories: closet.profile.accessories.map(\.rawValue),
            nextUnlock: next?.item.id, nextUnlockMissing: next?.missing, states: states
        )
    }

    static func eventRun(_ occurrence: SeasonalEventOccurrence, calendar: Calendar) -> EventRun {
        EventRun(event: occurrence.event.id, id: occurrence.id(calendar: calendar),
                 start: occurrence.start.timeIntervalSince1970, end: occurrence.end.timeIntervalSince1970)
    }

    static func activityRecord(_ record: Record) -> ActivityRecord {
        ActivityRecord(id: UUID(uuidString: record.id)!, source: ModuleID(record.source), kind: ActivityKind(record.kind),
                       start: date(record.start), end: date(record.end), quantity: record.quantity,
                       unit: ActivityUnit(rawValue: record.unit),
                       metadata: record.outcome.map { [ActivityMetadata.outcome: $0] } ?? [:])
    }

    // MARK: Samples

    static let sampleZones = ["America/New_York", "Asia/Tokyo"]

    /// A fixed record id; `n` tells the records of one sample apart.
    static func recordID(_ n: Int) -> String {
        let digits = String(n)
        return "C1053700-0000-4000-8000-" + String(repeating: "0", count: 12 - digits.count) + digits
    }

    /// A record that ends at `end` and lasted `minutes`.
    static func record(_ n: Int, end: Double, minutes: Double, source: String = "focus", kind: String = "focus.completed",
                       unit: String = "min", outcome: String? = "completed") -> Record {
        Record(id: recordID(n), source: source, kind: kind, unit: unit, start: end - minutes * 60, end: end,
               quantity: minutes, outcome: outcome)
    }

    static var sampleSharedPoints: [(Int, Int, Bool)] {
        [
            (4, 3, true), (5, 0, true), (5, 2, true), (24, 1, true), (25, 0, true), (25, 1, true), (25, 2, true),
            (25, 3, true), (25, 4, true), (25, -2, true), (50, 3, true), (25, 3, false), (30, 1, false), (4, 1, false),
        ]
    }

    static var sampleLedgers: [(String, String)] {
        [
            ("empty object", "{}"),
            ("plain", #"{"earned":300,"spent":275,"purchased":["accessory.beanie","outfit.scrubs"]}"#),
            ("free scarf refunded", #"{"earned":100,"spent":65,"purchased":["accessory.scarf","accessory.beanie"]}"#),
            ("other free items dropped", #"{"earned":40,"spent":0,"purchased":["accessory.partyHat","outfit.none"]}"#),
            ("unknown ids skipped", #"{"earned":50,"spent":0,"purchased":["accessory.jetpack","hat.beanie","outfit.scrubs"]}"#),
            ("limited never purchased, shop never granted",
             #"{"earned":10,"spent":0,"purchased":["accessory.flameHeadband"],"granted":["accessory.flameHeadband","accessory.beanie","accessory.jetpack"]}"#),
            ("spent clamped to earned", #"{"earned":200,"spent":250,"purchased":[]}"#),
            ("negative values clamped", #"{"earned":-5,"spent":-20}"#),
            ("wrong type fails", #"{"earned":"lots"}"#),
            ("not an object fails", "[]"),
        ]
    }

    static var sampleUnlocks: [(String, UnlockInput)] {
        let everything = PetItem.shopItems.filter { !$0.isFree }.map(\.id)
        return [
            ("new pet", UnlockInput(balance: 0, earned: 0, purchased: [])),
            ("short of the beanie", UnlockInput(balance: 30, earned: 10, purchased: [])),
            ("session makes the beanie affordable", UnlockInput(balance: 40, earned: 10, purchased: [])),
            ("plain look past the beanie", UnlockInput(balance: 40, earned: 0, purchased: [])),
            ("earned more than the balance", UnlockInput(balance: 10, earned: 50, purchased: [])),
            ("owned starters skipped",
             UnlockInput(balance: 100, earned: 100, purchased: ["accessory.beanie", "accessory.roundGlasses"],
                         pointsPerSession: 45)),
            ("zero pace falls back to a typical block", UnlockInput(balance: 0, earned: 0, purchased: [], pointsPerSession: 0)),
            ("negative pace falls back to a typical block",
             UnlockInput(balance: 0, earned: 0, purchased: [], pointsPerSession: -5)),
            ("mid tier near", UnlockInput(balance: 200, earned: 0, purchased: Array(everything.prefix(6)))),
            ("showpiece far", UnlockInput(balance: 1000, earned: 35, purchased: Array(everything.prefix(17)),
                                          pointsPerSession: 10)),
            ("everything owned", UnlockInput(balance: 5000, earned: 0, purchased: everything)),
        ]
    }

    static var sampleClosets: [(String, ClosetStart, [ClosetOp])] {
        let zone = "America/New_York"
        let base = local(zone, 2026, 10, 14, 12)
        func at(_ hour: Int) -> Double { base + Double(hour) * 3600 }
        func tap(_ item: String) -> ClosetOp { ClosetOp(op: "tap", item: item) }
        func buy(_ item: String) -> ClosetOp { ClosetOp(op: "buy", item: item) }
        func study(_ minutes: Int, _ completed: Bool) -> ClosetOp {
            ClosetOp(op: "study", minutes: minutes, completed: completed)
        }
        func party(_ minutes: Int, friends: Int, finished: Bool, _ hour: Int) -> ClosetOp {
            ClosetOp(op: "party", minutes: minutes, friends: friends, finished: finished, at: at(hour))
        }
        func credit(_ n: Int, _ quantity: Double, source: String = "focus", outcome: String?, _ hour: Int) -> ClosetOp {
            ClosetOp(op: "record", recordID: recordID(n), source: source, outcome: outcome, quantity: quantity, at: at(hour))
        }
        func start(earned: Int, spent: Int = 0, purchased: [String] = [], granted: [String] = [], outfit: String = "none",
                   accessories: [String] = []) -> ClosetStart {
            ClosetStart(breed: "tuxedo", outfit: outfit, accessories: accessories, earned: earned, spent: spent,
                        purchased: purchased, granted: granted)
        }
        return [
            ("new pet shops and dresses", start(earned: 0), [
                tap("accessory.beanie"),
                study(4, false),
                study(25, true),
                tap("accessory.beanie"),
                tap("accessory.beanie"),
                tap("accessory.beanie"),
                tap("accessory.partyHat"),
                tap("accessory.scarf"),
                tap("accessory.flameHeadband"),
                buy("accessory.beanie"),
                buy("accessory.flameHeadband"),
                buy("accessory.roundGlasses"),
                tap("outfit.none"),
                study(24, true),
                study(26, false),
                study(90, true),
                tap("outfit.scrubs"),
            ]),
            ("level-up awards", start(earned: 30), [
                credit(1, 10, outcome: "skipped", 0),
                party(25, friends: 2, finished: true, 1),
                credit(2, 30, outcome: "completed", 2),
                credit(3, 30, source: "party", outcome: "skipped", 3),
                credit(4, 4, outcome: "skipped", 4),
                credit(5, 12.7, outcome: "abandoned", 5),
                credit(6, 20, outcome: "stopped", 6),
                credit(7, 20, outcome: nil, 7),
                party(30, friends: 5, finished: false, 8),
                party(3, friends: 1, finished: true, 9),
                party(25, friends: 0, finished: true, 10),
                party(60, friends: 7, finished: true, 11),
                ClosetOp(op: "gift", points: 100),
                ClosetOp(op: "gift", points: -50),
            ]),
            ("server grants", start(earned: 0), [
                ClosetOp(op: "grant", ids: ["accessory.foundersPin", "accessory.beanie", "accessory.jetpack",
                                            "accessory.backwardsCap", "nonsense"]),
                ClosetOp(op: "grant", ids: ["accessory.backwardsCap"]),
                tap("accessory.backwardsCap"),
                buy("accessory.backwardsCap"),
                tap("accessory.foundersPin"),
                tap("accessory.backwardsCap"),
            ]),
            ("slots and clashes", start(earned: 10000, purchased: ["accessory.roundGlasses"],
                                        accessories: ["roundGlasses"]), [
                tap("accessory.pirateHat"),
                tap("accessory.roundGlasses"),
                tap("outfit.wizardRobe"),
                tap("outfit.whiteCoat"),
                tap("accessory.angelWings"),
                tap("accessory.rainCloud"),
                buy("accessory.graduationCap"),
                tap("accessory.graduationCap"),
                tap("outfit.whiteCoat"),
            ]),
            ("stored ledger cleaned up", start(earned: 100, spent: 500,
                                               purchased: ["accessory.scarf", "accessory.flameHeadband", "accessory.beanie"],
                                               granted: ["accessory.flameHeadband", "accessory.beanie"],
                                               outfit: "scrubs", accessories: ["beanie", "scarf"]), [
                tap("accessory.beanie"),
                tap("accessory.flameHeadband"),
                study(0, true),
            ]),
        ]
    }

    static var sampleMilestones: [(String, MilestoneInput)] {
        let york = "America/New_York"
        let tokyo = "Asia/Tokyo"
        func ny(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Double {
            local(york, 2026, month, day, hour, minute)
        }
        func jp(_ day: Int, _ hour: Int) -> Double { local(tokyo, 2027, 1, day, hour) }
        let week = [
            record(1, end: ny(10, 25, 10), minutes: 4),
            record(2, end: ny(10, 26, 23, 30), minutes: 25),
            record(3, end: ny(10, 27, 9), minutes: 60, kind: "break.taken"),
            record(4, end: ny(10, 27, 10), minutes: 25),
            record(5, end: ny(10, 28, 10), minutes: 30),
            record(5, end: ny(10, 28, 10), minutes: 30),
            record(6, end: ny(10, 29, 18), minutes: 50, source: "party", outcome: "completed"),
            record(7, end: ny(10, 30, 8), minutes: 3),
            record(8, end: ny(10, 30, 20), minutes: 3, outcome: "skipped"),
            record(9, end: ny(10, 31, 20), minutes: 25, source: "party", outcome: "skipped"),
            record(10, end: ny(11, 1, 1, 30), minutes: 30),
            record(11, end: ny(11, 2, 21), minutes: 45, outcome: "stopped"),
            record(12, end: ny(11, 2, 22), minutes: 40, unit: "cards"),
            record(13, end: ny(11, 2, 23), minutes: 0),
        ]
        let hours = [
            record(21, end: jp(5, 9), minutes: 500), record(22, end: jp(6, 9), minutes: 500),
            record(23, end: jp(7, 9), minutes: 500), record(24, end: jp(9, 9), minutes: 500),
            record(25, end: jp(10, 9), minutes: 500), record(26, end: jp(11, 9), minutes: 499.5),
        ]
        return [
            ("no records", MilestoneInput(timeZone: york, today: ny(11, 3, 8), records: [])),
            ("week streak across the clock change", MilestoneInput(timeZone: york, today: ny(11, 3, 8), records: week)),
            ("streak read on its last day", MilestoneInput(timeZone: york, today: ny(11, 2, 23, 59), records: week)),
            ("streak broken a day later", MilestoneInput(timeZone: york, today: ny(11, 4, 0, 1), records: week)),
            ("same records in Tokyo", MilestoneInput(timeZone: tokyo, today: ny(11, 3, 8), records: week)),
            ("just short of fifty hours", MilestoneInput(timeZone: tokyo, today: jp(13, 10), records: hours)),
            ("fifty hours reached", MilestoneInput(timeZone: tokyo, today: jp(13, 10),
                                                   records: hours + [record(27, end: jp(12, 9), minutes: 0.5)])),
        ]
    }

    static var sampleFreezes: [(String, FreezeInput)] {
        let zone = "America/New_York"
        func noon(_ day: Int) -> Double { local(zone, 2026, 10, day, 12) }
        return [
            ("holding limit before points", FreezeInput(timeZone: zone, firstWeekday: 2, earned: 250,
                                                        studyDays: ["2026-10-12", "2026-10-13"],
                                                        buys: [noon(14), noon(14), noon(14)])),
            ("not enough points", FreezeInput(timeZone: zone, firstWeekday: 2, earned: 150,
                                              studyDays: ["2026-10-13"], buys: [noon(14), noon(14)])),
            ("a used freeze makes room", FreezeInput(timeZone: zone, firstWeekday: 2, earned: 1000,
                                                     studyDays: ["2026-10-12", "2026-10-15"],
                                                     buys: [noon(12), noon(12), noon(15), noon(15)])),
            ("no streak needed to buy", FreezeInput(timeZone: zone, firstWeekday: 1, earned: 105, studyDays: [],
                                                    buys: [noon(14), noon(14)])),
        ]
    }

    static var sampleMoments: [(String, Double)] {
        let york = "America/New_York"
        let tokyo = "Asia/Tokyo"
        let nyMoments = [
            local(york, 2026, 10, 16, 23, 59, 59), local(york, 2026, 10, 17), local(york, 2026, 10, 31, 23, 59, 59),
            local(york, 2026, 11, 1), local(york, 2026, 12, 25, 12), local(york, 2027, 1, 6, 23), local(york, 2027, 1, 7),
            local(york, 2027, 2, 10, 12), local(york, 2026, 5, 1, 12), local(york, 2026, 6, 15, 12),
            local(york, 2026, 6, 21), local(york, 2026, 9, 1, 12),
        ]
        let shared = [local("UTC", 2026, 10, 16, 15, 30), local("UTC", 2027, 1, 6, 16)]
        return nyMoments.map { (york, $0) } + shared.flatMap { [(york, $0), (tokyo, $0)] }
    }

    static var sampleTallies: [(String, TallyInput)] {
        let york = "America/New_York"
        func ny(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Double {
            local(york, year, month, day, hour, minute)
        }
        return [
            ("halloween witch hat", TallyInput(timeZone: york, records: [
                record(1, end: ny(2026, 10, 17, 0), minutes: 45),
                record(2, end: ny(2026, 10, 18, 20), minutes: 60),
                record(3, end: ny(2026, 10, 20, 20), minutes: 40, outcome: "skipped"),
                record(3, end: ny(2026, 10, 20, 20), minutes: 40, outcome: "skipped"),
                record(4, end: ny(2026, 10, 21, 20), minutes: 30, kind: "break.taken"),
                record(5, end: ny(2026, 11, 1, 0), minutes: 200),
                record(6, end: ny(2026, 10, 16, 23, 59), minutes: 200),
            ], queries: [ny(2026, 10, 16, 12), ny(2026, 10, 25, 12), ny(2026, 11, 2, 12)])),
            ("winter over new year", TallyInput(timeZone: york, records: [
                record(11, end: ny(2026, 12, 13, 23, 59), minutes: 120),
                record(12, end: ny(2026, 12, 30, 20), minutes: 200),
                record(13, end: ny(2027, 1, 3, 20), minutes: 150),
            ], queries: [ny(2026, 12, 20, 12), ny(2027, 1, 1, 12)])),
            ("lunar new year and valentines overlap", TallyInput(timeZone: york, records: [
                record(21, end: ny(2027, 2, 10, 12), minutes: 200),
            ], queries: [ny(2027, 2, 9, 12), ny(2027, 2, 10, 12), ny(2027, 2, 16, 12)])),
            ("last year's run still earns", TallyInput(timeZone: york, records: [
                record(31, end: ny(2025, 10, 20, 20), minutes: 300),
                record(32, end: ny(2026, 10, 20, 20), minutes: 30),
            ], queries: [ny(2026, 10, 25, 12)])),
        ]
    }
}
