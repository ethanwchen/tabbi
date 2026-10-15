import Foundation
import XCTest
@testable import TabbiKitCore

/// Pins the Party wire contract to the golden fixture
/// `shared/fixtures/party/party.json`, which the Windows port and the
/// backend tests read too: the protocol the app speaks, the server id of
/// every outfit and accessory, the profile bodies sample pets send, and how
/// the app reads sample replies (from this server, from an older one, and
/// from a newer one with fields and items the app does not know), down to
/// the pet it draws for each profile.
///
/// `shared/schemas/party.v1.schema.json` describes the same JSON, and
/// `backend/test/compat.test.ts` checks the fixture and the live server
/// against it. Run with `TABBI_RECORD_FIXTURES=1` to rewrite the fixture
/// after an intended change.
final class PartyProtocolGoldenTests: XCTestCase {
    private var recording: Bool { ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" }

    func testPartyProtocolMatchesGoldenFixture() async throws {
        let url = PartyProtocolFixture.url
        let current = try await PartyProtocolFixture.current()
        if recording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(PartyProtocolFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.protocolVersion, current.protocolVersion)
        XCTAssertEqual(stored.outfits, current.outfits, "An outfit's server id changed")
        XCTAssertEqual(stored.accessories, current.accessories, "An accessory's server id changed")
        XCTAssertEqual(stored.updates.map(\.name), current.updates.map(\.name))
        for (old, new) in zip(stored.updates, current.updates) { XCTAssertEqual(old, new, old.name) }
        XCTAssertEqual(stored.replies.map(\.name), current.replies.map(\.name))
        for (old, new) in zip(stored.replies, current.replies) { XCTAssertEqual(old, new, old.name) }
        XCTAssertEqual(stored, current, "The Party contract no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own replies, read back: a port that reads only the
    /// replies from the file gets the recorded results and pets.
    func testStoredRepliesReadAsRecorded() async throws {
        try XCTSkipIf(recording, "Recording")
        let stored = try JSONDecoder().decode(PartyProtocolFixture.self, from: Data(contentsOf: PartyProtocolFixture.url))
        for reply in stored.replies {
            let reading = try await PartyProtocolFixture.read(reply.json, as: reply.schema)
            XCTAssertEqual(reading.summary, reply.summary, reply.name)
            XCTAssertEqual(reading.pets, reply.pets, reply.name)
        }
    }

    /// Every id the app sends is in the server's catalog, which takes every
    /// id the fixture lists.
    func testEveryWireIdIsInTheServerCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("backend/shared/catalog.json"))) as? [String: Any])
        let costumes = Set(try XCTUnwrap(catalog["costumes"] as? [String]))
        let accessories = Set(try XCTUnwrap(catalog["accessories"] as? [String]))
        for outfit in PetOutfit.allCases {
            XCTAssertTrue(costumes.contains(PartyPetAppearance.wireOutfit(outfit)), "\(outfit)")
        }
        for accessory in PetAccessory.allCases {
            XCTAssertTrue(accessories.contains(PartyPetAppearance.wireAccessory(accessory)), "\(accessory)")
        }
        XCTAssertEqual(Set(PetAccessory.allCases.map(PartyPetAppearance.wireAccessory)).count, PetAccessory.allCases.count,
                       "two accessories share a server id")
    }

    /// The shared schema names exactly the fields the app sends in a
    /// profile body and a heartbeat, and requires the profile fields the
    /// app cannot read a profile without.
    func testSchemaHasTheFieldsTheAppSendsAndNeeds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("shared/schemas/party.v1.schema.json"))) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        func properties(_ name: String) -> Set<String> { Set((defs[name]?["properties"] as? [String: Any] ?? [:]).keys) }
        func keys(_ value: some Encodable) throws -> Set<String> {
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: PartyClient.makeEncoder().encode(value)) as? [String: Any]).keys)
        }
        let body = PartyProfileUpdate(name: "A", petName: "B", species: "cat", breed: "tabby", colors: [], costume: "none",
                                      accessories: [], points: 1, level: 1)
        XCTAssertEqual(properties("profileBody"), try keys(body))
        let beat = PartyHeartbeat(status: .studying, method: "pomodoro", phaseEndsAt: Date(), sessionMinutes: 1,
                                  todayMinutes: 1, streakDays: 1, day: "2026-10-15")
        XCTAssertEqual(properties("heartbeatBody"), try keys(beat))
        let required = Set(defs["profile"]?["required"] as? [String] ?? [])
        XCTAssertEqual(required.union(["badges"]), properties("profile"))
    }

    /// Every request carries the protocol, so the server knows this app
    /// shows friend requests.
    func testEveryRequestNamesTheProtocol() async throws {
        let transport = FixtureTransport(reply: #"{"ok":true,"friends":[]}"#)
        _ = try await PartyClient(transport: transport, token: String(repeating: "ab", count: 32)).friendList()
        XCTAssertEqual(transport.sent.first?.headers[PartyClient.protocolHeader], String(PartyClient.protocolVersion))
    }
}

