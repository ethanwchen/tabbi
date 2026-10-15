import { describe, expect, it } from "vitest";
import { PartyClient } from "../../../src/core/party/partyClient";
import { partyDemoBlocked } from "../../../src/core/party/partyDemo";
import { PartyError } from "../../../src/core/party/partyError";
import { PartyHeartbeatSchedule } from "../../../src/core/party/partyHeartbeatSchedule";
import { OFFLINE_HEARTBEAT, PartyCode, canJoin, isFoundingMember, isPartyFull, isPartyHost, type PartyHeartbeatReply, type PartyStatus } from "../../../src/core/party/partyModels";
import { PARTY_REPORT_REASONS, REPORT_NOTE_LIMIT, SupportContact, reportReasonTitle, reportSentNote } from "../../../src/core/party/partyModeration";
import { PARTY_PRODUCTION_URL, parsePartyServer } from "../../../src/core/party/partyServer";
import { joinServerPath } from "../../../src/core/party/partyTransport";
import { FakePartyTransport, Fixture, TOKEN, errorBody, expectPartyError, json, type FakeReply } from "./partyFakes";

function client(replies: Record<string, FakeReply>, token: string | undefined = TOKEN): [PartyClient, FakePartyTransport] {
  const transport = new FakePartyTransport(replies);
  return [new PartyClient(transport.send, token), transport];
}

describe("PartyClient profile", () => {
  it("registers without a token and returns the credentials", async () => {
    const [party, transport] = client(
      { "POST /v1/register": json(`{"ok":true,"token":"${TOKEN}","code":"K7QW2MZD","profile":${Fixture.ana}}`, 201) },
      "stale",
    );
    const registration = await party.register({ name: "Ana", petName: "Mochi", species: "cat", breed: "tabby" });
    expect(registration.token).toBe(TOKEN);
    expect(registration.code).toBe("K7QW2MZD");
    expect(registration.profile.accessories).toEqual(["glasses", "coffee-mug"]);
    expect(transport.last?.token).toBeUndefined();
    expect(transport.lastBody).toEqual({ name: "Ana", petName: "Mochi", species: "cat", breed: "tabby" });
  });

  it("sends only the changed profile fields", async () => {
    const [party, transport] = client({ "PATCH /v1/me": json(`{"ok":true,"profile":${Fixture.ana}}`) });
    const profile = await party.updateProfile({ costume: "scrubs", accessories: ["glasses"], level: 7 });
    expect(profile.costume).toBe("scrubs");
    expect(transport.last?.token).toBe(TOKEN);
    expect(transport.lastBody).toEqual({ costume: "scrubs", accessories: ["glasses"], level: 7 });
  });

  it("fails calls that need a token without one, sending nothing", async () => {
    const transport = new FakePartyTransport();
    await expectPartyError(() => new PartyClient(transport.send).me(), PartyError.of("unauthorized"));
    expect(transport.requests).toEqual([]);
  });

  it("deletes me", async () => {
    const [party, transport] = client({ "DELETE /v1/me": json('{"ok":true}') });
    await party.deleteMe();
    expect(transport.requests.map((request) => request.method)).toEqual(["DELETE"]);
  });

  it("refuses a body over 4096 bytes without sending it", async () => {
    const [party, transport] = client({ "PATCH /v1/me": json(`{"ok":true,"profile":${Fixture.ana}}`) });
    await expectPartyError(() => party.updateProfile({ name: "a".repeat(5000) }), PartyError.invalidRequest("body_too_large"));
    expect(transport.requests).toEqual([]);
  });
});

