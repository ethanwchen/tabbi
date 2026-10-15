import Foundation
import TabbiKitCore
import XCTest

/// Pins the account's sync document (`SyncDocument`) and one sync round
/// (`SyncRound`) to the golden fixture
/// `shared/fixtures/sync-document/sync-document.json`: the exact JSON a
/// device writes to the server, how a stored document reads back (older,
/// newer and damaged ones too), how two documents merge, and what a round
/// pulls, pushes and adopts against a scripted server.
///
/// Every app writes the same server document, so the Windows port replays
/// the fixture's inputs through its own document and round and compares
/// every recorded output. `shared/schemas/sync-document.v1.schema.json`
/// describes the same JSON. Run with `TABBI_RECORD_FIXTURES=1` to rewrite
/// the fixture after an intended change.
final class SyncDocumentGoldenTests: XCTestCase {
    private var recording: Bool { ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" }

    func testSyncDocumentMatchesGoldenFixture() async throws {
        let url = SyncDocumentGoldenFixture.url
        let current = try await SyncDocumentGoldenFixture.current()
        if recording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(SyncDocumentGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "A sync constant changed")
        XCTAssertEqual(stored.wire.map(\.name), current.wire.map(\.name))
        for (old, new) in zip(stored.wire, current.wire) { XCTAssertEqual(old, new, "Wire \(old.name)") }
        XCTAssertEqual(stored.decodes.map(\.name), current.decodes.map(\.name))
        for (old, new) in zip(stored.decodes, current.decodes) { XCTAssertEqual(old, new, "Decode \(old.name)") }
        XCTAssertEqual(stored.merges.map(\.name), current.merges.map(\.name))
        for (old, new) in zip(stored.merges, current.merges) { XCTAssertEqual(old, new, "Merge \(old.name)") }
        XCTAssertEqual(stored.rounds.map(\.name), current.rounds.map(\.name))
        for (old, new) in zip(stored.rounds, current.rounds) {
            XCTAssertEqual(old.input, new.input, "Round \(old.name) input")
            XCTAssertEqual(old.output.exchanges, new.output.exchanges, "Round \(old.name) exchanges")
            XCTAssertEqual(old.output, new.output, "Round \(old.name) output")
        }
        XCTAssertEqual(stored, current, "The sync document no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() async throws {
        try XCTSkipIf(recording, "Recording")
        let stored = try JSONDecoder().decode(SyncDocumentGoldenFixture.self,
                                              from: Data(contentsOf: SyncDocumentGoldenFixture.url))
        for wire in stored.wire {
            let document = try SyncDocument.decode(Data(wire.text.utf8))
            XCTAssertEqual(String(decoding: try document.encoded(), as: UTF8.self), wire.text, wire.name)
            XCTAssertEqual(try PartyJSON.parse(Data(wire.text.utf8)), wire.document, wire.name)
        }
        for decode in stored.decodes {
            XCTAssertEqual(try SyncDocumentGoldenFixture.read(decode.input), decode.document, decode.name)
        }
        for merge in stored.merges {
            XCTAssertEqual(try SyncDocumentGoldenFixture.merge(merge.input), merge.output, merge.name)
        }
        for round in stored.rounds {
            let output = try await SyncDocumentGoldenFixture.play(round.input)
            XCTAssertEqual(output, round.output, round.name)
        }
    }

    /// The shared schema names exactly the fields the document writes, and
    /// its limits are the Swift ones.
    func testSchemaHasTheFieldsTheDocumentWrites() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schemaURL = root.appendingPathComponent("shared/schemas/sync-document.v1.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        let top = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        func properties(_ node: [String: Any]?) -> Set<String> { Set((node?["properties"] as? [String: Any] ?? [:]).keys) }

        let full = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SyncDocumentGoldenFixture.fullDocument.encoded()) as? [String: Any])
        XCTAssertEqual(properties(schema), Set(full.keys))
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(full.keys).subtracting(["pet"]),
                       "everything but the pet is always written")
        let pet = try XCTUnwrap(full["pet"] as? [String: Any])
        XCTAssertEqual(properties(defs["syncedPet"]), Set(pet.keys))
        let profile = try XCTUnwrap(pet["profile"] as? [String: Any])
        XCTAssertEqual(properties(defs["profile"]), Set(profile.keys))
        XCTAssertEqual(Set(defs["profile"]?["required"] as? [String] ?? []), Set(profile.keys))
        let tallies = try XCTUnwrap(full["tallies"] as? [String: [String: Any]])
        XCTAssertEqual(properties(defs["tally"]), Set(try XCTUnwrap(tallies.values.first).keys))

        XCTAssertEqual(top["schemaVersion"]?["const"] as? Int, SyncDocument.schema.current)
        XCTAssertEqual(top["studyDays"]?["maxItems"] as? Int, SyncDocument.keptStudyDays)
        let overrides = (defs["profile"]?["properties"] as? [String: [String: Any]])?["paletteOverrides"]
        let roles = (overrides?["propertyNames"] as? [String: Any])?["enum"] as? [String]
        XCTAssertEqual(roles, PetPaletteRole.userEditable.map(\.rawValue))
    }
}

