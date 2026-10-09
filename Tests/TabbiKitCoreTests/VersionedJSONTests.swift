import XCTest
import TabbiKitCore

final class VersionedJSONTests: XCTestCase {
    private struct Note: Codable, Equatable {
        var title: String
        var minutes: Int
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The format

    func testEncodingStampsTheCurrentVersionNextToTheValuesKeys() throws {
        let data = try VersionedJSON(current: 3).encode(Note(title: "Read", minutes: 25))
        let json = try object(data)
        XCTAssertEqual(json["schemaVersion"] as? Int, 3)
        XCTAssertEqual(json["title"] as? String, "Read")
        XCTAssertEqual(json["minutes"] as? Int, 25)
        XCTAssertEqual(VersionedJSON.version(of: data), 3)
    }

    func testADocumentWithoutAVersionIsVersionZeroAndStillDecodes() throws {
        let legacy = Data(#"{"title":"Read","minutes":25}"#.utf8)
        XCTAssertEqual(VersionedJSON.version(of: legacy), 0)
        XCTAssertEqual(try VersionedJSON(current: 1).decode(Note.self, from: legacy), Note(title: "Read", minutes: 25))
    }

    func testStepsNewerThanTheDocumentRunInOrderBeforeDecoding() throws {
        let schema = VersionedJSON(current: 3, migrations: [
            // 1: "name" became "title".
            .init(version: 1) { json in json["title"] = json.removeValue(forKey: "name") },
            // 3: "seconds" became "minutes".
            .init(version: 3) { json in
                json["minutes"] = (json.removeValue(forKey: "seconds") as? Int ?? 0) / 60
            },
        ])
        let v0 = Data(#"{"name":"Read","seconds":1500}"#.utf8)
        XCTAssertEqual(try schema.decode(Note.self, from: v0), Note(title: "Read", minutes: 25))

        // A version 2 document only needs the last step; "name" must not be touched.
        let v2 = Data(#"{"schemaVersion":2,"title":"Read","seconds":600}"#.utf8)
        XCTAssertEqual(try schema.decode(Note.self, from: v2), Note(title: "Read", minutes: 10))
    }

    func testADocumentFromANewerBuildDecodesAsItIsAndIgnoresUnknownKeys() throws {
        let schema = VersionedJSON(current: 1, migrations: [
            .init(version: 1) { _ in XCTFail("A newer document must not be migrated") },
        ])
        let newer = Data(#"{"schemaVersion":7,"title":"Read","minutes":25,"color":"blue"}"#.utf8)
        XCTAssertEqual(try schema.decode(Note.self, from: newer), Note(title: "Read", minutes: 25))
    }

    // MARK: The files that use it

    func testAPlannerDayWrittenBeforeVersionsLoadsAndIsSavedWithAVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PlannerRepository(directory: directory)
        let key = try XCTUnwrap(PlannerDayKey(rawValue: "2026-10-02"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = #"""
        {"date":"2026-10-02","items":[{"createdAt":"2026-10-02T08:00:00Z",
        "id":"7B0E7A3C-3C1B-4F5E-9C59-2C1F0A7C9E11","isDone":false,"title":"Ward round notes"}]}
        """#
        try Data(legacy.utf8).write(to: repository.fileURL(for: key))

        let day = try XCTUnwrap(repository.load(key))
        XCTAssertEqual(day.items.map(\.title), ["Ward round notes"])

        try repository.save(day)
        let saved = try Data(contentsOf: repository.fileURL(for: key))
        XCTAssertEqual(VersionedJSON.version(of: saved), PlannerRepository.schema.current)
        XCTAssertEqual(try repository.load(key), day)
    }

    func testAReviewRoundTripsWithAVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DayReviewRepository(directory: directory)
        let key = try XCTUnwrap(PlannerDayKey(rawValue: "2026-10-02"))
        let review = DayReview(date: key, done: ["Pharmacology deck"], carryingOver: [],
                               focusSessions: 2, focusMinutes: 50)
        try repository.save(review)
        XCTAssertEqual(VersionedJSON.version(of: try Data(contentsOf: repository.fileURL(for: key))), 1)
        XCTAssertEqual(try repository.load(key), review)
    }

    func testAStudyLogWrittenBeforeVersionsLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"entries":[]}"#.utf8).write(to: url)
        XCTAssertEqual(try StudyLog.load(from: url), StudyLog())

        try StudyLog().write(to: url)
        XCTAssertEqual(VersionedJSON.version(of: try Data(contentsOf: url)), StudyLog.schema.current)
    }

    func testClaudeLimitsSavedBeforeVersionsStillRestore() throws {
        // `fetchedAt` in JSONEncoder's default date format (seconds since 2001).
        let legacy = Data(#"{"status":"allowed","fiveHour":{"utilization":0.42},"fetchedAt":780000000}"#.utf8)
        let record = try XCTUnwrap(ClaudeLimitsRecord(encoded: legacy))
        XCTAssertEqual(record.snapshot.fiveHour?.utilization, 0.42)
        XCTAssertEqual(record.fetchedAt, Date(timeIntervalSinceReferenceDate: 780_000_000))

        let saved = try XCTUnwrap(record.encoded())
        XCTAssertEqual(VersionedJSON.version(of: saved), ClaudeLimitsRecord.schema.current)
        XCTAssertEqual(ClaudeLimitsRecord(encoded: saved), record)
    }

    // MARK: Focus timer keys

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        try body(InMemoryDefaults())
    }

    func testSettingsMigrationMovesTheFocusTimerOffThePlannerKeys() throws {
        try withDefaults { defaults in
            var timer = FocusTimer()
            timer.linkedItemID = UUID()
            let log = FocusSessionLog(sessions: [.init(endedAt: Date(timeIntervalSinceReferenceDate: 0), duration: 1500)])
            defaults.set(try JSONEncoder().encode(timer), forKey: "planner.focusTimer")
            defaults.set(try JSONEncoder().encode(log), forKey: "planner.focusSessions")

            SettingsSchema.migrate(defaults)

            XCTAssertNil(defaults.object(forKey: "planner.focusTimer"))
            XCTAssertNil(defaults.object(forKey: "planner.focusSessions"))
            let storage = FocusTimerStorage(defaults: defaults)
            XCTAssertEqual(storage.loadTimer(), timer)
            var moved: [FocusSessionLog] = []
            storage.moveSessionLog { moved.append($0); return true }
            storage.moveSessionLog { moved.append($0); return true }
            XCTAssertEqual(moved, [log], "the legacy log is handed out once")
        }
    }

    func testTheLegacySessionLogStaysUntilItIsMoved() throws {
        try withDefaults { defaults in
            let storage = FocusTimerStorage(defaults: defaults)
            let log = FocusSessionLog(sessions: [.init(endedAt: Date(timeIntervalSinceReferenceDate: 0), duration: 1500)])
            defaults.set(try FocusTimerStorage.sessionLogSchema.encode(log), forKey: FocusTimerStorage.sessionLogKey)

            storage.moveSessionLog { _ in false }
            XCTAssertNotNil(defaults.object(forKey: FocusTimerStorage.sessionLogKey), "a failed move keeps the history")

            var moved: [FocusSessionLog] = []
            storage.moveSessionLog { moved.append($0); return true }
            XCTAssertEqual(moved, [log])
            XCTAssertNil(defaults.object(forKey: FocusTimerStorage.sessionLogKey))
        }
    }

    func testAnUnreadableLegacySessionLogIsDropped() throws {
        try withDefaults { defaults in
            let storage = FocusTimerStorage(defaults: defaults)
            defaults.set(Data("not json".utf8), forKey: FocusTimerStorage.sessionLogKey)

            storage.moveSessionLog { _ in XCTFail("nothing to move"); return true }
            XCTAssertNil(defaults.object(forKey: FocusTimerStorage.sessionLogKey))
        }
    }

    func testTheMoveNeverOverwritesANewerFocusTimer() throws {
        try withDefaults { defaults in
            let storage = FocusTimerStorage(defaults: defaults)
            var current = FocusTimer()
            current.linkedItemID = UUID()
            storage.save(current)
            defaults.set(try JSONEncoder().encode(FocusTimer()), forKey: "planner.focusTimer")
            defaults.set(1, forKey: SettingsSchema.versionKey)

            SettingsSchema.migrate(defaults)

            XCTAssertEqual(storage.loadTimer(), current)
            XCTAssertNil(defaults.object(forKey: "planner.focusTimer"))
        }
    }

    func testFocusTimerStorageSavesVersionedDocuments() throws {
        try withDefaults { defaults in
            FocusTimerStorage(defaults: defaults).save(FocusTimer())
            let data = try XCTUnwrap(defaults.data(forKey: FocusTimerStorage.timerKey))
            XCTAssertEqual(VersionedJSON.version(of: data), FocusTimerStorage.timerSchema.current)
        }
    }
}