describe("PartyClient friends", () => {
  it("decodes profile, presence and party", async () => {
    const body = `{"ok":true,"friends":[{"profile":${Fixture.ana},"since":1789000000,"presence":${Fixture.studying},"online":true,"party":{"code":"Q4RT8M","size":3}},{"profile":${Fixture.ben},"since":1789000500,"presence":${Fixture.offline},"online":false,"party":null},{"profile":${Fixture.ben},"since":1789000500,"presence":null,"online":false,"party":{"code":"Q4RT8M","size":3}}]}`;
    const [party] = client({ "GET /v1/friends": json(body) });
    const friends = await party.friends();
    expect(friends.length).toBe(3);
    expect(friends[0]?.presence?.status).toBe("studying");
    expect(friends[0]?.presence?.phaseEndsAt).toBe(1_790_000_000);
    expect(friends[0]?.party).toEqual({ code: "Q4RT8M", size: 3 });
    expect(friends[0] && canJoin(friends[0])).toBe(true);
    expect(friends[1]?.presence?.status).toBe("offline");
    expect(friends[1]?.presence?.method).toBeUndefined();
    expect(friends[1] && canJoin(friends[1])).toBe(false);
    expect(friends[2]?.presence).toBeUndefined();
    expect(friends[2] && canJoin(friends[2]), "an offline friend's party is not joinable").toBe(false);
  });

  it("decodes badges and defaults them to none", async () => {
    const founder =
      '{"code":"F0UNDR2K","name":"Fay","petName":"Pip","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1,"badges":["founding","fromTheFuture"]}';
    const body = `{"ok":true,"friends":[{"profile":${founder},"since":1789000000,"presence":null,"online":false,"party":null},{"profile":${Fixture.ben},"since":1789000500,"presence":null,"online":false,"party":null}]}`;
    const [party] = client({ "GET /v1/friends": json(body) });
    const friends = await party.friends();
    expect(friends[0]?.profile.badges).toEqual(["founding", "fromTheFuture"]);
    expect(friends[0] && isFoundingMember(friends[0].profile)).toBe(true);
    expect(friends[1]?.profile.badges).toEqual([]);
    expect(friends[1] && isFoundingMember(friends[1].profile)).toBe(false);
  });

  it("normalizes a pasted code when adding a friend", async () => {
    const [party, transport] = client({ "POST /v1/friends": json(`{"ok":true,"added":true,"friend":${Fixture.ben}}`) });
    const result = await party.addFriend("  b3nx-9qrt ");
    expect(result.kind, "a server without requests makes friends at once").toBe("friends");
    expect(result.profile.petName).toBe("Biscuit");
    expect(transport.lastBody).toEqual({ code: "B3NX9QRT" });
  });

  it("reads a request and an already friend", async () => {
    const [requested] = client({ "POST /v1/friends": json(`{"ok":true,"added":false,"status":"requested","friend":${Fixture.ben}}`) });
    expect((await requested.addFriend("B3NX9QRT")).kind).toBe("requested");
    const [already] = client({ "POST /v1/friends": json(`{"ok":true,"added":false,"status":"friends","friend":${Fixture.ben}}`) });
    expect((await already.addFriend("B3NX9QRT")).kind).toBe("alreadyFriends");
  });

  it("accepts at their code and types a gone request", async () => {
    const reply = `{"ok":true,"added":true,"status":"friends","friend":${Fixture.ben}}`;
    const [party, transport] = client({ "POST /v1/friends/B3NX9QRT/accept": json(reply) });
    expect((await party.acceptFriend("b3nx-9qrt")).kind).toBe("friends");
    expect(transport.last?.method).toBe("POST");
    expect(transport.last?.body).toBeUndefined();
    const [gone] = client({ "POST /v1/friends/B3NX9QRT/accept": json(errorBody("no_request"), 404) });
    await expectPartyError(() => gone.acceptFriend("B3NX9QRT"), PartyError.of("noRequest"));
  });

  it("reads requests and their absence", async () => {
    const body = `{"ok":true,"friends":[],"incoming":[{"profile":${Fixture.ana},"since":1789000000}],"outgoing":[{"profile":${Fixture.ben},"since":1789000500}]}`;
    const [party] = client({ "GET /v1/friends": json(body) });
    const list = await party.friendList();
    expect(list.incoming.map((request) => request.profile.name)).toEqual(["Ana"]);
    expect(list.outgoing.map((request) => request.profile.code)).toEqual(["B3NX9QRT"]);
    expect(list.incoming[0]?.since).toBe(1_789_000_000);
    const [older] = client({ "GET /v1/friends": json('{"ok":true,"friends":[]}') });
    expect(await older.friendList()).toEqual({ friends: [], incoming: [], outgoing: [] });
  });

  it("types request errors", async () => {
    for (const [code, status, expected] of [
      ["pending_limit", 409, PartyError.of("pendingLimit")],
      ["request_limit", 429, PartyError.of("requestLimit")],
      ["self_friend", 400, PartyError.of("selfFriend")],
      ["unknown_code", 404, PartyError.of("unknownCode")],
      ["friend_limit", 409, PartyError.of("friendLimit")],
      ["their_friend_limit", 409, PartyError.of("theirFriendLimit")],
    ] as const) {
      const [party] = client({ "POST /v1/friends": json(errorBody(code), status) });
      await expectPartyError(() => party.addFriend("B3NX9QRT"), expected);
    }
  });

  it("rejects malformed codes without a request", async () => {
    const [party, transport] = client({});
    await expectPartyError(() => party.addFriend("B3NX9QR1"), PartyError.invalidRequest("invalid_field"));
    await expectPartyError(() => party.addFriend("short"), PartyError.invalidRequest("invalid_field"));
    expect(transport.requests).toEqual([]);
  });

  it("removes a friend by the code in the path", async () => {
    const [party, transport] = client({ "DELETE /v1/friends/B3NX9QRT": json('{"ok":true,"removed":false}') });
    expect(await party.removeFriend("b3nx9qrt")).toBe(false);
    expect(transport.last?.path).toBe("/v1/friends/B3NX9QRT");
  });
});

