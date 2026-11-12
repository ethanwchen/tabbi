import Foundation
import XCTest
@testable import TabbiKitCore

/// Pins the Study Crews contract to two golden fixtures the Windows port and
/// the backend tests read too:
///
/// - `shared/fixtures/crews/crews.json`: the protocol, every request body
///   the app sends (checked against `shared/schemas/crews.v1.schema.json` by
///   `backend/test/compat.test.ts`), sample replies with what the app reads
///   from them (`summary`), and the language-neutral parts of the hours and
///   countdown formats, the session queue's merging, the draft checks and
///   invite link parsing;
/// - `shared/fixtures/crews/crests.json`: a spread of crests composed as
///   characters (every frame with every emblem, every color, laurel and pip
///   count) and every palette, so a port draws the same pixels. The design's
///   reference compositor draws the same crests.
///
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite them after an intended change.
final class CrewsGoldenTests: XCTestCase {
    private var recording: Bool { ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" }

    func testCrewsContractMatchesGoldenFixture() async throws {
        let current = try await CrewsFixture.current()
        if recording {
            try FileManager.default.createDirectory(at: CrewsFixture.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try CrewsFixture.encode(current).write(to: CrewsFixture.url)
            return
        }
        let stored = try CrewsFixture.decoder.decode(CrewsFixture.self, from: Data(contentsOf: CrewsFixture.url))
        XCTAssertEqual(stored.protocolVersion, current.protocolVersion)
        for (old, new) in zip(stored.requests, current.requests) { XCTAssertEqual(old, new, old.name) }
        for (old, new) in zip(stored.replies, current.replies) { XCTAssertEqual(old, new, old.name) }
        XCTAssertEqual(stored, current, "The Crews contract no longer matches \(CrewsFixture.url.lastPathComponent)")
    }

    func testCrewCrestsMatchGoldenFixture() throws {
        let current = CrewCrestsFixture.current()
        if recording {
            try FileManager.default.createDirectory(at: CrewCrestsFixture.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: CrewCrestsFixture.url)
            return
        }
        let stored = try JSONDecoder().decode(CrewCrestsFixture.self, from: Data(contentsOf: CrewCrestsFixture.url))
        for (old, new) in zip(stored.cases, current.cases) {
            XCTAssertEqual(old, new, "\(old.frame) \(old.emblem) \(old.color) \(old.laurel ?? "none") \(old.pips)")
        }
        XCTAssertEqual(stored, current, "The crew crests no longer match \(CrewCrestsFixture.url.lastPathComponent)")
    }

    /// The fixture's replies, read back from the file alone, give the
    /// recorded summaries, as a port reading only the file would.
    func testStoredRepliesReadAsRecorded() throws {
        try XCTSkipIf(recording, "Recording")
        let stored = try CrewsFixture.decoder.decode(CrewsFixture.self, from: Data(contentsOf: CrewsFixture.url))
        for reply in stored.replies {
            XCTAssertEqual(try CrewsFixture.summary(of: reply.json.data(), schema: reply.schema), reply.summary, reply.name)
        }
    }
}

/// Any JSON value, kept as is in the fixture.
indirect enum CrewJSON: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([CrewJSON])
    case object([String: CrewJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([CrewJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: CrewJSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 { try container.encode(Int(value)) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    init(data: Data) throws { self = try JSONDecoder().decode(CrewJSON.self, from: data) }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

struct CrewsFixture: Codable, Equatable {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/fixtures/crews/crews.json")

    struct Request: Codable, Equatable {
        var name: String
        var method: String
        var path: String
        /// The `$defs` name of the body in `crews.v1.schema.json`, nil without a body.
        var schema: String?
        var body: CrewJSON?
    }

    struct Reply: Codable, Equatable {
        var name: String
        var schema: String
        var json: CrewJSON
        /// What the app reads from it, one line per fact (see `summary(of:schema:)`).
        var summary: [String]
    }

    struct HoursCase: Codable, Equatable {
        var minutes: Int
        /// Tenths of an hour, rounded down; the app always shows one decimal.
        var tenths: Int
    }

    struct RemainingCase: Codable, Equatable {
        var seconds: Int
        /// `lessThanAMinute`, `minutes`, `hoursMinutes` or `daysHours`.
        var form: String
        var values: [Int]
    }

    struct WeekCase: Codable, Equatable {
        var at: Int
        var week: CrewWeek
    }

    struct QueueCase: Codable, Equatable {
        var name: String
        /// Finished focus records, in the order they arrive: start, end and quantity in minutes.
        var records: [[Double]]
        /// What the queue holds afterwards: start, end and minutes.
        var pending: [[Int]]
    }

    struct DraftCase: Codable, Equatable {
        var name: String
        var description: String
        /// The `CrewDraftCheck.Problem`, or nil when the draft is fine.
        var problem: String?
    }

    struct InviteCase: Codable, Equatable {
        var text: String
        var code: String?
    }

    var protocolVersion: Int
    var requests: [Request]
    var replies: [Reply]
    var hours: [HoursCase]
    var remaining: [RemainingCase]
    var weeks: [WeekCase]
    var queue: [QueueCase]
    var drafts: [DraftCase]
    var invites: [InviteCase]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol", requests, replies, hours, remaining, weeks, queue, drafts, invites
    }

    /// Dates in this fixture are unix seconds, as on the wire.
    static func encode(_ value: CrewsFixture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value) + Data("\n".utf8)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func current() async throws -> CrewsFixture {
        CrewsFixture(protocolVersion: PartyClient.protocolVersion, requests: try await requests(), replies: try replies(),
                     hours: hoursCases(), remaining: remainingCases(), weeks: weekCases(), queue: queueCases(),
                     drafts: draftCases(), invites: inviteCases())
    }

    // MARK: Requests

    private static func requests() async throws -> [Request] {
        let at = Date(timeIntervalSince1970: 1_793_000_000)
        let calls: [(String, String?, @Sendable (PartyClient) async throws -> Void)] = [
            ("create", "createBody", { _ = try await $0.createCrew(name: "Night Owls", description: "Late study sessions.",
                                                                  crest: CrewCrest(frame: CrewCatalog.frames[0], emblem: CrewCatalog.emblems[0], color: "indigo"),
                                                                  visibility: .private) }),
            ("update name and visibility", "updateBody", { _ = try await $0.updateCrew(CrewDraft(name: "Night Owls 2", visibility: .public)) }),
            ("update the crest", "updateBody", { _ = try await $0.updateCrew(CrewDraft(frame: CrewCatalog.frames.last!,
                                                                                         emblem: CrewCatalog.emblems.last!, color: "teal")) }),
            ("hide my pet", "memberSettingsBody", { _ = try await $0.setShowsPet(false) }),
            ("join by invite", "joinBody", { _ = try await $0.joinCrew(invite: "w4ln-ut7") }),
            ("ask to join a public crew", "joinBody", { _ = try await $0.requestToJoin(id: "MEDSQUAD2K") }),
            ("cancel my request", nil, { _ = try await $0.cancelJoinRequest() }),
            ("approve a request", nil, { _ = try await $0.approveJoinRequest(ref: "LENAREF3QW") }),
            ("decline a request", nil, { _ = try await $0.declineJoinRequest(ref: "LENAREF3QW") }),
            ("leave", nil, { _ = try await $0.leaveCrew() }),
            ("remove a member", nil, { _ = try await $0.removeCrewMember(ref: "MAYAREF4QR") }),
            ("search", nil, { _ = try await $0.searchCrews("night owls+") }),
            ("board", nil, { _ = try await $0.crewBoard() }),
            ("board, next page", nil, { _ = try await $0.crewBoard(cursor: "eyJyIjo1fQ") }),
            ("hall of fame", nil, { _ = try await $0.crewHall() }),
            ("hall of fame, next page", nil, { _ = try await $0.crewHall(cursor: "eyJnIjoxfQ+/=") }),
            ("mine", nil, { _ = try await $0.myCrew() }),
            ("crew page", nil, { _ = try await $0.crew(id: "MEDSQUAD2K") }),
            ("sessions", "sessionsBody", { _ = try await $0.reportCrewSessions([
                CrewSession(start: at, end: at.addingTimeInterval(1500), minutes: 25),
                CrewSession(start: at.addingTimeInterval(1800), end: at.addingTimeInterval(4800), minutes: 48),
            ]) }),
            ("report a crew", "reportBody", { _ = try await $0.reportCrew(id: "MEDSQUAD2K", member: nil, reason: .inappropriateName, note: "  ") }),
            ("report a member", "reportBody", { _ = try await $0.reportCrew(id: "MEDSQUAD2K", member: "AVAREF7K3R", reason: .cheating,
                                                                             note: "Reports 16 hours every day.") }),
            ("block a member", "blockBody", { _ = try await $0.blockCrewMember(crew: "MEDSQUAD2K", member: "AVAREF7K3R") }),
        ]
        var out: [Request] = []
        for (name, schema, call) in calls {
            let transport = RecordingTransport()
            try? await call(PartyClient(transport: transport, token: String(repeating: "a", count: 64)))
            let request = try XCTUnwrap(transport.sent.first, name)
            XCTAssertEqual(request.headers[PartyClient.protocolHeader], String(PartyClient.protocolVersion))
            out.append(Request(name: name, method: request.method, path: request.path, schema: schema,
                               body: try request.body.map { try CrewJSON(data: $0) }))
        }
        return out
    }

    // MARK: Replies

    private static func replies() throws -> [Reply] {
        let samples: [(String, String, String)] = [
            ("mine, in a crew", "mineReply", CrewReplySamples.mine),
            ("mine, no crew", "mineReply", #"{"ok":true,"crew":null,"week":{"id":"2026-W46","startsAt":1794182400,"endsAt":1794787200},"request":null}"#),
            ("board with featured", "boardReply", CrewReplySamples.board),
            ("board, first week", "boardReply", #"{"ok":true,"week":{"id":"2026-W46","startsAt":1794182400,"endsAt":1794787200},"top":[],"featured":null,"rows":[],"next":null,"crewCount":0,"mine":null}"#),
            ("board, next page", "boardReply", CrewReplySamples.boardNext),
            ("board, my crew hidden", "boardReply", #"{"ok":true,"week":{"id":"2026-W46","startsAt":1794182400,"endsAt":1794787200},"top":[],"featured":null,"rows":[],"next":null,"crewCount":0,"mine":{"rank":null,"minutes":0}}"#),
            ("search", "searchReply", CrewReplySamples.search),
            ("hall of fame", "hallReply", CrewReplySamples.hall),
            ("crew page of another crew", "crewReply", CrewReplySamples.visitor),
            ("newer server crew page", "crewReply", CrewReplySamples.newer),
            ("join by invite", "joinReply", CrewReplySamples.join),
            ("ask to join a public crew", "joinReply", CrewReplySamples.requested),
            ("mine, waiting to join", "mineReply", CrewReplySamples.mineWaiting),
            ("approve a request", "crewReply", CrewReplySamples.mine),
            ("cancel a request", "cancelReply", #"{"ok":true,"cancelled":true}"#),
            ("decline a request", "declineReply", #"{"ok":true,"declined":true}"#),
            ("leave", "leaveReply", #"{"ok":true,"left":true}"#),
            ("sessions", "sessionsReply", CrewReplySamples.sessions),
            ("newer server sessions", "sessionsReply", CrewReplySamples.newerSessions),
            ("report", "reportReply", #"{"ok":true,"created":true}"#),
            ("block", "blockReply", #"{"ok":true,"blocked":true}"#),
        ]
        return try samples.map { name, schema, json in
            let data = Data(json.utf8)
            return Reply(name: name, schema: schema, json: try CrewJSON(data: data), summary: try summary(of: data, schema: schema))
        }
    }

    /// What the app reads from a reply, as lines a port can produce the same way.
    static func summary(of data: Data, schema: String) throws -> [String] {
        let decoder = PartyClient.makeDecoder()
        func week(_ week: CrewWeek) -> String {
            "week \(week.id) \(Int(week.startsAt.timeIntervalSince1970))-\(Int(week.endsAt.timeIntervalSince1970))"
        }
        func crew(_ c: CrewSummary) -> String {
            "crew \(c.id) \"\(c.name)\" crest=\(c.crest.resolved.frame)/\(c.crest.resolved.emblem)/\(c.crest.resolved.color) pips=\(c.pips) "
                + "\(c.visibility.rawValue) laurel=\(c.laurel?.rawValue ?? "none") trophies=\(c.trophies) golds=\(c.golds) "
                + "members=\(c.memberCount)/\(c.maxMembers) minutes=\(c.weekMinutes) full=\(c.isFull)"
        }
        func detail(_ d: CrewDetail) -> [String] {
            ["\(crew(d.summary)) rank=\(d.rank.map(String.init) ?? "none") mine=\(d.mine) owner=\(d.owner) "
                + "invite=\(d.inviteCode ?? "none") hidden=\(d.hidden) medals=\(d.medals.gold)/\(d.medals.silver)/\(d.medals.bronze) "
                + "crews=\(d.crewCount)"]
                + d.history.map { "week \($0.week.id) place=\($0.place.map(String.init) ?? "none") minutes=\($0.minutes) medal=\($0.medal?.rawValue ?? "none")" }
                + d.requests.map { "request \($0.ref) \"\($0.name)\" pet=\($0.pet?.petName ?? "hidden") at=\(Int($0.requestedAt.timeIntervalSince1970))-\(Int($0.expiresAt.timeIntervalSince1970))" }
                + d.members.map { m in
                    let pet = m.partyProfile.map { profile -> String in
                        let drawn = PartyPetAppearance.pet(for: profile)
                        return "pet=\"\(profile.petName)\" \(drawn.breed.rawValue) outfit=\(drawn.outfit.rawValue) "
                            + "accessories=\(drawn.accessories.map(\.rawValue).joined(separator: ","))"
                    } ?? "pet=hidden"
                    return "member \(m.ref) \"\(m.name)\" \(pet) level=\(m.studyLevel.map(String.init) ?? "none") "
                        + "minutes=\(m.weekMinutes) owner=\(m.owner) me=\(m.me)"
                }
        }
        func entry(_ e: CrewBoardEntry) -> String {
            "#\(e.rank) \(e.minutes) pets=\(e.pets.map(\.petName).joined(separator: ",")) tied=\(e.tiedWith.joined(separator: ",")) \(crew(e.crew))"
        }
        func request(_ r: CrewMyRequest?) -> [String] {
            r.map { ["waiting \($0.crew.id) at=\(Int($0.requestedAt.timeIntervalSince1970))-\(Int($0.expiresAt.timeIntervalSince1970))"] } ?? []
        }
        switch schema {
        case "mineReply":
            struct R: Decodable { let crew: CrewDetail?; let week: CrewWeek; let request: CrewMyRequest? }
            let r = try decoder.decode(R.self, from: data)
            return [week(r.week)] + (r.crew.map(detail) ?? ["no crew"]) + request(r.request)
        case "crewReply", "joinReply", "removeReply":
            struct R: Decodable { let crew: CrewDetail; let joined: Bool?; let request: CrewMyRequest? }
            let r = try decoder.decode(R.self, from: data)
            return (r.joined.map { ["joined=\($0)"] } ?? []) + request(r.request) + detail(r.crew)
        case "boardReply":
            let r = try decoder.decode(CrewBoard.self, from: data)
            return [week(r.week), "crews=\(r.crewCount) next=\(r.next ?? "none")",
                    "mine=\(r.mine.map { "\($0.rank.map(String.init) ?? "none")/\($0.minutes)" } ?? "none")"]
                + r.top.map(entry) + r.rows.map { "row " + entry($0) }
                + (r.featured.map { ["featured \(week($0.week))"] + $0.entries.map(entry) } ?? ["no featured"])
        case "searchReply":
            struct R: Decodable { let crews: [CrewSummary] }
            return try decoder.decode(R.self, from: data).crews.map(crew)
        case "sessionsReply":
            let r = try decoder.decode(CrewSessionsReply.self, from: data)
            return [week(r.week), "crew=\(r.crewMinutes.map(String.init) ?? "none") me=\(r.myMinutes)"]
                + r.results.map { "\($0.status.rawValue) \($0.credited)" }
        case "hallReply":
            let r = try decoder.decode(CrewHallPage.self, from: data)
            return r.entries.map { "#\($0.rank) \($0.medals.gold)/\($0.medals.silver)/\($0.medals.bronze) at=\(Int($0.reachedAt.timeIntervalSince1970)) \(crew($0.crew))" }
                + ["next=\(r.next ?? "none")",
                   "mine=\(r.mine.map { "\($0.rank.map(String.init) ?? "none") \($0.medals.gold)/\($0.medals.silver)/\($0.medals.bronze)" } ?? "none")"]
        case "cancelReply":
            struct R: Decodable { let cancelled: Bool }
            return ["cancelled=\(try decoder.decode(R.self, from: data).cancelled)"]
        case "declineReply":
            struct R: Decodable { let declined: Bool }
            return ["declined=\(try decoder.decode(R.self, from: data).declined)"]
        case "leaveReply":
            struct R: Decodable { let left: Bool }
            return ["left=\(try decoder.decode(R.self, from: data).left)"]
        case "reportReply":
            struct R: Decodable { let created: Bool }
            return ["created=\(try decoder.decode(R.self, from: data).created)"]
        case "blockReply":
            struct R: Decodable { let blocked: Bool }
            return ["blocked=\(try decoder.decode(R.self, from: data).blocked)"]
        default:
            throw PartyError.invalidResponse("unknown schema \(schema)")
        }
    }

    // MARK: Formats and logic

    private static func hoursCases() -> [HoursCase] {
        [-5, 0, 5, 6, 59, 60, 61, 252, 599, 600, 659, 7_260, 9_999].map {
            HoursCase(minutes: $0, tenths: CrewFormat.tenths(minutes: $0))
        }
    }

    private static func remainingCases() -> [RemainingCase] {
        let end = Date(timeIntervalSince1970: 1_794_787_200)
        return [-30, 0, 59, 60, 119, 3_599, 3_600, 3_660, 86_399, 86_400, 90_000, 6 * 86_400 + 3_599].map { seconds in
            let value = CrewFormat.remainingValue(until: end, now: end.addingTimeInterval(-Double(seconds)))
            switch value {
            case .lessThanAMinute: return RemainingCase(seconds: seconds, form: "lessThanAMinute", values: [])
            case .minutes(let m): return RemainingCase(seconds: seconds, form: "minutes", values: [m])
            case .hoursMinutes(let h, let m): return RemainingCase(seconds: seconds, form: "hoursMinutes", values: [h, m])
            case .daysHours(let d, let h): return RemainingCase(seconds: seconds, form: "daysHours", values: [d, h])
            }
        }
    }

    private static func weekCases() -> [WeekCase] {
        // Monday 9 November 2026 at midnight UTC, a second before it, the
        // Sunday night a second before the next Monday, 31 December 2026
        // (its ISO week is 2026-W53), 1 January 2027 (still 2026-W53) and
        // 29 February 2028.
        [1_794_182_400, 1_794_182_399, 1_794_787_199, 1_798_675_200, 1_798_761_600, 1_835_395_200].map {
            WeekCase(at: $0, week: CrewWeek.containing(Date(timeIntervalSince1970: TimeInterval($0))))
        }
    }

    private static func queueCases() -> [QueueCase] {
        let t = 1_794_200_000.0
        let cases: [(String, [[Double]])] = [
            ("one session", [[t, t + 1500, 25]]),
            ("partial minutes round down", [[t, t + 1500, 24.9]]),
            ("under a minute is dropped", [[t, t + 50, 0.8]]),
            ("minutes capped to the length", [[t, t + 600, 40]]),
            ("overlapping logs merge once", [[t, t + 1500, 25], [t + 600, t + 2100, 25]]),
            ("touching logs merge", [[t, t + 1500, 25], [t + 1500, t + 3000, 25]]),
            ("apart logs stay apart", [[t + 4000, t + 5500, 25], [t, t + 1500, 25]]),
            ("a shared session inside my own", [[t, t + 3000, 50], [t + 600, t + 1800, 20]]),
            ("a break is not a session", [[t, t, 0]]),
        ]
        return cases.map { name, records in
            var queue = CrewSessionQueue()
            for record in records {
                let activity = ActivityRecord(source: .party, kind: .focusCompleted, start: Date(timeIntervalSince1970: record[0]),
                                              end: Date(timeIntervalSince1970: record[1]), quantity: record[2], unit: .minutes)
                if let session = CrewSessionQueue.session(for: activity) { queue.add(session) }
            }
            return QueueCase(name: name, records: records, pending: queue.pending.map {
                [Int($0.start.timeIntervalSince1970), Int($0.end.timeIntervalSince1970), $0.minutes]
            })
        }
    }

    private static func draftCases() -> [DraftCase] {
        let cases: [(String, String)] = [
            ("Night Owls", ""), ("   ", ""), ("  Night Owls  ", "Late study sessions."),
            (String(repeating: "a", count: 20), ""), (String(repeating: "a", count: 21), ""),
            ("Fuck Squad", ""), ("Scunthorpe Scholars", ""), ("Night Owls", String(repeating: "b", count: 121)),
            ("Night Owls", "We are a shit crew"), ("Night\nOwls", "two\nlines"),
        ]
        return cases.map { name, description in
            DraftCase(name: name, description: description,
                      problem: CrewDraftCheck.problem(name: name, description: description).map { "\($0)" })
        }
    }

    private static func inviteCases() -> [InviteCase] {
        ["tabbi://crew/W4LNUT7", "TABBI://CREW/w4ln-ut7", "https://tabbinotch.com/crew/W4LNUT7", "https://www.tabbinotch.com/crew/w4lnut7",
         "https://tabbinotch.com/join/W4LNUT7", "https://evil.example/crew/W4LNUT7", "tabbi://crew/W4LNUT", "tabbi://crew/W4LNUT0",
         "tabbi://crew/W4L%4EUT7", "Join my crew on Tabbi: https://tabbinotch.com/crew/W4LNUT7 see you there", "w4ln ut7", "hello"]
            .map { InviteCase(text: $0, code: CrewCode.findInvite(in: $0)) }
    }
}

/// The sample replies, as the server sends them.
enum CrewReplySamples {
    static let week = #""week":{"id":"2026-W46","startsAt":1794182400,"endsAt":1794787200}"#

    static let mine = """
    {"ok":true,\(week),"crew":{"id":"NGHTQWLS2K","name":"Night Owls","description":"Late study sessions.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])",
    "color":"indigo","visibility":"private","laurel":"gold","trophies":3,"golds":2,"memberCount":3,"maxMembers":20,"weekMinutes":2860,
    "createdAt":1790000000,"medals":{"gold":2,"silver":1,"bronze":0},"rank":2,"mine":true,"owner":true,"inviteCode":"W4LNUT7","hidden":false,"crewCount":38,"history":[{"week":{"id":"2026-W45","startsAt":1793577600,"endsAt":1794182400},"place":1,"minutes":11460,"medal":"gold"},{"week":{"id":"2026-W44","startsAt":1792972800,"endsAt":1793577600},"place":5,"minutes":3120,"medal":null},{"week":{"id":"2026-W43","startsAt":1792368000,"endsAt":1792972800},"place":null,"minutes":0,"medal":null}],"requests":[{"ref":"LENAREF3QW","name":"Lena","pet":{"petName":"Pickle","species":"dog","breed":"labrador","colors":[],"costume":"none","accessories":[]},"badges":[],"requestedAt":1794300000,"expiresAt":1794904800},{"ref":"QMARREF8KD","name":"Omar","pet":null,"badges":["founding"],"requestedAt":1794310000,"expiresAt":1794914800}],
    "members":[
    {"ref":"SAMREF2K7Q","name":"Sam","pet":{"petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":["scarf","graduation-cap"]},"badges":["founding"],"weekMinutes":1140,"owner":true,"me":true},
    {"ref":"MAYAREF4QR","name":"Maya","pet":{"petName":"Biscuit","species":"dog","breed":"golden-retriever","colors":[],"costume":"hoodie","accessories":["cowboy-hat"]},"badges":[],"weekMinutes":1720,"owner":false,"me":false},
    {"ref":"JQNAHREF2P","name":"Jonah","pet":null,"badges":[],"weekMinutes":0,"owner":false,"me":false}]}}
    """

    static let board = """
    {"ok":true,\(week),"top":[
    {"rank":1,"minutes":9120,"pets":[{"petName":"Clover","species":"dog","breed":"beagle","colors":["#C8915A"],"costume":"none","accessories":["flower"]},{"petName":"Pip","species":"cat","breed":"scottish-fold","colors":[],"costume":"none","accessories":["headphones"]}],"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"Anki every morning.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":3,"memberCount":14,"maxMembers":20,"weekMinutes":9120}},
    {"rank":2,"minutes":2860,"crew":{"id":"NGHTQWLS2K","name":"Night Owls","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"indigo","visibility":"private","laurel":"gold","trophies":3,"golds":2,"memberCount":3,"maxMembers":20,"weekMinutes":2860}},
    {"rank":3,"minutes":1500,"pets":[],"tiedWith":["Late Shift"],"crew":{"id":"TEACHERS22","name":"Teachers Lounge","description":"","frame":"\(CrewCatalog.frames[1])","emblem":"\(CrewCatalog.emblems[2])","color":"teal","visibility":"public","laurel":null,"trophies":0,"golds":0,"memberCount":4,"maxMembers":20,"weekMinutes":1500}},
    {"rank":3,"minutes":1500,"tiedWith":["Teachers Lounge"],"crew":{"id":"LATESHFT2K","name":"Late Shift","description":"","frame":"\(CrewCatalog.frames[1])","emblem":"\(CrewCatalog.emblems[2])","color":"rose","visibility":"public","laurel":null,"trophies":0,"golds":0,"memberCount":4,"maxMembers":20,"weekMinutes":1500}}],
    "rows":[
    {"rank":5,"minutes":840,"crew":{"id":"PQMQDQRQ2S","name":"Pomodoro Pals","description":"","frame":"\(CrewCatalog.frames[1])","emblem":"\(CrewCatalog.emblems[2])","color":"sky","visibility":"public","laurel":null,"trophies":0,"golds":0,"memberCount":4,"maxMembers":20,"weekMinutes":840}}],
    "next":"eyJyIjo1fQ","crewCount":38,"mine":{"rank":5,"minutes":840},
    "featured":{"week":{"id":"2026-W45","startsAt":1793577600,"endsAt":1794182400},"entries":[
    {"rank":1,"minutes":11460,"crew":{"id":"NGHTQWLS2K","name":"Night Owls","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"indigo","visibility":"private","laurel":"gold","trophies":3,"golds":2,"memberCount":3,"maxMembers":20,"weekMinutes":2860}},
    {"rank":2,"minutes":10020,"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":3,"memberCount":14,"maxMembers":20,"weekMinutes":9120}},
    {"rank":3,"minutes":4410,"crew":{"id":"BQQKWQRMS2","name":"Bookworms","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"amber","visibility":"public","laurel":"bronze","trophies":1,"golds":1,"memberCount":20,"maxMembers":20,"weekMinutes":3980}}]}}
    """

    static let search = """
    {"ok":true,\(week),"crews":[
    {"id":"MEDSQUAD2K","name":"Med School Squad","description":"Anki every morning.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"coral","visibility":"public","laurel":null,"trophies":5,"golds":3,"memberCount":14,"maxMembers":20,"weekMinutes":9120},
    {"id":"BQQKWQRMS2","name":"Bookworms","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"amber","visibility":"public","laurel":"bronze","trophies":1,"golds":1,"memberCount":20,"maxMembers":20,"weekMinutes":3980}]}
    """

    /// Two crews tied on golds, silvers and bronzes share a rank only when they
    /// reached the tally at the same time; here the earlier one is ahead.
    static let hall = """
    {"ok":true,"next":"eyJnIjoxfQ","mine":{"rank":1,"medals":{"gold":3,"silver":1,"bronze":0},"reachedAt":1794182400},"entries":[
    {"rank":1,"medals":{"gold":3,"silver":1,"bronze":0},"reachedAt":1794182400,"crew":{"id":"NGHTQWLS2K","name":"Night Owls","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"indigo","visibility":"private","laurel":"gold","trophies":4,"golds":3,"memberCount":5,"maxMembers":20,"weekMinutes":2860}},
    {"rank":2,"medals":{"gold":1,"silver":3,"bronze":1},"reachedAt":1793577600,"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":1,"memberCount":14,"maxMembers":20,"weekMinutes":9120}},
    {"rank":3,"medals":{"gold":1,"silver":3,"bronze":1},"reachedAt":1794182400,"crew":{"id":"BQQKWQRMS2","name":"Bookworms","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"amber","visibility":"public","laurel":null,"trophies":5,"golds":1,"memberCount":20,"maxMembers":20,"weekMinutes":3980}}]}
    """

    static let visitor = """
    {"ok":true,"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"Anki every morning.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])",
    "color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":3,"memberCount":2,"maxMembers":20,"weekMinutes":9120,
    "createdAt":1790000000,"medals":{"gold":1,"silver":3,"bronze":1},"rank":1,"mine":false,"owner":false,"inviteCode":null,"hidden":false,"crewCount":38,"history":[{"week":{"id":"2026-W45","startsAt":1793577600,"endsAt":1794182400},"place":2,"minutes":10020,"medal":"silver"}],
    "members":[
    {"ref":"AVAREF7K3R","name":"Ava","pet":{"petName":"Clover","species":"dog","breed":"beagle","colors":["#C8915A"],"costume":"none","accessories":["flower"]},"badges":[],"weekMinutes":2640,"owner":true,"me":false},
    {"ref":"NQQRREF7HV","name":"Noor","pet":{"petName":"Pip","species":"cat","breed":"scottish-fold","colors":[],"costume":"none","accessories":["headphones"]},"badges":[],"weekMinutes":2380,"owner":false,"me":false}]}}
    """

    /// A newer server: a frame, emblem, color, laurel and visibility this app does
    /// not know, a Study Level, and fields it ignores.
    static let newer = """
    {"ok":true,"crew":{"id":"NEWERCREW2","name":"From the Future","description":"","frame":"castle","emblem":"dragon","color":"ultraviolet",
    "visibility":"unlisted","laurel":"platinum","trophies":0,"golds":0,"memberCount":1,"maxMembers":30,"weekMinutes":60,"createdAt":1790000000,
    "rank":null,"mine":false,"owner":false,"inviteCode":null,"hidden":false,"streak":4,
    "members":[{"ref":"FUTUREREF2","name":"Zed","pet":{"petName":"Byte","species":"cat","breed":"hologram-cat","colors":[],"costume":"space-suit-9000","accessories":["jetpack","scarf"]},"studyLevel":12,"badges":["founding","future"],"weekMinutes":60,"owner":true,"me":false,"mood":"sunny"}]}}
    """

    static let boardNext = """
    {"ok":true,\(week),"rows":[
    {"rank":21,"minutes":60,"crew":{"id":"SLQWSTDY2K","name":"Slow and Steady","description":"","frame":"\(CrewCatalog.frames[1])","emblem":"\(CrewCatalog.emblems[2])","color":"slate","visibility":"public","laurel":null,"trophies":0,"golds":0,"memberCount":4,"maxMembers":20,"weekMinutes":60}}],
    "next":null,"crewCount":38}
    """

    /// Asking to join a public crew: the owner decides, the crew page shows what a visitor sees.
    static let requested = """
    {"ok":true,"joined":false,"requested":true,"request":{"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"Anki every morning.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":1,"memberCount":14,"maxMembers":20,"weekMinutes":9120},"requestedAt":1794300000,"expiresAt":1794904800},
    "crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"Anki every morning.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])",
    "color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":1,"memberCount":14,"maxMembers":20,"weekMinutes":9120,
    "createdAt":1790000000,"medals":{"gold":1,"silver":3,"bronze":1},"rank":1,"mine":false,"owner":false,"inviteCode":null,"hidden":false,"crewCount":38,"history":[],"members":[]}}
    """

    static let mineWaiting = """
    {"ok":true,\(week),"crew":null,"request":{"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"Anki every morning.","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])","color":"coral","visibility":"public","laurel":"silver","trophies":5,"golds":1,"memberCount":14,"maxMembers":20,"weekMinutes":9120},"requestedAt":1794300000,"expiresAt":1794904800}}
    """

    static let join = """
    {"ok":true,"joined":true,"crew":{"id":"MEDSQUAD2K","name":"Med School Squad","description":"","frame":"\(CrewCatalog.frames[0])","emblem":"\(CrewCatalog.emblems[0])",
    "color":"coral","visibility":"public","laurel":null,"trophies":0,"golds":0,"memberCount":15,"maxMembers":20,"weekMinutes":9120,"createdAt":1790000000,
    "medals":{"gold":0,"silver":0,"bronze":0},"rank":1,"mine":true,"owner":false,"inviteCode":"M3DSQD7","hidden":false,"crewCount":38,"history":[],
    "members":[{"ref":"SAMREF2K7Q","name":"Sam","pet":null,"badges":[],"weekMinutes":0,"owner":false,"me":true}]}}
    """

    static let sessions = """
    {"ok":true,\(week),"crewMinutes":2933,"myMinutes":1213,"results":[
    {"status":"credited","credited":25},{"status":"capped","credited":12},{"status":"duplicate","credited":0},
    {"status":"overlap","credited":0},{"status":"future","credited":0},{"status":"invalid","credited":0},
    {"status":"week_closed","credited":0},{"status":"no_crew","credited":0}]}
    """

    /// A newer server's session results: a status this app does not know reads as answered.
    static let newerSessions = """
    {"ok":true,\(week),"crewMinutes":null,"myMinutes":0,"results":[{"status":"something_new","credited":0}],"streak":2}
    """
}

/// Remembers every request and answers each with an empty success, which
/// the client then fails to decode: the request is what is recorded.
private final class RecordingTransport: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PartyHTTPRequest] = []

    var sent: [PartyHTTPRequest] { lock.withLock { requests } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock { requests.append(request) }
        return PartyHTTPResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
    }
}

/// A spread of crests as composed characters, and every palette, so a port
/// draws the same pixels from `crew.json`: every frame with every emblem,
/// every color, every laurel and every pip count.
struct CrewCrestsFixture: Codable, Equatable {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/fixtures/crews/crests.json")

    struct Case: Codable, Equatable {
        var frame: String
        var emblem: String
        var color: String
        var laurel: String?
        var pips: Int
        /// The canvas, one string per row, `.` for clear.
        var rows: [String]
    }

    var grid: Int
    var cases: [Case]
    /// Per crew color id, then per laurel (`none`, `gold`, `silver`, `bronze`):
    /// the hex of every character.
    var palettes: [String: [String: [String: String]]]

    static func cases() -> [(CrewCrest, CrewLaurel?, Int)] {
        let frames = CrewCatalog.frames, emblems = CrewCatalog.emblems, colors = CrewCatalog.colors.map(\.id)
        var out: [(CrewCrest, CrewLaurel?, Int)] = []
        for (f, frame) in frames.enumerated() {
            for (e, emblem) in emblems.enumerated() {
                out.append((CrewCrest(frame: frame, emblem: emblem, color: colors[(f + e) % colors.count]), nil, 0))
            }
        }
        for (index, color) in colors.enumerated() {
            let laurel = [nil, CrewLaurel.gold, .silver, .bronze][index % 4]
            out.append((CrewCrest(frame: frames[index % frames.count], emblem: emblems[(index * 5) % emblems.count], color: color),
                        laurel, index % 4))
        }
        for (index, laurel) in CrewLaurel.allCases.enumerated() {
            for frame in frames {
                out.append((CrewCrest(frame: frame, emblem: emblems[index], color: colors[index]), laurel, 3))
            }
        }
        // Ids this app has no art for draw the default crest.
        out.append((CrewCrest(frame: "castle", emblem: "dragon", color: "ultraviolet"), nil, 0))
        return out
    }

    static func current() -> CrewCrestsFixture {
        let art = CrewCrestArt.art
        func rows(_ pixels: [Character?]) -> [String] {
            (0..<art.grid).map { y in String((0..<art.grid).map { pixels[y * art.grid + $0] ?? "." }) }
        }
        let cases = cases().map { crest, laurel, pips in
            Case(frame: crest.frame, emblem: crest.emblem, color: crest.color, laurel: laurel?.rawValue, pips: pips,
                 rows: rows(CrewCrestArt.canvas(crest, laurel: laurel, pips: pips)))
        }
        var palettes: [String: [String: [String: String]]] = [:]
        for color in CrewCatalog.colors {
            var byLaurel: [String: [String: String]] = [:]
            for laurel in [nil] + CrewLaurel.allCases.map(Optional.some) {
                let palette = art.palette(color: color.id, laurel: laurel)
                byLaurel[laurel?.rawValue ?? "none"] = Dictionary(uniqueKeysWithValues: palette.map { (String($0.key), $0.value.hex) })
            }
            palettes[color.id] = byLaurel
        }
        return CrewCrestsFixture(grid: art.grid, cases: cases, palettes: palettes)
    }
}
