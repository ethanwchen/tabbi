import Foundation

/// The Study Crews routes (protocol 3, see docs/design/crews.md and
/// docs/study/backend-api.md). Like the rest of `PartyClient`, they send only
/// what the contract lists: a crew's name, description, crest and
/// visibility, my pet setting, and finished focus sessions as start, end
/// and minutes. Nothing about what was studied leaves the device.
extension PartyClient {
    /// `GET /v1/crews/mine`: my crew, or nil, and the current week.
    public func myCrew() async throws -> (crew: CrewDetail?, week: CrewWeek) {
        let reply = try await send("GET", "/v1/crews/mine", as: MineReply.self)
        return (reply.crew, reply.week)
    }

    /// `POST /v1/crews`: a new crew owned by me. `in_crew` while I am in one.
    public func createCrew(name: String, description: String, crest: CrewCrest,
                           visibility: CrewVisibility) async throws -> CrewDetail {
        let body = CrewDraft(name: name, description: description, frame: crest.frame, emblem: crest.emblem,
                             color: crest.color, visibility: visibility)
        return try await send("POST", "/v1/crews", body: body, as: CrewReply.self).crew
    }

    /// `PATCH /v1/crews/mine` (owner): nil fields keep their value.
    public func updateCrew(_ draft: CrewDraft) async throws -> CrewDetail {
        try await send("PATCH", "/v1/crews/mine", body: draft, as: CrewReply.self).crew
    }

    /// `PATCH /v1/crews/mine/me`: whether my pet shows on crew pages.
    public func setShowsPet(_ showsPet: Bool) async throws -> CrewDetail {
        try await send("PATCH", "/v1/crews/mine/me", body: ["showPet": showsPet], as: CrewReply.self).crew
    }

    /// `POST /v1/crews/join` with an invite code.
    public func joinCrew(invite: String) async throws -> CrewDetail {
        guard let code = CrewCode.invite(invite) else { throw PartyError.invalidRequest("invalid_field") }
        return try await send("POST", "/v1/crews/join", body: ["code": code], as: JoinReply.self).crew
    }

    /// `POST /v1/crews/join` with a public crew's id.
    public func joinCrew(id: String) async throws -> CrewDetail {
        guard let id = CrewCode.crewID(id) else { throw PartyError.invalidRequest("invalid_field") }
        return try await send("POST", "/v1/crews/join", body: ["crew": id], as: JoinReply.self).crew
    }

    /// `POST /v1/crews/leave`. False when I was not in one.
    @discardableResult
    public func leaveCrew() async throws -> Bool {
        try await send("POST", "/v1/crews/leave", body: [String: String](), as: LeaveReply.self).left
    }

    /// `POST /v1/crews/mine/members/{ref}/remove` (owner).
    public func removeCrewMember(ref: String) async throws -> CrewDetail {
        guard let ref = CrewCode.crewID(ref) else { throw PartyError.invalidRequest("invalid_field") }
        return try await send("POST", "/v1/crews/mine/members/\(ref)/remove", body: [String: String](),
                              as: CrewReply.self).crew
    }

    /// `GET /v1/crews?q=`: public crews, most minutes this week first.
    public func searchCrews(_ query: String) async throws -> [CrewSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var path = "/v1/crews"
        if !trimmed.isEmpty {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "q", value: String(trimmed.prefix(CrewCatalog.nameMaxLength)))]
            // `+` reads as a space in a query; send it encoded.
            path += "?" + (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        }
        return try await send("GET", path, as: SearchReply.self).crews
    }

    /// `GET /v1/crews/board`.
    public func crewBoard() async throws -> CrewBoard {
        try await send("GET", "/v1/crews/board", as: CrewBoard.self)
    }

    /// `GET /v1/crews/hall?cursor=`: a page of the all-time Hall of Fame;
    /// pass the previous page's `next` for the following one.
    public func crewHall(cursor: String? = nil) async throws -> CrewHallPage {
        var path = "/v1/crews/hall"
        if let cursor {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
            path += "?" + (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        }
        return try await send("GET", path, as: CrewHallPage.self)
    }

    /// `GET /v1/crews/{id}`: a crew page.
    public func crew(id: String) async throws -> CrewDetail {
        guard let id = CrewCode.crewID(id) else { throw PartyError.invalidRequest("invalid_field") }
        return try await send("GET", "/v1/crews/\(id)", as: CrewReply.self).crew
    }

    /// `POST /v1/crews/sessions`: finished focus sessions, at most
    /// `CrewCatalog.maxSessionsPerReport` at a time.
    public func reportCrewSessions(_ sessions: [CrewSession]) async throws -> CrewSessionsReply {
        try await send("POST", "/v1/crews/sessions", body: SessionsBody(sessions: sessions), as: CrewSessionsReply.self)
    }

    /// `POST /v1/crews/reports`: a crew, or one member of it by `ref`.
    @discardableResult
    public func reportCrew(id: String, member: String?, reason: CrewReportReason, note: String) async throws -> Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ReportBody(crew: id, member: member, reason: reason.rawValue,
                              note: trimmed.isEmpty ? nil : String(trimmed.prefix(PartyReport.noteLimit)))
        return try await send("POST", "/v1/crews/reports", body: body, as: ReportReply.self).created
    }

    /// `POST /v1/crews/block`: blocks a crew member by `ref`, the same block
    /// as everywhere in Party.
    @discardableResult
    public func blockCrewMember(crew: String, member: String) async throws -> Bool {
        try await send("POST", "/v1/crews/block", body: ["crew": crew, "member": member], as: BlockReply.self).blocked
    }
}

private struct MineReply: Decodable {
    let crew: CrewDetail?
    let week: CrewWeek
}

private struct CrewReply: Decodable {
    let crew: CrewDetail
}

private struct JoinReply: Decodable {
    let joined: Bool
    let crew: CrewDetail
}

private struct LeaveReply: Decodable {
    let left: Bool
}

private struct SearchReply: Decodable {
    let crews: [CrewSummary]
}

private struct SessionsBody: Encodable {
    let sessions: [CrewSession]
}

private struct ReportBody: Encodable {
    let crew: String
    let member: String?
    let reason: String
    let note: String?
}

private struct ReportReply: Decodable {
    let created: Bool
}

private struct BlockReply: Decodable {
    let blocked: Bool
}