describe("PartyClient moderation", () => {
  it("reads the ban flag", async () => {
    const [banned] = client({ "GET /v1/me": json(`{"ok":true,"profile":${Fixture.ben},"banned":true}`) });
    const standing = await banned.standing();
    expect(standing.banned).toBe(true);
    expect(standing.profile.name).toBe("Ben");
    const [fine] = client({ "GET /v1/me": json(`{"ok":true,"profile":${Fixture.ben}}`) });
    expect((await fine.standing()).banned).toBe(false);
  });

  it("decodes the blocks list", async () => {
    const [party] = client({
      "GET /v1/blocks": json('{"ok":true,"blocks":[{"code":"B3NX9QRT","name":"Ben","petName":"Biscuit","since":1789000000}]}'),
    });
    expect(await party.blocks()).toEqual([{ code: "B3NX9QRT", name: "Ben", petName: "Biscuit", since: 1_789_000_000 }]);
  });

  it("blocks by a normalized code and reads the reply", async () => {
    const [party, transport] = client({
      "POST /v1/blocks": json('{"ok":true,"blocked":true,"block":{"code":"B3NX9QRT","name":"Ben","petName":"Biscuit"}}'),
    });
    const reply = await party.block("b3nx-9qrt");
    expect(reply.blocked).toBe(true);
    expect(reply.user.name).toBe("Ben");
    expect(reply.user.since).toBeUndefined();
    expect(transport.lastBody).toEqual({ code: "B3NX9QRT" });
  });

  it("types block errors", async () => {
    for (const [code, status, expected] of [
      ["self_block", 400, PartyError.of("selfBlock")],
      ["unknown_code", 404, PartyError.of("unknownCode")],
      ["block_limit", 409, PartyError.of("blockLimit")],
    ] as const) {
      const [party] = client({ "POST /v1/blocks": json(errorBody(code), status) });
      await expectPartyError(() => party.block("B3NX9QRT"), expected);
    }
    const [party, transport] = client({});
    await expectPartyError(() => party.block("nope"), PartyError.invalidRequest("invalid_field"));
    expect(transport.requests).toEqual([]);
  });

  it("unblocks by the code in the path", async () => {
    const [party, transport] = client({ "DELETE /v1/blocks/B3NX9QRT": json('{"ok":true,"unblocked":true}') });
    expect(await party.unblock("b3nx9qrt")).toBe(true);
    expect(transport.last?.path).toBe("/v1/blocks/B3NX9QRT");
  });

  it("reports with the reason code and a trimmed note", async () => {
    const [party, transport] = client({ "POST /v1/reports": json('{"ok":true,"created":true}', 201) });
    expect(await party.report({ code: "b3nx9qrt", reason: "inappropriate_name", note: "  rude pet name \n" })).toBe(true);
    expect(transport.lastBody).toEqual({ code: "B3NX9QRT", reason: "inappropriate_name", note: "rude pet name" });
  });

  it("leaves out an empty note and cuts a long one", async () => {
    const [party, transport] = client({ "POST /v1/reports": json('{"ok":true,"created":false}') });
    expect(await party.report({ code: "B3NX9QRT", reason: "spam", note: "   " })).toBe(false);
    expect(transport.lastBody).toEqual({ code: "B3NX9QRT", reason: "spam" });
    await party.report({ code: "B3NX9QRT", reason: "other" });
    expect(Object.keys(transport.lastBody).sort()).toEqual(["code", "reason"]);
    expect(reportSentNote({ code: "B3NX9QRT", reason: "other", note: "a".repeat(400) })?.length).toBe(REPORT_NOTE_LIMIT);
  });

  it("opens a mail to the support address", () => {
    expect(SupportContact.mailURL).toBe("mailto:support@tabbinotch.com");
    expect(SupportContact.reportLine()).toBe("Report a problem: support@tabbinotch.com");
  });

  it("types report, ban and block errors", async () => {
    for (const [code, status, expected] of [
      ["self_report", 400, PartyError.of("selfReport")],
      ["unknown_code", 404, PartyError.of("unknownCode")],
      ["report_limit", 429, PartyError.of("reportLimit")],
    ] as const) {
      const [party] = client({ "POST /v1/reports": json(errorBody(code), status) });
      await expectPartyError(() => party.report({ code: "B3NX9QRT", reason: "harassment" }), expected);
    }
    const [banned] = client({ "POST /v1/party": json(errorBody("banned"), 403) });
    await expectPartyError(() => banned.createParty(), PartyError.of("banned"));
    const [blocked] = client({ "POST /v1/friends": json(errorBody("blocked"), 409) });
    await expectPartyError(() => blocked.addFriend("B3NX9QRT"), PartyError.of("blocked"));
  });

  it("uses valid codes in the demo blocked list", () => {
    const blocked = partyDemoBlocked(1_790_000_000);
    expect(blocked.length).toBeGreaterThan(0);
    for (const user of blocked) expect(PartyCode.friendCode(user.code)).toBe(user.code);
  });

  it("matches the server's report reason codes", () => {
    expect(PARTY_REPORT_REASONS).toEqual(["inappropriate_name", "harassment", "spam", "other"]);
    expect(PARTY_REPORT_REASONS.map(reportReasonTitle)).toEqual(["Inappropriate name", "Harassment", "Spam", "Other"]);
  });
});