/// Any JSON value, so the fixture can hold request bodies and replies as
/// they go over the wire.
indirect enum PartyJSON: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PartyJSON])
    case object([String: PartyJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([PartyJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: PartyJSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    static func parse(_ data: Data) throws -> PartyJSON { try JSONDecoder().decode(PartyJSON.self, from: data) }
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// Answers every request with one recorded reply.
private final class FixtureTransport: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let reply: Data
    private var requests: [PartyHTTPRequest] = []

    init(reply: Data) { self.reply = reply }
    convenience init(reply: String) { self.init(reply: Data(reply.utf8)) }

    var sent: [PartyHTTPRequest] { lock.withLock { requests } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock { requests.append(request) }
        return PartyHTTPResponse(statusCode: 200, body: reply)
    }
}

struct PartyProtocolFixture: Codable, Equatable {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/fixtures/party/party.json")

    /// A pet as the app draws it, in the app's own ids.
    struct Pet: Codable, Equatable {
        var species: String
        var breed: String
        var outfit: String
        var accessories: [String]
        /// The effective color of each role in `colorRoles`.
        var colors: [String: String]

        init(_ pet: PetProfile) {
            species = pet.species.rawValue
            breed = pet.breed.rawValue
            outfit = pet.outfit.rawValue
            accessories = pet.accessories.map(\.rawValue)
            let palette = pet.palette
            colors = Dictionary(uniqueKeysWithValues: PartyPetAppearance.colorRoles.map { ($0.rawValue, String(palette[$0].hex.prefix(7))) })
        }
    }

    struct Update: Codable, Equatable {
        var name: String
        var pet: Pet
        /// The pet fields of `POST /v1/register` and `PATCH /v1/me`.
        var body: PartyJSON
    }

    struct Reply: Codable, Equatable {
        var name: String
        /// The reply's `$defs` name in `party.v1.schema.json`.
        var schema: String
        var json: PartyJSON
        /// What the app made of it.
        var summary: [String: PartyJSON]
        /// The pet the app draws for each profile in it, by friend code.
        var pets: [String: Pet]
    }

    var protocolVersion: Int
    var protocolHeader: String
    var colorRoles: [String]
    /// The server id of each outfit and accessory, by the app's id.
    var outfits: [String: String]
    var accessories: [String: String]
    var updates: [Update]
    var replies: [Reply]

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol", protocolHeader, colorRoles, outfits, accessories, updates, replies
    }

    static func current() async throws -> PartyProtocolFixture {
        var recorded: [Reply] = []
        for (name, schema, text) in sampleReplies {
            let json = try PartyJSON.parse(Data(text.utf8))
            let reading = try await read(json, as: schema)
            recorded.append(Reply(name: name, schema: schema, json: json, summary: reading.summary, pets: reading.pets))
        }
        return try PartyProtocolFixture(
            protocolVersion: PartyClient.protocolVersion,
            protocolHeader: PartyClient.protocolHeader,
            colorRoles: PartyPetAppearance.colorRoles.map(\.rawValue),
            outfits: Dictionary(uniqueKeysWithValues: PetOutfit.allCases.map { ($0.rawValue, PartyPetAppearance.wireOutfit($0)) }),
            accessories: Dictionary(uniqueKeysWithValues: PetAccessory.allCases.map { ($0.rawValue, PartyPetAppearance.wireAccessory($0)) }),
            updates: samplePets.map { name, pet in
                let body = try PartyClient.makeEncoder().encode(PartyPetAppearance.update(for: pet))
                return Update(name: name, pet: Pet(pet), body: try PartyJSON.parse(body))
            },
            replies: recorded
        )
    }

    /// Reads `json` the way the app reads a reply of that kind.
    static func read(_ json: PartyJSON, as schema: String) async throws -> (summary: [String: PartyJSON], pets: [String: Pet]) {
        let client = PartyClient(transport: FixtureTransport(reply: try json.data()), token: String(repeating: "ab", count: 32))
        func pets(_ profiles: [PartyProfile]) -> [String: Pet] {
            Dictionary(profiles.map { ($0.code, Pet(PartyPetAppearance.pet(for: $0))) }, uniquingKeysWith: { first, _ in first })
        }
        switch schema {
        case "friendList":
            let list = try await client.friendList()
            return ([
                "friends": .array(list.friends.map { .string($0.profile.code) }),
                "incoming": .array(list.incoming.map { .string($0.profile.code) }),
                "outgoing": .array(list.outgoing.map { .string($0.profile.code) }),
                "badges": .object(Dictionary(uniqueKeysWithValues: list.friends.map {
                    ($0.profile.code, .array($0.profile.badges.map(PartyJSON.string)))
                })),
            ], pets(list.friends.map(\.profile) + list.incoming.map(\.profile) + list.outgoing.map(\.profile)))
        case "addFriendReply":
            let addition = try await client.addFriend(code: "B3NX9QRT")
            let result: String = switch addition {
            case .friends: "friends"
            case .alreadyFriends: "alreadyFriends"
            case .requested: "requested"
            }
            return (["result": .string(result)], pets([addition.profile]))
        case "heartbeatReply":
            let reply = try await client.heartbeat(PartyHeartbeat(status: .idle))
            return ([
                "status": .string(reply.presence.status.rawValue),
                "nextHeartbeat": reply.nextHeartbeat.map { .int(Int($0)) } ?? .null,
                "incomingRequests": reply.incomingRequests.map(PartyJSON.int) ?? .null,
            ], [:])
        case "partyReply":
            guard let party = try await client.party() else { throw PartyError.invalidResponse("no party") }
            return ([
                "members": .array(party.members.map { .string($0.profile.code) }),
                "host": .string(party.host),
                "session": party.session.map { .string($0.method) } ?? .null,
            ], pets(party.members.map(\.profile)))
        default:
            throw PartyError.invalidResponse("no reader for \(schema)")
        }
    }

    // MARK: Samples

    /// Pets whose profile bodies are pinned: one per outfit, and the looks
    /// that went missing before catalog version 2 (hats with an outfit,
    /// hats the server had no id for, every slot worn, recolored items).
    static var samplePets: [(String, PetProfile)] {
        var dressed = PetProfile(name: "Nova", breed: .corgi, outfit: .dinosaurHoodie,
                                 accessories: [.snowScarf, .heartGlasses, .wizardHat, .angelWings, .sparkleTrail])
        dressed.setColor(PetColor(hex: "#3E7CB1"), for: .costumeBase)
        dressed.setColor(PetColor(hex: "#E2557A"), for: .accessoryBase)
        var tinted = PetProfile(name: "Plum", breed: .grayTabby, outfit: .scrubs, accessories: [.surgicalCap, .stethoscope])
        tinted.tintFur(PetColor(hex: "#8E6FD1"))
        return [
            ("starter cat", PetProfile.starter(.cat)),
            ("starter dog", PetProfile.starter(.dog)),
            ("scrubs, surgical cap and stethoscope, purple fur", tinted),
            ("graduation cap and scarf, no outfit", PetProfile(name: "Mochi", breed: .orangeTabby, accessories: [.scarf, .graduationCap])),
            ("cowboy hat and glasses", PetProfile(name: "Biscuit", breed: .goldenRetriever, accessories: [.roundGlasses, .cowboyHat])),
            ("every slot, recolored", dressed),
            ("eyepatch hat", PetProfile(name: "Kit", breed: .beagle, accessories: [.pirateHat])),
            ("limited and seasonal items", PetProfile(name: "Pip", breed: .shihTzu,
                                                       accessories: [.foundersPin, .summerShades, .lionDanceHat, .rainCloud])),
        ] + PetOutfit.allCases.map { ("outfit \($0.rawValue)", PetProfile(name: "Luna", breed: .siamese, outfit: $0)) }
    }

    private static let currentApp = ##"{"code":"N4ZR7HVB","name":"Noor","petName":"Pip","species":"dog","breed":"corgi","colors":["#D98C4A","#B06A33","#F2C38B","#5A3A22","#FFF1DE","#3E7CB1","#2E5E88","#FFFFFF","#E2557A","#B83D5E"],"costume":"dinosaur-hoodie","accessories":["snow-scarf","heart-glasses","wizard-hat","angel-wings","sparkle-trail"],"points":120,"level":3,"badges":["founding"]}"##
    private static let olderApp = ##"{"code":"K7QW2MZD","name":"Olive","petName":"Mochi","species":"cat","breed":"tabby","colors":["#D98C4A","#B06A33","#F2C38B","#5A3A22","#FFF1DE","#3E7CB1"],"costume":"graduation","accessories":["glasses","scarf"],"points":80,"level":2}"##
    private static let newerApp = ##"{"code":"F7TRE9XQ","name":"Fay","petName":"Zip","species":"cat","breed":"maine-coon","colors":["#334455","#AABBCC"],"costume":"space-suit","accessories":["jetpack","party-hat","wings-of-tomorrow"],"points":5,"level":1,"badges":["founding","fromTheFuture"],"aura":"glow","pronouns":"they"}"##
    private static let studying = #"{"status":"studying","method":"pomodoro","phaseEndsAt":1790000000,"sessionMinutes":5,"todayMinutes":95,"streakDays":6,"day":"2026-10-15","lastSeen":1789999100}"#

    /// Replies as this server, an older one (protocol 1) and a newer one
    /// send them.
    static let sampleReplies: [(String, String, String)] = [
        ("friend list with requests", "friendList",
         #"{"ok":true,"friends":[{"profile":\#(olderApp),"since":1789000000,"presence":\#(studying),"online":true,"party":{"code":"Q4RT8M","size":2}}],"incoming":[{"profile":\#(currentApp),"since":1789990000}],"outgoing":[{"profile":\#(newerApp),"since":1789980000}]}"#),
        ("friend list from a protocol 1 server", "friendList",
         #"{"ok":true,"friends":[{"profile":\#(olderApp),"since":1789000000,"presence":null,"online":false,"party":null}]}"#),
        ("friend list from a newer server", "friendList",
         #"{"ok":true,"friends":[{"profile":\#(newerApp),"since":1789000000,"presence":null,"online":false,"party":null,"streak":{"best":9}}],"incoming":[],"outgoing":[],"suggested":[{"code":"ZZZZZZZZ"}],"cursor":"abc"}"#),
        ("request sent", "addFriendReply", #"{"ok":true,"added":false,"status":"requested","friend":\#(currentApp)}"#),
        ("request accepted, or theirs was waiting", "addFriendReply", #"{"ok":true,"added":true,"status":"friends","friend":\#(currentApp)}"#),
        ("already friends", "addFriendReply", #"{"ok":true,"added":false,"status":"friends","friend":\#(olderApp)}"#),
        ("added on a protocol 1 server", "addFriendReply", #"{"ok":true,"added":true,"friend":\#(olderApp)}"#),
        ("heartbeat with requests waiting", "heartbeatReply",
         #"{"ok":true,"presence":\#(studying),"heartbeatSeconds":120,"incomingRequests":2}"#),
        ("heartbeat from a protocol 1 server", "heartbeatReply", #"{"ok":true,"presence":\#(studying),"heartbeatSeconds":120}"#),
        ("party of an older and a current app, and a newer one", "partyReply",
         #"{"ok":true,"party":{"code":"Q4RT8M","host":"N4ZR7HVB","createdAt":1789990000,"lastActive":1789999000,"expiresAt":1790042200,"maxMembers":8,"session":{"method":"pomodoro","phaseEndsAt":1790000000,"startedAt":1789998500},"members":[{"profile":\#(currentApp),"joinedAt":1789990000,"host":true,"presence":\#(studying),"online":true},{"profile":\#(olderApp),"joinedAt":1789991000,"host":false,"presence":null,"online":false},{"profile":\#(newerApp),"joinedAt":1789992000,"host":false,"presence":null,"online":false,"seat":3}],"theme":"night"}}"#),
    ]
}
