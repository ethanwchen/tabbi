import Foundation
import TabbiKitCore
import XCTest

/// Pins the activity log's records and day files, how a record is normalized
/// when it is made, which day file it lands in, the exact JSON
/// `ActivityLogRepository` writes, and how it reads day files back (older
/// versions, newer ones and broken ones), to the golden fixture
/// `shared/fixtures/activity-log/activity-log.json`.
///
/// Streaks, the weekly recap and the pet all read these files, so the
/// Windows port replays the same records and files and must write and read
/// the same days. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an
/// intended change.
final class ActivityLogGoldenTests: XCTestCase {
    func testActivityLogMatchesGoldenFixture() throws {
        let url = ActivityLogGoldenFixture.url
        let current = try ActivityLogGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(ActivityLogGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Activity log constants changed")
        XCTAssertEqual(stored.records.map(\.name), current.records.map(\.name))
        for (old, new) in zip(stored.records, current.records) {
            XCTAssertEqual(old, new, "Record \(old.name)")
        }
        XCTAssertEqual(stored.days.records, current.days.records, "Day records changed")
        XCTAssertEqual(stored.days.zones.map(\.timeZone), current.days.zones.map(\.timeZone))
        for (old, new) in zip(stored.days.zones, current.days.zones) {
            XCTAssertEqual(old, new, "Days in \(old.timeZone)")
        }
        XCTAssertEqual(stored.appends.map(\.name), current.appends.map(\.name))
        for (old, new) in zip(stored.appends, current.appends) {
            XCTAssertEqual(old.input, new.input, old.name)
            XCTAssertEqual(old.output.files.map(\.name), new.output.files.map(\.name), "Append \(old.name) file names")
            for (oldFile, newFile) in zip(old.output.files, new.output.files) {
                XCTAssertEqual(oldFile, newFile, "Append \(old.name), file \(oldFile.name)")
            }
            XCTAssertEqual(old.output, new.output, "Append \(old.name)")
        }
        XCTAssertEqual(stored.reads.map(\.name), current.reads.map(\.name))
        for (old, new) in zip(stored.reads, current.reads) {
            XCTAssertEqual(old, new, "Read \(old.name)")
        }
        XCTAssertEqual(stored, current, "The activity log no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(ActivityLogGoldenFixture.self,
                                              from: Data(contentsOf: ActivityLogGoldenFixture.url))
        for record in stored.records {
            XCTAssertEqual(ActivityLogGoldenFixture.Record(record.input.activityRecord), record.record, record.name)
        }
        for zone in stored.days.zones {
            XCTAssertEqual(ActivityLogGoldenFixture.days(of: stored.days.records, in: zone.timeZone), zone.days,
                           zone.timeZone)
        }
        for append in stored.appends {
            XCTAssertEqual(try ActivityLogGoldenFixture.append(append.input, tag: "replay", name: append.name),
                           append.output, append.name)
        }
        for read in stored.reads {
            XCTAssertEqual(try ActivityLogGoldenFixture.read(read.contents, tag: "replay", name: read.name), read.records,
                           read.name)
        }
    }
}

/// Activity records as they are made, the days they count toward, the day
/// files appending them writes, and day files read back.
struct ActivityLogGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.activity-log.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/activity-log/activity-log.json")
    }

    struct Constants: Codable, Equatable {
        /// The folder in the edition's storage that holds the day files.
        var folderName: String
        /// The top-level key that carries a day file's version.
        var versionKey: String
        /// The version this build writes.
        var schemaVersion: Int
        /// The versions that have an upgrade step (none so far).
        var migrations: [Int]
        var kinds: [String: String]
        var units: [String: String]
        var metadataKeys: [String: String]
    }

    /// A record as handed to `ActivityRecord.init`: times are seconds since
    /// 1970 and may carry fractions, `end` may be absent.
    struct RecordInput: Codable, Equatable {
        var id: String
        var source: String
        var kind: String
        var start: Double
        var end: Double?
        var quantity: Double?
        var unit: String?
        var subject: String?
        var metadata: [String: String]

        var activityRecord: ActivityRecord {
            ActivityRecord(id: UUID(uuidString: id)!, source: ModuleID(rawValue: source), kind: ActivityKind(rawValue: kind),
                           start: Date(timeIntervalSince1970: start), end: end.map { Date(timeIntervalSince1970: $0) },
                           quantity: quantity, unit: unit.map { ActivityUnit(rawValue: $0) }, subject: subject,
                           metadata: metadata)
        }
    }

    /// A record as the app holds it: whole seconds, `end` never before
    /// `start`, and the id as an upper-case UUID string.
    struct Record: Codable, Equatable {
        var id: String
        var source: String
        var kind: String
        var start: Double
        var end: Double
        var quantity: Double?
        var unit: String?
        var subject: String?
        var metadata: [String: String]

        init(_ record: ActivityRecord) {
            id = record.id.uuidString
            source = record.source.rawValue
            kind = record.kind.rawValue
            start = record.start.timeIntervalSince1970
            end = record.end.timeIntervalSince1970
            quantity = record.quantity
            unit = record.unit?.rawValue
            subject = record.subject
            metadata = record.metadata
        }
    }

    struct RecordCase: Codable, Equatable {
        var name: String
        var input: RecordInput
        var record: Record
    }

    /// The day (`yyyy-MM-dd`, the day file's name without `.json`) each of
    /// `Days.records` counts toward in `timeZone`.
    struct ZoneDays: Codable, Equatable {
        var timeZone: String
        var days: [String]
    }

    struct Days: Codable, Equatable {
        var records: [RecordInput]
        var zones: [ZoneDays]
    }

    /// A file in the folder before the appends run.
    struct SeedFile: Codable, Equatable {
        var name: String
        var contents: String
    }

    /// A day file's JSON as written: dates are ISO 8601 strings.
    struct StoredRecord: Codable, Equatable {
        var id: String
        var source: String
        var kind: String
        var start: String
        var end: String
        var quantity: Double?
        var unit: String?
        var subject: String?
        var metadata: [String: String]
    }

    struct DayDocument: Codable, Equatable {
        var schemaVersion: Int
        var records: [StoredRecord]
    }

    /// A file in the folder after the appends: its exact text, and its JSON
    /// value when it is a day document.
    struct WrittenFile: Codable, Equatable {
        var name: String
        var contents: String
        var document: DayDocument?
    }

    struct AppendInput: Codable, Equatable {
        var timeZone: String
        var seed: [SeedFile]
        /// Each batch is one `append` call.
        var batches: [[RecordInput]]
    }

    struct AppendOutput: Codable, Equatable {
        /// Whether each batch's `append` threw.
        var threw: [Bool]
        /// Every file in the folder, by name.
        var files: [WrittenFile]
        /// The days with a day file, oldest first.
        var savedDays: [String]
        /// Every record that reads back from the folder, oldest day first.
        var readBack: [Record]
    }

    struct AppendCase: Codable, Equatable {
        var name: String
        var input: AppendInput
        var output: AppendOutput
    }

    /// A day file's text and the records it reads as, or null when the
    /// repository refuses it.
    struct ReadCase: Codable, Equatable {
        var name: String
        var contents: String
        var records: [Record]?
    }

    var schema = Self.schemaName
    var version = 1
    var constants: Constants
    var records: [RecordCase]
    var days: Days
    var appends: [AppendCase]
    var reads: [ReadCase]

    static func current() throws -> ActivityLogGoldenFixture {
        ActivityLogGoldenFixture(
            constants: Constants(
                folderName: ActivityLogRepository.folderName,
                versionKey: VersionedJSON.versionKey,
                schemaVersion: ActivityLogRepository.schema.current,
                migrations: ActivityLogRepository.schema.migrations.map(\.version),
                kinds: [
                    "focusCompleted": ActivityKind.focusCompleted.rawValue,
                    "breakTaken": ActivityKind.breakTaken.rawValue,
                    "cardsReviewed": ActivityKind.cardsReviewed.rawValue,
                    "taskCompleted": ActivityKind.taskCompleted.rawValue,
                ],
                units: ["minutes": ActivityUnit.minutes.rawValue, "cards": ActivityUnit.cards.rawValue],
                metadataKeys: ["outcome": ActivityMetadata.outcome, "method": ActivityMetadata.method]
            ),
            records: sampleRecords.map { name, input in
                RecordCase(name: name, input: input, record: Record(input.activityRecord))
            },
            days: Days(records: dayRecords, zones: timeZones.map { ZoneDays(timeZone: $0, days: days(of: dayRecords, in: $0)) }),
            appends: try sampleAppends.map { name, input in
                AppendCase(name: name, input: input, output: try append(input, tag: "record", name: name))
            },
            reads: try sampleReads.map { name, contents in
                ReadCase(name: name, contents: contents, records: try read(contents, tag: "record", name: name))
            }
        )
    }

    // MARK: Running

    static func zoneCalendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    static func days(of records: [RecordInput], in timeZone: String) -> [String] {
        let calendar = zoneCalendar(timeZone)
        return records.map { $0.activityRecord.day(calendar: calendar).rawValue }
    }

    /// Runs `body` with an empty folder under the temporary directory, named
    /// after the case, and removes the folder afterwards.
    private static func withFolder<Value>(_ name: String, _ body: (URL) throws -> Value) throws -> Value {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TabbiActivityLogGolden-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try body(folder)
    }

    static func append(_ input: AppendInput, tag: String, name: String) throws -> AppendOutput {
        try withFolder("append-\(tag)-\(name)") { folder -> AppendOutput in
            let repository = ActivityLogRepository(directory: folder, calendar: zoneCalendar(input.timeZone))
            if !input.seed.isEmpty {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in input.seed {
                    try Data(file.contents.utf8).write(to: folder.appendingPathComponent(file.name))
                }
            }
            let threw = input.batches.map { batch -> Bool in
                do {
                    try repository.append(batch.map(\.activityRecord))
                    return false
                } catch {
                    return true
                }
            }
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
            let files = try names.map { fileName -> WrittenFile in
                let data = try Data(contentsOf: folder.appendingPathComponent(fileName))
                return WrittenFile(name: fileName, contents: String(decoding: data, as: UTF8.self),
                                   document: try? JSONDecoder().decode(DayDocument.self, from: data))
            }
            let readBack = repository.records(from: PlannerDayKey(rawValue: "1970-01-01")!,
                                              through: PlannerDayKey(rawValue: "2999-12-31")!)
            return AppendOutput(threw: threw, files: files, savedDays: repository.savedDays().map(\.rawValue),
                                readBack: readBack.map { Record($0) })
        }
    }

    /// Reads `contents` as the day file of 2 October 2026; nil when the
    /// repository throws.
    static func read(_ contents: String, tag: String, name: String) throws -> [Record]? {
        try withFolder("read-\(tag)-\(name)") { folder -> [Record]? in
            let repository = ActivityLogRepository(directory: folder, calendar: zoneCalendar("UTC"))
            let day = PlannerDayKey(rawValue: "2026-10-02")!
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: repository.fileURL(for: day))
            return (try? repository.records(on: day))?.map { Record($0) }
        }
    }

    // MARK: Samples

    private static let timeZones = [
        "UTC", "America/New_York", "America/Los_Angeles", "Europe/London", "Asia/Kolkata", "Australia/Sydney",
        "Pacific/Kiritimati", "Pacific/Pago_Pago",
    ]

    /// Seconds since 1970 of a UTC wall-clock time.
    private static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
                            _ second: Int = 0) -> Double {
        zoneCalendar("UTC").date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute,
                                                  second: second))!.timeIntervalSince1970
    }

    private static func id(_ number: Int) -> String {
        String(format: "00000000-0000-4000-8000-%012d", number)
    }

    private static func focus(_ number: Int, endingAt end: Double, minutes: Double, source: String = "focus",
                              metadata: [String: String] = ["method": "pomodoro", "outcome": "completed"]) -> RecordInput {
        RecordInput(id: id(number), source: source, kind: "focus.completed", start: end - minutes * 60, end: end,
                    quantity: minutes, unit: "min", subject: nil, metadata: metadata)
    }

    private static func moment(_ number: Int, at time: Double, kind: String = "task.completed",
                               source: String = "planner", subject: String? = nil) -> RecordInput {
        RecordInput(id: id(number), source: source, kind: kind, start: time, end: nil, quantity: nil, unit: nil,
                    subject: subject, metadata: [:])
    }

    private static var sampleRecords: [(String, RecordInput)] {
        let nine = utc(2026, 10, 2, 9)
        return [
            ("focus-whole-seconds", focus(1, endingAt: nine, minutes: 25)),
            ("moment-without-end", moment(2, at: nine, subject: "4D1C7E3A-2B6F-4A8E-9C0D-5E7F8A9B0C1D")),
            ("end-before-start-clamped", RecordInput(id: id(3), source: "focus", kind: "break.taken", start: nine,
                                                     end: nine - 3600, quantity: 5, unit: "min", subject: nil,
                                                     metadata: [:])),
            ("half-second-rounds-up", RecordInput(id: id(4), source: "study", kind: "focus.completed",
                                                  start: nine - 1500.5, end: nine + 0.5, quantity: 25, unit: "min",
                                                  subject: nil, metadata: [:])),
            ("under-half-second-rounds-down", RecordInput(id: id(5), source: "study", kind: "focus.completed",
                                                          start: nine - 1500.49, end: nine + 0.49, quantity: 25,
                                                          unit: "min", subject: nil, metadata: [:])),
            ("fractional-quantity", focus(6, endingAt: nine, minutes: 24.6)),
            ("cards", RecordInput(id: id(7), source: "anki", kind: "cards.reviewed", start: nine - 600, end: nine,
                                  quantity: 40, unit: "cards", subject: nil, metadata: ["deck": "Pharmacology"])),
            ("open-kind-and-source", RecordInput(id: id(8), source: "leetcode", kind: "problem.solved", start: nine,
                                                 end: nil, quantity: 1, unit: "problems", subject: "two-sum",
                                                 metadata: [:])),
            ("lower-case-id", RecordInput(id: "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d", source: "planner",
                                          kind: "task.completed", start: nine, end: nil, quantity: nil, unit: nil,
                                          subject: nil, metadata: [:])),
        ]
    }

    /// Instants around midnight and daylight saving changes in the zones the
    /// fixture covers.
    private static var dayRecords: [RecordInput] {
        [
            // New York: the last second of Saturday 7 March (EST) and midnight Sunday.
            moment(101, at: utc(2026, 3, 8, 4, 59, 59)),
            moment(102, at: utc(2026, 3, 8, 5)),
            // New York 03:30 EDT, just after clocks spring forward on 8 March.
            moment(103, at: utc(2026, 3, 8, 7, 30)),
            // London: 00:30 GMT and 02:30 BST on 29 March, either side of the change.
            moment(104, at: utc(2026, 3, 29, 0, 30)),
            moment(105, at: utc(2026, 3, 29, 1, 30)),
            // Sydney: midnight AEDT on 5 April and 23:30 AEST that evening, after clocks fall back.
            moment(106, at: utc(2026, 4, 4, 13)),
            moment(107, at: utc(2026, 4, 5, 13, 30)),
            // Kolkata: the last second of 1 October and its midnight (UTC+05:30).
            moment(108, at: utc(2026, 10, 1, 18, 29, 59)),
            moment(109, at: utc(2026, 10, 1, 18, 30)),
            // New York 23:40 to 00:10: counts toward the day it ended.
            focus(110, endingAt: utc(2026, 10, 2, 4, 10), minutes: 30),
            // New York 23:59:59.5 rounds to midnight, so it lands on the next day.
            RecordInput(id: id(111), source: "focus", kind: "focus.completed", start: utc(2026, 10, 2, 3, 30),
                        end: utc(2026, 10, 2, 3, 59, 59) + 0.5, quantity: 30, unit: "min", subject: nil, metadata: [:]),
            // New York 01:30 EDT and 01:30 EST on 1 November, the hour that repeats.
            moment(112, at: utc(2026, 11, 1, 5, 30)),
            moment(113, at: utc(2026, 11, 1, 6, 30)),
            // New York: the last second of Sunday 1 November (EST) and midnight Monday.
            moment(114, at: utc(2026, 11, 2, 4, 59, 59)),
            moment(115, at: utc(2026, 11, 2, 5)),
            // Kiritimati (UTC+14) and Pago Pago (UTC-11) are two days apart for an hour.
            moment(116, at: utc(2026, 10, 2, 10, 30)),
            // An end before the start: the day follows the start.
            RecordInput(id: id(117), source: "focus", kind: "break.taken", start: utc(2026, 10, 3, 0, 30),
                        end: utc(2026, 10, 2, 23, 30), quantity: 5, unit: "min", subject: nil, metadata: [:]),
        ]
    }

    private static var sampleAppends: [(String, AppendInput)] {
        let day = utc(2026, 10, 2, 0)
        let task = RecordInput(id: id(204), source: "planner", kind: "task.completed", start: day + 15 * 3600, end: nil,
                               quantity: nil, unit: nil, subject: "notes/ch-1 caf\u{E9} \"draft\"", metadata: [:])
        let cards = RecordInput(id: id(205), source: "anki", kind: "cards.reviewed", start: day + 13 * 3600,
                                end: day + 13 * 3600 + 900, quantity: 12, unit: "cards", subject: nil, metadata: [:])
        let rest = RecordInput(id: id(206), source: "focus", kind: "break.taken", start: day + 9 * 3600,
                               end: day + 9 * 3600 + 300, quantity: 5, unit: "min", subject: nil, metadata: [:])
        let legacy = """
        {"records": [{"id": "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E", "source": "anki", "kind": "cards.reviewed",
                      "start": "2026-10-02T09:00:00Z", "quantity": 12, "unit": "cards"}]}
        """
        return [
            ("two-days-utc", AppendInput(timeZone: "UTC", seed: [], batches: [[
                focus(201, endingAt: day + 21 * 3600, minutes: 50, source: "study",
                      metadata: ["method": "flowtime", "outcome": "stopped"]),
                focus(202, endingAt: day + 32 * 3600, minutes: 25),
                focus(203, endingAt: day + 9 * 3600 - 300, minutes: 24.6),
                task, cards, rest,
            ]])),
            ("merge-and-skip-duplicates-new-york", AppendInput(timeZone: "America/New_York", seed: [], batches: [
                [focus(211, endingAt: utc(2026, 10, 2, 18), minutes: 25)],
                [focus(212, endingAt: utc(2026, 10, 2, 13), minutes: 25), focus(211, endingAt: utc(2026, 10, 2, 18), minutes: 25)],
                [focus(211, endingAt: utc(2026, 10, 2, 18), minutes: 25)],
            ])),
            ("midnight-and-daylight-saving-new-york", AppendInput(timeZone: "America/New_York", seed: [], batches: [[
                focus(221, endingAt: utc(2026, 10, 2, 4, 10), minutes: 30),
                RecordInput(id: id(222), source: "focus", kind: "focus.completed", start: utc(2026, 10, 2, 3, 30),
                            end: utc(2026, 10, 2, 3, 59, 59) + 0.5, quantity: 30, unit: "min", subject: nil,
                            metadata: [:]),
                moment(223, at: utc(2026, 10, 2, 3, 59, 58)),
                moment(224, at: utc(2026, 11, 1, 5, 30)),
                moment(225, at: utc(2026, 11, 1, 6, 30)),
                moment(226, at: utc(2026, 3, 8, 7, 30)),
                moment(227, at: utc(2026, 3, 8, 4, 59, 59)),
            ]])),
            ("half-hour-zone-kolkata", AppendInput(timeZone: "Asia/Kolkata", seed: [], batches: [[
                moment(231, at: utc(2026, 10, 1, 18, 29, 59)),
                moment(232, at: utc(2026, 10, 1, 18, 30)),
            ]])),
            ("unreadable-day-is-kept", AppendInput(timeZone: "UTC", seed: [
                SeedFile(name: "2026-10-02.json", contents: "{\"records\": 42}"),
                SeedFile(name: "readme.txt", contents: "notes"),
            ], batches: [[
                focus(241, endingAt: utc(2026, 10, 1, 9), minutes: 25),
                focus(242, endingAt: utc(2026, 10, 2, 9), minutes: 25),
                focus(243, endingAt: utc(2026, 10, 3, 9), minutes: 25),
            ]])),
            ("legacy-day-file-rewritten", AppendInput(timeZone: "UTC", seed: [
                SeedFile(name: "2026-10-02.json", contents: legacy),
            ], batches: [[
                focus(251, endingAt: utc(2026, 10, 2, 8), minutes: 25),
            ]])),
        ]
    }

    private static let sampleReads: [(String, String)] = [
        ("current-version", """
        {
          "records" : [
            {
              "end" : "2026-10-02T09:00:00Z",
              "id" : "00000000-0000-4000-8000-000000000301",
              "kind" : "focus.completed",
              "metadata" : {
                "method" : "pomodoro",
                "outcome" : "completed"
              },
              "quantity" : 25,
              "source" : "focus",
              "start" : "2026-10-02T08:35:00Z",
              "unit" : "min"
            }
          ],
          "schemaVersion" : 1
        }
        """),
        ("legacy-without-version", """
        {"records": [{"id": "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E", "source": "anki", "kind": "cards.reviewed",
                      "start": "2026-10-02T09:00:00Z", "quantity": 12, "unit": "cards"}]}
        """),
        ("newer-version-with-unknown-keys", """
        {"schemaVersion": 2, "device": "mac", "records": [{"id": "00000000-0000-4000-8000-000000000302",
          "source": "focus", "kind": "focus.completed", "start": "2026-10-02T08:35:00Z", "end": "2026-10-02T09:00:00Z",
          "quantity": 25, "unit": "min", "metadata": {}, "mood": "calm"}]}
        """),
        ("offset-dates", """
        {"schemaVersion": 1, "records": [{"id": "00000000-0000-4000-8000-000000000303", "source": "focus",
          "kind": "focus.completed", "start": "2026-10-02T10:35:00+02:00", "end": "2026-10-02T05:00:00-04:00",
          "quantity": 25, "unit": "min", "metadata": {}}]}
        """),
        ("end-before-start-clamped", """
        {"schemaVersion": 1, "records": [{"id": "00000000-0000-4000-8000-000000000304", "source": "focus",
          "kind": "break.taken", "start": "2026-10-02T09:00:00Z", "end": "2026-10-02T08:00:00Z", "metadata": {}}]}
        """),
        ("null-optionals", """
        {"schemaVersion": 1, "records": [{"id": "00000000-0000-4000-8000-000000000305", "source": "planner",
          "kind": "task.completed", "start": "2026-10-02T09:00:00Z", "end": null, "quantity": null, "unit": null,
          "subject": null, "metadata": null}]}
        """),
        ("lower-case-id", """
        {"schemaVersion": 1, "records": [{"id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d", "source": "planner",
          "kind": "task.completed", "start": "2026-10-02T09:00:00Z", "end": "2026-10-02T09:00:00Z", "metadata": {}}]}
        """),
        ("records-kept-in-file-order", """
        {"schemaVersion": 1, "records": [
          {"id": "00000000-0000-4000-8000-000000000306", "source": "focus", "kind": "focus.completed",
           "start": "2026-10-02T14:35:00Z", "end": "2026-10-02T15:00:00Z", "quantity": 25, "unit": "min", "metadata": {}},
          {"id": "00000000-0000-4000-8000-000000000307", "source": "focus", "kind": "focus.completed",
           "start": "2026-10-02T08:35:00Z", "end": "2026-10-02T09:00:00Z", "quantity": 25, "unit": "min", "metadata": {}}]}
        """),
        ("empty-records", "{\"schemaVersion\": 1, \"records\": []}"),
        ("missing-records", "{\"schemaVersion\": 1}"),
        ("records-not-an-array", "{\"records\": 42}"),
        ("not-json", "not json"),
        ("missing-id", """
        {"schemaVersion": 1, "records": [{"source": "focus", "kind": "focus.completed",
          "start": "2026-10-02T09:00:00Z", "metadata": {}}]}
        """),
        ("invalid-id", """
        {"schemaVersion": 1, "records": [{"id": "301", "source": "focus", "kind": "focus.completed",
          "start": "2026-10-02T09:00:00Z", "metadata": {}}]}
        """),
        ("date-as-number", """
        {"schemaVersion": 1, "records": [{"id": "00000000-0000-4000-8000-000000000308", "source": "focus",
          "kind": "focus.completed", "start": 781088400, "metadata": {}}]}
        """),
        ("date-without-zone", """
        {"schemaVersion": 1, "records": [{"id": "00000000-0000-4000-8000-000000000309", "source": "focus",
          "kind": "focus.completed", "start": "2026-10-02T09:00:00", "metadata": {}}]}
        """),
    ]
}