describe("PartyClient presence and leaderboard", () => {
  it("sends whole seconds and omits unset counters", async () => {
    const [party, transport] = client({ "POST /v1/presence": json(`{"ok":true,"presence":${Fixture.studying},"heartbeatSeconds":120}`) });
    const reply = await party.heartbeat({ status: "studying", method: "pomodoro", phaseEndsAt: 1_790_000_000.4, todayMinutes: 125, day: "2026-10-01" });
    expect(reply.nextHeartbeat).toBe(120);
    expect(reply.presence.todayMinutes).toBe(125);
    expect(transport.lastBody).toEqual({ status: "studying", method: "pomodoro", phaseEndsAt: 1_790_000_000, todayMinutes: 125, day: "2026-10-01" });
  });

  it("sends a break as `break`", async () => {
    const [party, transport] = client({ "POST /v1/presence": json(`{"ok":true,"presence":${Fixture.studying},"heartbeatSeconds":120}`) });
    await party.heartbeat({ status: "onBreak" });
    expect(transport.lastBody).toEqual({ status: "break" });
  });

  it("says stop after an offline heartbeat", async () => {
    const [party, transport] = client({ "POST /v1/presence": json(`{"ok":true,"presence":${Fixture.offline},"heartbeatSeconds":null}`) });
    const reply = await party.heartbeat(OFFLINE_HEARTBEAT);
    expect(reply.nextHeartbeat).toBeUndefined();
    expect(transport.lastBody).toEqual({ status: "offline" });
  });

  it("keeps shared leaderboard ranks", async () => {
    const body = `{"ok":true,"week":"2026-W40","from":"2026-09-28","to":"2026-10-04","entries":[{"rank":1,"minutes":840,"me":false,"profile":${Fixture.ana}},{"rank":1,"minutes":840,"me":true,"profile":${Fixture.ben}}]}`;
    const [party] = client({ "GET /v1/leaderboard": json(body) });
    const board = await party.leaderboard();
    expect(board.week).toBe("2026-W40");
    expect(board.entries.map((entry) => entry.rank)).toEqual([1, 1]);
    expect(board.entries.find((entry) => entry.me)?.profile.name).toBe("Ben");
  });

  it("lists granted item ids", async () => {
    const [party, transport] = client({ "GET /v1/grants": json('{"ok":true,"items":["accessory.backwardsCap"]}') });
    expect(await party.grants()).toEqual(["accessory.backwardsCap"]);
    expect(transport.last?.method).toBe("GET");
    expect(transport.last?.path).toBe("/v1/grants");
    const [none] = client({ "GET /v1/grants": json('{"ok":true,"items":[]}') });
    expect(await none.grants()).toEqual([]);
  });
});