/// Sample documents as written, stored documents as read, merges of two
/// documents, and sync rounds against a scripted server. Documents are kept
/// as JSON objects exactly as they go over the wire.
struct SyncDocumentGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.sync-document.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/sync-document/sync-document.json")
    }

    /// The numbers the format and the round are built on.
    struct Constants: Codable, Equatable {
        var schemaVersion: Int
        var keptStudyDays: Int
        var maxAttempts: Int
    }

    /// A document as `SyncDocument.encoded()` writes it: `text` is the exact
    /// string, `document` the same JSON as an object.
    struct Wire: Codable, Equatable {
        var name: String
        var text: String
        var document: PartyJSON
    }

    /// A stored document (`input`, any text) and what reading it gives,
    /// written back out (`document`), or nil when it cannot be read at all.
    struct Decode: Codable, Equatable {
        var name: String
        var input: String
        var document: PartyJSON?
    }

    /// `remote` is nil when the server holds no document yet.
    struct MergeInput: Codable, Equatable {
        var today: String
        var local: PartyJSON
        var remote: PartyJSON?
    }

    /// The points ledger the merged document gives this build: items it
    /// does not know are left out, limited ones are granted, not bought.
    struct Ledger: Codable, Equatable {
        var earned: Int
        var spent: Int
        var purchased: [String]
        var granted: [String]
    }

    struct MergeOutput: Codable, Equatable {
        var merged: PartyJSON
        var earned: Int
        var spent: Int
        var ledger: Ledger
        var currentStreak: Int
    }

    struct Merge: Codable, Equatable {
        var name: String
        var input: MergeInput
        var output: MergeOutput
    }

    /// A pet save: the profile as `PetProfile` encodes it, and the ledger.
    /// Dates are seconds since 1970.
    struct Save: Codable, Equatable {
        var profile: PartyJSON
        var earned: Int
        var spent: Int
        var purchased: [String]
        var granted: [String]
        var streakFreezes: [Double]
    }

    /// `SyncLocalProgress`: the device's save, when its look last changed
    /// (nil when unknown) and its own study days.
    struct LocalProgress: Codable, Equatable {
        var save: Save
        var lookChangedAt: Double?
        var studyDays: [String]
    }

    /// The server's revision and document (nil before any push).
    struct Server: Codable, Equatable {
        var revision: Int
        var document: PartyJSON?
    }

    /// One request the round made: a `pull` with the revision and document
    /// served, or a `push` with its `ifMatch` revision, the document `sent`,
    /// and the new revision (absent on a 409).
    struct Exchange: Codable, Equatable {
        var request: String
        var ifMatch: Int?
        var sent: PartyJSON?
        var status: Int
        var revision: Int?
        var received: PartyJSON?
    }

    /// `SyncOutcome`: the merged document (also the state's adopted one),
    /// whether it was pushed, the save to adopt, and the state's revision
    /// and last sync time.
    struct Outcome: Codable, Equatable {
        var document: PartyJSON
        var pushed: Bool
        var save: Save
        var revision: Int
        var lastSyncedAt: Double?
    }

    /// `SyncState` (`device`, `account`, the `adopted` document and its
    /// `revision`), this device's progress, the server before the round,
    /// `racers` (for the n-th push, a document another device merges into
    /// the server just before it lands, so the push meets a 409) and `now`.
    /// `duringRound` is progress made while the round ran, folded on top of
    /// its outcome with `SyncOutcome.folding(_:base:)`.
    struct RoundInput: Codable, Equatable {
        var device: String
        var account: String?
        var adopted: PartyJSON
        var revision: Int
        var local: LocalProgress
        var duringRound: LocalProgress?
        var server: Server
        var racers: [PartyJSON?]
        var now: Double
    }

    /// `error` is `revision_conflict` when the round gave up; `outcome` and
    /// `folded` are then absent.
    struct RoundOutput: Codable, Equatable {
        var exchanges: [Exchange]
        var outcome: Outcome?
        var error: String?
        var folded: Outcome?
        var server: Server
    }

    struct Round: Codable, Equatable {
        var name: String
        var input: RoundInput
        var output: RoundOutput
    }

    var schema = Self.schemaName
    var version = 1
    var constants: Constants
    var wire: [Wire]
    var decodes: [Decode]
    var merges: [Merge]
    var rounds: [Round]

    static func current() async throws -> SyncDocumentGoldenFixture {
        var rounds: [Round] = []
        for (name, input) in try roundInputs() {
            rounds.append(Round(name: name, input: input, output: try await play(input)))
        }
        return SyncDocumentGoldenFixture(
            constants: Constants(schemaVersion: SyncDocument.schema.current, keptStudyDays: SyncDocument.keptStudyDays,
                                 maxAttempts: SyncRound.maxAttempts),
            wire: try wireDocuments.map { name, document in
                let text = String(decoding: try document.encoded(), as: UTF8.self)
                return Wire(name: name, text: text, document: try PartyJSON.parse(Data(text.utf8)))
            },
            decodes: try decodeInputs.map { Decode(name: $0.0, input: $0.1, document: try read($0.1)) },
            merges: try mergeInputs().map { Merge(name: $0.0, input: $0.1, output: try merge($0.1)) },
            rounds: rounds
        )
    }

    // MARK: - Replay

    /// Reads a stored document and writes it back out, or nil when it cannot be read.
    static func read(_ input: String) throws -> PartyJSON? {
        let document: SyncDocument
        do {
            document = try SyncDocument.decode(Data(input.utf8))
        } catch {
            return nil
        }
        return try wireJSON(document)
    }

    static func merge(_ input: MergeInput) throws -> MergeOutput {
        let local = try decodeDocument(input.local)
        let remote = try input.remote.map(decodeDocument) ?? .empty
        let merged = local.merged(with: remote)
        XCTAssertEqual(remote.merged(with: local), merged, "Merging the other way round differs")
        XCTAssertEqual(merged.merged(with: local), merged, "Merging again changed the document")
        let ledger = merged.ledger
        return MergeOutput(
            merged: try wireJSON(merged),
            earned: merged.earned,
            spent: merged.spent,
            ledger: Ledger(earned: ledger.earned, spent: ledger.spent, purchased: ledger.purchased.map(\.id).sorted(),
                           granted: ledger.granted.map(\.id).sorted()),
            currentStreak: merged.currentStreak(today: input.today)
        )
    }

    /// Runs one `SyncRound` against a scripted server built from `input`.
    static func play(_ input: RoundInput) async throws -> RoundOutput {
        let server = SyncDocumentGoldenServer(
            revision: input.server.revision,
            stored: try input.server.document.map { try $0.data() },
            racers: try input.racers.map { try $0.map(decodeDocument) }
        )
        let state = SyncState(device: input.device, account: input.account, adopted: try decodeDocument(input.adopted),
                              revision: input.revision)
        let client = SyncClient(transport: server, token: "golden-token")
        var output = RoundOutput(exchanges: [], server: input.server)
        do {
            let outcome = try await SyncRound.run(try progress(input.local), state: state, client: client,
                                                  now: Date(timeIntervalSince1970: input.now))
            output.outcome = try record(outcome)
            if let during = input.duringRound {
                output.folded = try record(outcome.folding(try progress(during), base: state))
            }
        } catch let error as PartyError {
            output.error = error.isRevisionConflict ? "revision_conflict" : String(describing: error)
        }
        output.exchanges = server.exchanges
        output.server = try server.snapshot()
        return output
    }

    private static func record(_ outcome: SyncOutcome) throws -> Outcome {
        XCTAssertEqual(outcome.state.adopted, outcome.document, "The state adopts the outcome's document")
        return Outcome(document: try wireJSON(outcome.document), pushed: outcome.pushed, save: try save(of: outcome.save),
                       revision: outcome.state.revision, lastSyncedAt: outcome.state.lastSyncedAt?.timeIntervalSince1970)
    }

    private static func progress(_ local: LocalProgress) throws -> SyncLocalProgress {
        SyncLocalProgress(save: try petSave(local.save), lookChangedAt: local.lookChangedAt.map(Date.init(timeIntervalSince1970:)),
                          studyDays: Set(local.studyDays))
    }

    private static func petSave(_ save: Save) throws -> PetSave {
        let profile = try JSONDecoder().decode(PetProfile.self, from: save.profile.data())
        let ledger = PetPointsLedger(
            earned: save.earned, spent: save.spent,
            purchased: Set(save.purchased.compactMap(PetItem.init(id:))),
            granted: Set(save.granted.compactMap(PetItem.init(id:))),
            streakFreezes: save.streakFreezes.map(Date.init(timeIntervalSince1970:))
        )
        return PetSave(profile: profile, ledger: ledger)
    }

    private static func save(of save: PetSave) throws -> Save {
        Save(profile: try profileJSON(save.profile), earned: save.ledger.earned, spent: save.ledger.spent,
             purchased: save.ledger.purchased.map(\.id).sorted(), granted: save.ledger.granted.map(\.id).sorted(),
             streakFreezes: save.ledger.streakFreezes.map(\.timeIntervalSince1970))
    }

    // MARK: - JSON

    static func wireJSON(_ document: SyncDocument) throws -> PartyJSON {
        try PartyJSON.parse(document.encoded())
    }

    static func decodeDocument(_ json: PartyJSON) throws -> SyncDocument {
        try SyncDocument.decode(json.data())
    }

    static func profileJSON(_ profile: PetProfile) throws -> PartyJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try PartyJSON.parse(encoder.encode(profile))
    }

    /// `json` with some of its top-level keys changed, for documents an app
    /// would not write itself.
    private static func editing(_ json: PartyJSON, _ edit: (inout [String: PartyJSON]) -> Void) -> PartyJSON {
        guard case .object(var object) = json else { return json }
        edit(&object)
        return .object(object)
    }

    // MARK: - Inputs

    /// 2027-01-15 08:00:00 UTC, in seconds since 1970.
    static let t0: Double = 1_800_000_000

    /// Sync device ids, which the Mac makes with `UUID().uuidString`.
    static let deviceA = "0A6F3C1E-5B2D-4E8F-9A71-3C5D7E9F1B2A"
    static let deviceB = "1B7E4D2F-6C3E-4F9A-8B82-4D6E8F0A2C3B"
    static let deviceC = "2C8F5E3A-7D4F-4A0B-9C93-5E7F9A1B3D4C"
    static let accountCode = "K7QW2MZD"

    private static func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private static func pet(_ name: String, _ breed: PetBreed = .britishShorthair, at seconds: Double) -> SyncedPet {
        SyncedPet(profile: PetProfile(name: name, breed: breed), updatedAt: at(seconds))
    }

    static let mochi = PetProfile(name: "Mochi", breed: .britishShorthair)
    static let tofu = PetProfile(name: "Tofu", breed: .calico)

    /// A pet that sets every profile field.
    static let dressedProfile = PetProfile(
        name: "Pip", breed: .tuxedo,
        paletteOverrides: [.belly: PetColor(red: 0xF5, green: 0xE6, blue: 0xD3),
                           .accessoryBase: PetColor(red: 0x2E, green: 0x6B, blue: 0xD9)],
        furTint: PetColor(red: 0x8A, green: 0x6B, blue: 0xBE),
        outfit: .scrubs, accessories: [.roundGlasses, .beanie]
    )

    /// A document that sets every field.
    static let fullDocument = SyncDocument(
        pet: SyncedPet(profile: dressedProfile, updatedAt: Date(timeIntervalSince1970: t0)),
        tallies: [deviceA: SyncTally(earned: 1250, spent: 410), deviceB: SyncTally(earned: 75)],
        unlocks: ["accessory.beanie", "accessory.roundGlasses", "outfit.scrubs", "accessory.flameHeadband",
                  "accessory.fromTheFuture"],
        studyDays: ["2027-01-10", "2027-01-12", "2027-01-13", "2027-01-14"],
        longestStreak: 9
    )

    /// `count` consecutive days from `start` (a UTC midnight), as `YYYY-MM-DD`.
    private static func days(from start: Double, count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return (0..<count).map { offset in
            let parts = calendar.dateComponents([.year, .month, .day], from: at(start + Double(offset) * 86_400))
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }

    /// 2025-06-01 00:00:00 UTC.
    private static let june2025: Double = 1_748_736_000

    static let wireDocuments: [(String, SyncDocument)] = [
        ("empty", .empty),
        ("full", fullDocument),
        ("pet-only", SyncDocument(pet: pet("Mochi", at: t0))),
        ("default-cat-name", SyncDocument(pet: SyncedPet(profile: PetProfile(name: "", breed: .britishShorthair),
                                                         updatedAt: Date(timeIntervalSince1970: t0)))),
        ("name-with-slash-and-accents", SyncDocument(
            pet: SyncedPet(profile: PetProfile(name: "Caf\u{00E9}/\u{3082}\u{3061}", breed: .shihTzu),
                           updatedAt: Date(timeIntervalSince1970: t0)),
            tallies: [deviceA: SyncTally(earned: 3)]
        )),
        ("translucent-fur-tint", SyncDocument(
            pet: SyncedPet(profile: PetProfile(name: "Ghost", breed: .whiteCat,
                                               furTint: PetColor(red: 0x10, green: 0x20, blue: 0x30, alpha: 0x80)),
                           updatedAt: Date(timeIntervalSince1970: t0))
        )),
        ("fractional-time-cut-to-the-second", SyncDocument(
            pet: SyncedPet(profile: mochi, updatedAt: Date(timeIntervalSince1970: t0 + 0.999))
        )),
        ("before-1970", SyncDocument(pet: SyncedPet(profile: mochi, updatedAt: Date(timeIntervalSince1970: -86_400.5)))),
        ("points-days-and-unlocks", SyncDocument(
            tallies: [deviceB: SyncTally(earned: 40), deviceA: SyncTally(earned: 120, spent: 30)],
            unlocks: ["outfit.scrubs", "accessory.beanie"],
            studyDays: ["2027-01-03", "2027-01-01", "2027-01-02"]
        )),
    ]

    static let decodeInputs: [(String, String)] = {
        let fullPet = #"{"profile":{"accessories":["roundGlasses","beanie"],"breed":"tuxedo","furTint":"#8A6BBE","name":"Pip","outfit":"scrubs","paletteOverrides":{"belly":"#F5E6D3"}},"updatedAt":"2027-01-15T08:00:00Z"}"#
        func withPet(_ pet: String) -> String { #"{"schemaVersion":1,"pet":"# + pet + "}" }
        func withProfile(_ profile: String, updatedAt: String = #""2027-01-15T08:00:00Z""#) -> String {
            withPet(#"{"profile":"# + profile + #","updatedAt":"# + updatedAt + "}")
        }
        let manyDays = days(from: june2025, count: SyncDocument.keptStudyDays + 50)
        let manyDaysJSON = "[" + manyDays.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return [
            ("empty-object", "{}"),
            ("without-schema-version",
             #"{"tallies":{"a":{"earned":12,"spent":3}},"unlocks":["accessory.beanie"],"studyDays":["2027-01-01"],"longestStreak":1}"#),
            ("newer-schema-version-with-unknown-keys",
             #"{"schemaVersion":2,"somethingNew":{"x":[1,2]},"tallies":{"a":{"earned":5,"spent":0,"bonus":9}},"unlocks":[],"studyDays":[],"longestStreak":0}"#),
            ("every-field-null",
             #"{"schemaVersion":1,"pet":null,"tallies":null,"unlocks":null,"studyDays":null,"longestStreak":null}"#),
            ("bad-fields-keep-the-rest",
             #"{"schemaVersion":1,"pet":{"profile":{"breed":"notABreed"}},"tallies":{"a":{"earned":7,"spent":0}},"unlocks":"oops","studyDays":["2027-01-01"],"somethingNew":true}"#),
            ("invalid-study-days-dropped",
             #"{"studyDays":["2027-02-30","yesterday","2027-1-01","2027-02-29","2028-02-29","+027-01-01","2027-13-01","2027-01-05"," 2027-01-06",""]}"#),
            ("study-days-sorted-and-deduplicated", #"{"studyDays":["2027-01-03","2027-01-01","2027-01-03","2026-12-31"]}"#),
            ("study-day-that-is-not-a-string-drops-every-day", #"{"studyDays":["2027-01-01",20270102]}"#),
            ("longest-streak-raised-to-the-days-run",
             #"{"studyDays":["2026-12-31","2027-01-01","2027-01-02","2027-01-05"],"longestStreak":1}"#),
            ("longest-streak-kept-above-the-days-run", #"{"studyDays":["2027-01-01"],"longestStreak":40}"#),
            ("negative-longest-streak", #"{"longestStreak":-4}"#),
            ("longest-streak-as-a-string", #"{"studyDays":["2027-01-01","2027-01-02"],"longestStreak":"5"}"#),
            ("fractional-longest-streak", #"{"longestStreak":2.5}"#),
            ("negative-tallies-kept", #"{"tallies":{"a":{"earned":-5,"spent":-1},"b":{"earned":3,"spent":9}}}"#),
            ("tally-missing-spent-drops-every-tally", #"{"tallies":{"a":{"earned":7},"b":{"earned":3,"spent":1}}}"#),
            ("fractional-tally-drops-every-tally", #"{"tallies":{"a":{"earned":7.5,"spent":0},"b":{"earned":3,"spent":1}}}"#),
            ("tallies-as-a-list", #"{"tallies":[{"earned":7,"spent":0}]}"#),
            ("unlocks-sorted-deduplicated-unknown-kept",
             #"{"unlocks":["outfit.scrubs","accessory.fromTheFuture","accessory.beanie","outfit.scrubs","hat.legacy",""]}"#),
            ("unlock-that-is-not-a-string-drops-every-unlock", #"{"unlocks":["accessory.beanie",7]}"#),
            ("pet-with-every-field", withPet(fullPet)),
            ("pet-null", withPet("null")),
            ("pet-unknown-breed-dropped", withProfile(#"{"name":"Rex","breed":"dragon"}"#)),
            ("pet-without-breed-dropped", withProfile(#"{"name":"Rex"}"#)),
            ("pet-with-only-a-breed", withProfile(#"{"breed":"corgi"}"#)),
            ("pet-legacy-fur-base-becomes-the-tint",
             withProfile(#"{"name":"Old","breed":"orangeTabby","paletteOverrides":{"furBase":"#aabbcc","furShade":"#112233","belly":"#FFFFFF","costumeBase":"#336699"}}"#)),
            ("pet-null-fur-tint-keeps-fur-colors",
             withProfile(#"{"name":"New","breed":"orangeTabby","furTint":null,"paletteOverrides":{"furBase":"#AABBCC","furShade":"#112233"}}"#)),
            ("pet-bad-colors-dropped",
             withProfile(#"{"name":"Dots","breed":"calico","furTint":"blue","paletteOverrides":{"eye":"#00FF00","belly":"#abc","furSpot":"#11223344","nope":"#123456"}}"#)),
            ("pet-name-cleaned", withProfile(#"{"name":"  Sir   Pounce-a-lot\n the Third  ","breed":"siamese"}"#)),
            ("pet-blank-name", withProfile(#"{"name":"   ","breed":"goldenRetriever"}"#)),
            ("pet-unknown-outfit-and-accessories",
             withProfile(#"{"name":"Rex","breed":"corgi","outfit":"spaceSuit","accessories":["notAThing","beanie","backwardsCap","roundGlasses","coolSunglasses"]}"#)),
            ("pet-date-with-an-offset", withProfile(#"{"breed":"sphynx"}"#, updatedAt: #""2027-01-15T17:00:00+09:00""#)),
            ("pet-date-with-fractional-seconds", withProfile(#"{"breed":"sphynx"}"#, updatedAt: #""2027-01-15T08:00:00.750Z""#)),
            ("pet-date-without-a-zone", withProfile(#"{"breed":"sphynx"}"#, updatedAt: #""2027-01-15T08:00:00""#)),
            ("pet-date-as-a-number", withProfile(#"{"breed":"sphynx"}"#, updatedAt: "1800000000")),
            ("pet-without-a-date", withPet(#"{"profile":{"breed":"sphynx"}}"#)),
            ("more-days-than-kept", #"{"schemaVersion":1,"studyDays":"# + manyDaysJSON + "}"),
            ("not-an-object", "[]"),
            ("json-null", "null"),
            ("not-json", "tallies"),
        ]
    }()

    static func mergeInputs() throws -> [(String, MergeInput)] {
        func input(_ local: SyncDocument, _ remote: SyncDocument?, today: String = "2027-01-15") throws -> MergeInput {
            MergeInput(today: today, local: try wireJSON(local), remote: try remote.map(wireJSON))
        }
        let progress = SyncDocument(
            pet: pet("Mochi", at: t0),
            tallies: [deviceA: SyncTally(earned: 120, spent: 30)],
            unlocks: ["accessory.beanie"],
            studyDays: ["2027-01-14", "2027-01-15"]
        )
        let fiveHundredDays = days(from: june2025, count: 500)
        return [
            ("both-empty", try input(.empty, .empty)),
            ("server-has-no-document", try input(progress, nil)),
            ("first-sync-into-an-empty-document", try input(progress, .empty)),
            ("identical-documents", try input(fullDocument, fullDocument)),
            ("points-from-two-devices-add-up", try input(
                SyncDocument(tallies: [deviceA: SyncTally(earned: 120, spent: 30)]),
                SyncDocument(tallies: [deviceB: SyncTally(earned: 40)])
            )),
            ("same-device-takes-the-larger-of-each-counter", try input(
                SyncDocument(tallies: [deviceA: SyncTally(earned: 120, spent: 30)]),
                SyncDocument(tallies: [deviceA: SyncTally(earned: 90, spent: 45)])
            )),
            ("three-devices-overlapping", try input(
                SyncDocument(tallies: [deviceA: SyncTally(earned: 100), deviceB: SyncTally(earned: 50, spent: 10)]),
                SyncDocument(tallies: [deviceB: SyncTally(earned: 60, spent: 5), deviceC: SyncTally(earned: 5)])
            )),
            ("spent-above-earned-is-capped-in-the-ledger", try input(
                SyncDocument(tallies: [deviceA: SyncTally(earned: 10)]),
                SyncDocument(tallies: [deviceB: SyncTally(spent: 50)])
            )),
            ("unlocks-union", try input(
                SyncDocument(unlocks: ["accessory.beanie", "outfit.scrubs"]),
                SyncDocument(unlocks: ["accessory.beanie", "accessory.roundGlasses", "accessory.fromTheFuture",
                                       "accessory.flameHeadband", "accessory.scarf", "outfit.none"])
            )),
            ("study-days-join-into-one-streak", try input(
                SyncDocument(studyDays: ["2027-01-01", "2027-01-03"]),
                SyncDocument(studyDays: ["2027-01-02"]),
                today: "2027-01-03"
            )),
            ("streak-lasts-until-a-whole-day-is-missed", try input(
                SyncDocument(studyDays: ["2027-01-13", "2027-01-14"]),
                SyncDocument(studyDays: ["2027-01-12"]),
                today: "2027-01-15"
            )),
            ("streak-broken-after-a-missed-day", try input(
                SyncDocument(studyDays: ["2027-01-13", "2027-01-14"]),
                SyncDocument(studyDays: ["2027-01-12"]),
                today: "2027-01-16"
            )),
            ("streak-across-a-year-end", try input(
                SyncDocument(studyDays: ["2026-12-30", "2026-12-31"]),
                SyncDocument(studyDays: ["2027-01-01"]),
                today: "2027-01-01"
            )),
            ("streak-across-a-leap-day", try input(
                SyncDocument(studyDays: ["2028-02-28", "2028-03-01"]),
                SyncDocument(studyDays: ["2028-02-29"]),
                today: "2028-03-02"
            )),
            ("longest-streak-takes-the-maximum", try input(
                SyncDocument(studyDays: ["2027-01-10", "2027-01-11"], longestStreak: 9),
                SyncDocument(studyDays: ["2027-01-14"], longestStreak: 4)
            )),
            ("union-longer-than-either-longest-streak", try input(
                SyncDocument(studyDays: ["2027-01-01", "2027-01-02", "2027-01-03"]),
                SyncDocument(studyDays: ["2027-01-04", "2027-01-05", "2027-01-06"]),
                today: "2027-01-07"
            )),
            ("union-trimmed-to-the-kept-days", try input(
                SyncDocument(studyDays: Set(fiveHundredDays.prefix(300))),
                SyncDocument(studyDays: Set(fiveHundredDays.suffix(200))),
                today: fiveHundredDays[499]
            )),
            ("newer-remote-look-wins", try input(
                SyncDocument(pet: pet("Mochi", at: t0)),
                SyncDocument(pet: pet("Tofu", .calico, at: t0 + 600))
            )),
            ("newer-local-look-wins", try input(
                SyncDocument(pet: pet("Tofu", .calico, at: t0 + 600)),
                SyncDocument(pet: pet("Mochi", at: t0))
            )),
            ("one-second-newer-wins-over-a-greater-profile", try input(
                SyncDocument(pet: pet("Alpha", at: t0 + 1)),
                SyncDocument(pet: pet("Zed", at: t0))
            )),
            ("equal-times-greater-name-wins", try input(
                SyncDocument(pet: pet("Alpha", at: t0)),
                SyncDocument(pet: pet("Beta", at: t0))
            )),
            ("equal-times-greater-breed-wins", try input(
                SyncDocument(pet: pet("Pip", .tuxedo, at: t0)),
                SyncDocument(pet: pet("Pip", .calico, at: t0))
            )),
            ("equal-times-no-accessories-beat-worn-ones", try input(
                SyncDocument(pet: SyncedPet(profile: PetProfile(name: "Pip", breed: .calico, accessories: [.beanie]),
                                            updatedAt: at(t0))),
                SyncDocument(pet: pet("Pip", .calico, at: t0))
            )),
            ("equal-times-null-fur-tint-beats-a-color", try input(
                SyncDocument(pet: SyncedPet(profile: PetProfile(name: "Pip", breed: .calico,
                                                                furTint: PetColor(red: 0x8A, green: 0x6B, blue: 0xBE)),
                                            updatedAt: at(t0))),
                SyncDocument(pet: pet("Pip", .calico, at: t0))
            )),
            ("fractions-are-cut-before-comparing", try input(
                SyncDocument(pet: pet("Alpha", at: t0 + 0.75)),
                SyncDocument(pet: pet("Beta", at: t0))
            )),
            ("one-side-without-a-pet", try input(
                SyncDocument(tallies: [deviceA: SyncTally(earned: 5)]),
                SyncDocument(pet: pet("Tofu", .calico, at: t0))
            )),
            ("everything-at-once", try input(
                fullDocument,
                SyncDocument(
                    pet: SyncedPet(profile: tofu, updatedAt: at(t0 + 3600)),
                    tallies: [deviceA: SyncTally(earned: 1200, spent: 450), deviceC: SyncTally(earned: 20, spent: 20)],
                    unlocks: ["accessory.backwardsCap", "outfit.cozyHoodie"],
                    studyDays: ["2027-01-11", "2027-01-15"],
                    longestStreak: 2
                )
            )),
        ]
    }

    static func roundInputs() throws -> [(String, RoundInput)] {
        func save(_ profile: PetProfile, earned: Int, spent: Int = 0, purchased: [PetItem] = [], granted: [PetItem] = [],
                  freezes: [Double] = []) throws -> Save {
            Save(profile: try profileJSON(profile), earned: earned, spent: spent, purchased: purchased.map(\.id).sorted(),
                 granted: granted.map(\.id).sorted(), streakFreezes: freezes)
        }
        func makeRound(device: String = deviceA, account: String? = accountCode, adopted: SyncDocument = .empty, revision: Int = 0,
                       local: LocalProgress, duringRound: LocalProgress? = nil, server: Server = Server(revision: 0),
                       racers: [SyncDocument?] = [], now: Double = t0 + 3600) throws -> RoundInput {
            RoundInput(device: device, account: account, adopted: try wireJSON(adopted), revision: revision, local: local,
                       duringRound: duringRound, server: server, racers: try racers.map { try $0.map(wireJSON) }, now: now)
        }
        func server(_ revision: Int, _ document: SyncDocument) throws -> Server {
            Server(revision: revision, document: try wireJSON(document))
        }

        // A document this device already adopted, and the save it adopted with it.
        let synced = SyncDocument(pet: SyncedPet(profile: mochi, updatedAt: at(t0)),
                                  tallies: [deviceA: SyncTally(earned: 20)], studyDays: ["2027-01-14"])
        let syncedSave = try Self.save(of: synced.applied(to: PetSave(profile: mochi, ledger: PetPointsLedger(earned: 20))))
        var renamed = mochi
        renamed.rename("Pip")
        let otherDevice = SyncDocument.empty.recording(PetSave(profile: tofu, ledger: PetPointsLedger(earned: 50)),
                                                       changedAt: at(t0), device: deviceB)
        let twoDevices = SyncDocument(pet: SyncedPet(profile: mochi, updatedAt: at(t0)),
                                      tallies: [deviceA: SyncTally(earned: 100), deviceB: SyncTally(earned: 50)])

        return [
            ("first-sync-pushes-local-progress", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 100, spent: 30, purchased: [.accessory(.beanie)]),
                                     lookChangedAt: t0, studyDays: ["2027-01-14", "2027-01-15"])
            )),
            ("first-sync-from-a-fresh-device", try makeRound(
                account: nil,
                local: LocalProgress(save: try save(PetProfile.starter(.cat), earned: 0), studyDays: [])
            )),
            ("first-sign-in-into-an-account-with-progress", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 100, purchased: [.accessory(.beanie)]),
                                     lookChangedAt: t0 - 3600, studyDays: []),
                server: try server(1, otherDevice)
            )),
            ("unknown-local-look-time-loses", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 5), studyDays: []),
                server: try server(1, otherDevice)
            )),
            ("nothing-new-means-no-push", try makeRound(
                adopted: synced, revision: 1,
                local: LocalProgress(save: syncedSave, studyDays: ["2027-01-14"]),
                server: try server(1, synced)
            )),
            ("newer-local-look-is-pushed", try makeRound(
                adopted: synced, revision: 1,
                local: LocalProgress(save: try save(renamed, earned: 20), lookChangedAt: t0 + 600, studyDays: []),
                server: try server(1, synced)
            )),
            ("unchanged-look-loses-to-a-newer-remote-look", try makeRound(
                adopted: synced, revision: 1,
                local: LocalProgress(save: syncedSave, lookChangedAt: t0 + 1200, studyDays: []),
                server: try server(2, synced.merged(with: SyncDocument(pet: SyncedPet(profile: tofu, updatedAt: at(t0 + 600)),
                                                                       tallies: [deviceB: SyncTally(earned: 5)])))
            )),
            ("fractional-look-time-is-cut-to-the-second", try makeRound(
                local: LocalProgress(save: try save(renamed, earned: 1), lookChangedAt: t0 + 0.75, studyDays: [])
            )),
            ("later-round-counts-only-what-this-device-added", try makeRound(
                adopted: twoDevices, revision: 2,
                local: LocalProgress(save: try save(mochi, earned: 160), studyDays: []),
                server: try server(3, SyncDocument(pet: SyncedPet(profile: mochi, updatedAt: at(t0)),
                                                   tallies: [deviceA: SyncTally(earned: 100), deviceB: SyncTally(earned: 60)]))
            )),
            ("offline-spending-on-two-devices", try makeRound(
                adopted: twoDevices, revision: 2,
                local: LocalProgress(save: try save(mochi, earned: 150, spent: 35, purchased: [.accessory(.beanie)]),
                                     studyDays: ["2027-01-15"]),
                server: try server(3, SyncDocument(pet: SyncedPet(profile: mochi, updatedAt: at(t0)),
                                                   tallies: [deviceA: SyncTally(earned: 100),
                                                             deviceB: SyncTally(earned: 50, spent: 50)],
                                                   unlocks: ["accessory.roundGlasses"], studyDays: ["2027-01-14"]))
            )),
            ("limited-and-server-granted-items", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 80, spent: 35, purchased: [.accessory(.beanie)],
                                                    granted: [.accessory(.flameHeadband)]),
                                     lookChangedAt: t0 - 60, studyDays: []),
                server: try server(1, SyncDocument(pet: SyncedPet(profile: mochi, updatedAt: at(t0)),
                                                   tallies: [deviceB: SyncTally(earned: 30)],
                                                   unlocks: ["accessory.backwardsCap", "accessory.fromTheFuture"]))
            )),
            ("streak-freezes-stay-on-the-device", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 200, spent: 60,
                                                    freezes: [t0 - 3 * 86_400, t0 - 86_400]),
                                     lookChangedAt: t0, studyDays: ["2027-01-13", "2027-01-15"])
            )),
            ("worn-items-not-owned-come-off", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 10), lookChangedAt: t0, studyDays: []),
                server: try server(1, SyncDocument(pet: SyncedPet(profile: dressedProfile, updatedAt: at(t0 + 60)),
                                                   tallies: [deviceB: SyncTally(earned: 5)]))
            )),
            ("server-document-from-an-older-build-is-read-leniently", try makeRound(
                adopted: synced, revision: 1,
                local: LocalProgress(save: syncedSave, studyDays: ["2027-01-14"]),
                server: Server(revision: 1, document: editing(try wireJSON(synced)) { object in
                    object["schemaVersion"] = nil
                    object["longestStreak"] = nil
                    object["studyDays"] = .array([.string("2027-01-14"), .string("2027-02-30")])
                    object["comment"] = .string("written by a newer build")
                })
            )),
            ("conflict-pulls-merges-and-retries", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 10), lookChangedAt: t0, studyDays: []),
                racers: [SyncDocument(tallies: [deviceC: SyncTally(earned: 40)], unlocks: ["accessory.roundGlasses"])]
            )),
            ("conflict-on-the-second-push", try makeRound(
                adopted: twoDevices, revision: 2,
                local: LocalProgress(save: try save(mochi, earned: 170), studyDays: []),
                server: try server(2, twoDevices),
                racers: [nil, SyncDocument(tallies: [deviceB: SyncTally(earned: 75)])]
            )),
            ("gives-up-after-repeated-conflicts", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 10), lookChangedAt: t0, studyDays: []),
                racers: [
                    SyncDocument(tallies: [deviceC: SyncTally(earned: 1)]),
                    SyncDocument(tallies: [deviceC: SyncTally(earned: 2)]),
                    SyncDocument(tallies: [deviceC: SyncTally(earned: 3)]),
                ]
            )),
            ("change-during-the-round-is-folded-on-top", try makeRound(
                local: LocalProgress(save: try save(mochi, earned: 10), lookChangedAt: t0, studyDays: []),
                duringRound: LocalProgress(save: try save(mochi, earned: 15), lookChangedAt: t0, studyDays: ["2027-01-15"]),
                server: try server(1, SyncDocument(tallies: [deviceB: SyncTally(earned: 50)]))
            )),
        ]
    }
}

/// A sync server that behaves like `backend/` for `GET` and `PUT /v1/sync`:
/// one document with a revision, stored as sent, and a 409 for a push whose
/// `If-Match` is stale. Before the n-th push lands, `racers[n]` (when set)
/// is merged into the stored document as another device's push.
final class SyncDocumentGoldenServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var revision: Int
    private var stored: Data?
    private let racers: [SyncDocument?]
    private var pushes = 0
    private var log: [SyncDocumentGoldenFixture.Exchange] = []

    init(revision: Int, stored: Data?, racers: [SyncDocument?]) {
        self.revision = revision
        self.stored = stored
        self.racers = racers
    }

    var exchanges: [SyncDocumentGoldenFixture.Exchange] { lock.withLock { log } }

    func snapshot() throws -> SyncDocumentGoldenFixture.Server {
        let (revision, stored) = lock.withLock { (self.revision, self.stored) }
        return SyncDocumentGoldenFixture.Server(revision: revision, document: try stored.map(PartyJSON.parse))
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        try lock.withLock { try handle(request) }
    }

    private func handle(_ request: PartyHTTPRequest) throws -> PartyHTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/v1/sync"):
            let document = stored.map { String(decoding: $0, as: UTF8.self) } ?? "null"
            let updatedAt = stored == nil ? "null" : "1791504000"
            log.append(.init(request: "pull", status: 200, revision: revision, received: try stored.map(PartyJSON.parse)))
            return Self.reply(#"{"ok":true,"revision":\#(revision),"updatedAt":\#(updatedAt),"document":\#(document)}"#)
        case ("PUT", "/v1/sync"):
            let match = Int(request.headers["If-Match"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "")
            let body = request.body ?? Data()
            let prefix = Data(#"{"document":"#.utf8)
            XCTAssertTrue(body.starts(with: prefix) && body.last == UInt8(ascii: "}"), "Unexpected push body")
            let sent = Data(body.dropFirst(prefix.count).dropLast())
            let index = pushes
            pushes += 1
            if index < racers.count, let racer = racers[index] {
                let current = try stored.map(SyncDocument.decode) ?? .empty
                stored = try current.merged(with: racer).encoded()
                revision += 1
            }
            guard match == revision else {
                log.append(.init(request: "push", ifMatch: match, sent: try PartyJSON.parse(sent), status: 409))
                return Self.reply(#"{"ok":false,"error":"revision_conflict","message":"stale"}"#, status: 409)
            }
            stored = sent
            revision += 1
            log.append(.init(request: "push", ifMatch: match, sent: try PartyJSON.parse(sent), status: 200, revision: revision))
            return Self.reply(#"{"ok":true,"revision":\#(revision),"updatedAt":1791504060}"#)
        default:
            XCTFail("Unexpected request \(request.method) \(request.path)")
            return Self.reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, status: 404)
        }
    }

    private static func reply(_ text: String, status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}