describe("PartyClient parties", () => {
  it("decodes no party as undefined", async () => {
    const [party] = client({ "GET /v1/party": json('{"ok":true,"party":null}') });
    expect(await party.party()).toBeUndefined();
  });

  it("decodes members and the session", async () => {
    const [party, transport] = client({ "POST /v1/party": json(Fixture.party, 201) });
    const created = await party.createParty();
    expect(transport.last?.body, "an empty body counts as {}").toBeUndefined();
    expect(created.code).toBe("Q4RT8M");
    expect(isPartyHost(created, "K7QW2MZD")).toBe(true);
    expect(isPartyHost(created, "B3NX9QRT")).toBe(false);
    expect(created.session?.method).toBe("pomodoro");
    expect(created.session?.phaseEndsAt).toBe(1_790_000_000);
    expect(created.members.map((member) => member.profile.name)).toEqual(["Ana", "Ben"]);
    expect(created.members.map((member) => member.host)).toEqual([true, false]);
    expect(created.members[1]?.presence).toBeUndefined();
    expect(isPartyFull(created)).toBe(false);
  });

  it("joins by code or friend with exactly one field", async () => {
    const [party, transport] = client({ "POST /v1/party/join": json(Fixture.party) });
    await party.joinParty("q4rt8m");
    expect(transport.lastBody).toEqual({ code: "Q4RT8M" });
    await party.joinPartyOf("K7QW2MZD");
    expect(transport.lastBody).toEqual({ friend: "K7QW2MZD" });
    await expectPartyError(() => party.joinParty("K7QW2MZD"), PartyError.invalidRequest("invalid_field"));
  });

  it("types join errors", async () => {
    for (const [code, status, expected] of [
      ["party_not_found", 404, PartyError.of("partyNotFound")],
      ["not_friend", 403, PartyError.of("notFriend")],
      ["friend_offline", 409, PartyError.of("friendOffline")],
      ["friend_not_in_party", 404, PartyError.of("friendNotInParty")],
      ["party_full", 409, PartyError.of("partyFull")],
    ] as const) {
      const [party] = client({ "POST /v1/party/join": json(errorBody(code), status) });
      await expectPartyError(() => party.joinPartyOf("K7QW2MZD"), expected);
    }
  });

  it("leaves and controls the session", async () => {
    const [party, transport] = client({
      "POST /v1/party/leave": json('{"ok":true,"left":true}'),
      "POST /v1/party/session": json(Fixture.party),
      "DELETE /v1/party/session": json(errorBody("not_host"), 403),
    });
    expect(await party.leaveParty()).toBe(true);
    await party.startSession("pomodoro", 1_790_000_000);
    expect(transport.lastBody).toEqual({ method: "pomodoro", phaseEndsAt: 1_790_000_000 });
    await expectPartyError(() => party.endSession(), PartyError.of("notHost"));
  });
});

describe("PartyClient failures", () => {
  it("classifies common failures", async () => {
    const cases: [FakeReply, PartyError][] = [
      [json(errorBody("unauthorized"), 401), PartyError.of("unauthorized")],
      [json(errorBody("rate_limited"), 429, 17), PartyError.rateLimited(17)],
      [json(errorBody("unavailable"), 503), PartyError.of("serverUnavailable")],
      [json("<html>Bad gateway</html>", 502), PartyError.of("serverUnavailable")],
      [json(errorBody("brand_new_code"), 418), PartyError.server("brand_new_code", 418)],
      [json("<html>captive portal</html>"), PartyError.invalidResponse("not a friends-server reply")],
      [{ failure: PartyError.of("unreachable") }, PartyError.of("unreachable")],
    ];
    for (const [reply, expected] of cases) {
      const [party] = client({ "GET /v1/me": reply });
      await expectPartyError(() => party.me(), expected);
    }
  });

  it("branches on the error code, never the message", async () => {
    const [known] = client({ "POST /v1/friends": json('{"ok":false,"error":"friend_limit","message":"something entirely new"}', 409) });
    await expectPartyError(() => known.addFriend("B3NX9QRT"), PartyError.of("friendLimit"));
    const [unknown] = client({ "POST /v1/friends": json('{"ok":false,"error":"brand_new","message":"friend_limit"}', 409) });
    await expectPartyError(() => unknown.addFriend("B3NX9QRT"), PartyError.server("brand_new", 409));
  });

  it("wraps a transport failure that is not a PartyError", async () => {
    const [party] = client({ "GET /v1/me": { failure: new Error("boom") } });
    await expectPartyError(() => party.me(), PartyError.transport("Error"));
  });

  it("checks health without a token", async () => {
    const transport = new FakePartyTransport({ "GET /": json('{"ok":true,"service":"tabbi-friends","version":1}') });
    expect(await new PartyClient(transport.send).health()).toBe(true);
    expect(transport.last?.token).toBeUndefined();
  });

  it("accepts the pre-rename worker but no other service", async () => {
    for (const [service, expected] of [
      ["studynotch-friends", true],
      ["tabbi-friends", true],
      ["some-other-api", false],
    ] as const) {
      const transport = new FakePartyTransport({ "GET /": json(`{"ok":true,"service":"${service}","version":1}`) });
      expect(await new PartyClient(transport.send).health(), service).toBe(expected);
    }
  });

  it("joins a route onto the base with or without a slash", () => {
    expect(joinServerPath("http://localhost:8787/", "/v1/party")).toBe("http://localhost:8787/v1/party");
    expect(joinServerPath(PARTY_PRODUCTION_URL, "/v1/party")).toBe(`${PARTY_PRODUCTION_URL}/v1/party`);
  });
});

describe("PartyServer and PartyCode", () => {
  it("parses server addresses", () => {
    expect(parsePartyServer(" example.workers.dev/ ")).toBe("https://example.workers.dev");
    expect(parsePartyServer("http://localhost:8787")).toBe("http://localhost:8787");
    expect(parsePartyServer("http://example.com"), "plain http only for this PC").toBeUndefined();
    expect(parsePartyServer("ftp://example.com")).toBeUndefined();
    expect(parsePartyServer("")).toBeUndefined();
    expect(parsePartyServer(PARTY_PRODUCTION_URL)).toBe(PARTY_PRODUCTION_URL);
  });

  it("normalizes codes", () => {
    expect(PartyCode.friendCode("k7qw 2mzd")).toBe("K7QW2MZD");
    expect(PartyCode.partyCode("q4r-t8m")).toBe("Q4RT8M");
    expect(PartyCode.friendCode("K7QW2MZO"), "O is not in the alphabet").toBeUndefined();
    expect(PartyCode.partyCode("K7QW2MZD"), "a friend code is not a party code").toBeUndefined();
  });

  it("finds a code in pasted text", () => {
    const friend = PartyCode.friendCodeLength;
    expect(PartyCode.find("  k7qw-2mzd\n", friend)).toBe("K7QW2MZD");
    expect(PartyCode.find("Add me on Tabbi: k7qw-2mzd.", friend)).toBe("K7QW2MZD");
    expect(PartyCode.find("My code is K7QW 2MZD", friend), "a code split by a space").toBe("K7QW2MZD");
    expect(PartyCode.find("Join party Q4RT8M now", PartyCode.partyCodeLength)).toBe("Q4RT8M");
    expect(PartyCode.find("K7QW2MZD or Q4RT8MXY", friend), "two codes: no guessing").toBeUndefined();
    expect(PartyCode.find("Hello there friend", friend)).toBeUndefined();
    expect(PartyCode.find("", friend)).toBeUndefined();
  });
});

describe("PartyHeartbeatSchedule", () => {
  const reply = (status: PartyStatus, next: number | undefined): PartyHeartbeatReply => ({
    presence: { status, method: undefined, phaseEndsAt: undefined, sessionMinutes: 0, todayMinutes: 0, streakDays: 0, day: "2026-10-02", lastSeen: 0 },
    nextHeartbeat: next,
    incomingRequests: undefined,
  });

  it("follows the server's interval and stops after offline", () => {
    const schedule = new PartyHeartbeatSchedule();
    expect(schedule.delayAfterSuccess(reply("studying", 120))).toBe(120);
    expect(schedule.delayAfterSuccess(reply("idle", 300))).toBe(300);
    expect(schedule.delayAfterSuccess(reply("idle", undefined))).toBe(PartyHeartbeatSchedule.fallbackInterval);
    expect(schedule.delayAfterSuccess(reply("offline", undefined))).toBeUndefined();
  });

  it("backs off 5, 10, 20 s up to five minutes", () => {
    const schedule = new PartyHeartbeatSchedule();
    const delays = Array.from({ length: 8 }, () => schedule.delayAfterFailure(PartyError.of("unreachable")));
    expect(delays).toEqual([5, 10, 20, 40, 80, 160, 300, 300]);
    schedule.delayAfterSuccess(reply("studying", 120));
    expect(schedule.delayAfterFailure(PartyError.of("serverUnavailable")), "a success resets the backoff").toBe(5);
    expect(schedule.delayAfterFailure(PartyError.of("timedOut"))).toBe(10);
    schedule.reset();
    expect(schedule.failures).toBe(0);
  });

  it("waits for Retry-After on 429 and stops on permanent errors", () => {
    const schedule = new PartyHeartbeatSchedule();
    expect(schedule.delayAfterFailure(PartyError.rateLimited(42))).toBe(42);
    expect(schedule.delayAfterFailure(PartyError.of("unauthorized"))).toBeUndefined();
    expect(schedule.delayAfterFailure(PartyError.invalidRequest("invalid_field"))).toBeUndefined();
  });

  it("reads a 429's Retry-After through the client", async () => {
    const [party] = client({ "GET /v1/me": json('{"ok":false,"error":"rate_limited"}', 429, 42) });
    let caught: unknown;
    try {
      await party.me();
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(PartyError);
    expect(new PartyHeartbeatSchedule().delayAfterFailure(caught as PartyError)).toBe(42);
  });
});
