import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PartyAccount } from "../../src/core/party/partyAccount";
import { PartyClient } from "../../src/core/party/partyClient";
import { InMemoryPartyCredentialStore } from "../../src/core/party/partyCredentialStore";
import { PartyError } from "../../src/core/party/partyError";
import { inviteAppURL, parseInvite } from "../../src/core/party/partyInvite";
import { PartyInviteFlow } from "../../src/core/party/partyInviteFlow";
import { partyPetUpdate } from "../../src/core/party/partyPetAppearance";
import { PartyPresenceTracker } from "../../src/core/party/partyPresenceTracker";
import { partyDevServer } from "../../src/core/party/partyServer";
import { PartyState } from "../../src/core/party/partyState";
import { classifyTransportError, joinServerPath, parseRetryAfter, requestHeaders, type PartyTransport } from "../../src/core/party/partyTransport";
import { PetProfile } from "../../src/core/pets/petProfile";
import { PetSave } from "../../src/core/pets/petSave";
import { PetPointsLedger } from "../../src/core/pets/petUnlocks";
import { ProvidedFocus } from "../../src/core/providers/providedFocus";
import { SyncClient } from "../../src/core/sync/syncClient";
import { SyncDocument, syncTally } from "../../src/core/sync/syncDocument";
import { SyncState, runSyncRound } from "../../src/core/sync/syncRound";

/*
 * End to end against a local friends Worker, the way the Windows app talks
 * to it: two users register, become friends through an invite link, share
 * a party session, one blocks the other, the first syncs with a 409 retry,
 * and both are deleted (even after a failed step).
 *
 * Runs only with TABBI_PARTY_SERVER set to a plain-http loopback Worker
 * (`cd backend && npm ci && npx wrangler dev`, local mode, no Cloudflare
 * login); skipped otherwise, and it refuses any other address, so it can
 * never create users on a deployed server. Node's fetch is the transport
 * here only; the app uses the host's HTTP.
 *
 * Sync needs a Sign in with Apple account, which a local Worker cannot
 * verify. The suite links one through wrangler's local explorer API
 * (`/cdn-cgi/local/explorer/api`, which exists only under `wrangler dev`):
 * one row in `apple_accounts`, exactly what a sign-in writes. Everything
 * else goes through the public API.
 */

const server = partyDevServer(process.env.TABBI_PARTY_SERVER);
const TIME_ZONE = "America/New_York";
const now = () => Date.now() / 1000;

/** Node's fetch as the Party transport, for this suite only. */
function fetchTransport(base: string): PartyTransport {
  return async (request, timeout) => {
    let response: Response;
    try {
      response = await fetch(joinServerPath(base, request.path), {
        method: request.method,
        headers: requestHeaders(request),
        ...(request.body === undefined ? {} : { body: request.body }),
        signal: AbortSignal.timeout(timeout * 1000),
        redirect: "manual",
      });
    } catch (error) {
      throw classifyTransportError(error);
    }
    const retryAfter = parseRetryAfter(response.headers.get("retry-after") ?? undefined);
    const etag = response.headers.get("etag") ?? undefined;
    return {
      status: response.status,
      body: await response.text(),
      ...(retryAfter === undefined ? {} : { retryAfter }),
      ...(etag === undefined ? {} : { etag }),
    };
  };
}

/** Runs SQL on the local Worker's Durable Object through wrangler's local explorer (local dev only). */
async function localSQL(base: string, sql: string, params: unknown[]): Promise<void> {
  const response = await fetch(joinServerPath(base, "/cdn-cgi/local/explorer/api/workers/durable_objects/namespaces/tabbi-friends-Hub/query"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ durable_object_name: "hub", queries: [{ sql, params }] }),
  });
  const reply = (await response.json()) as { success?: boolean; errors?: unknown };
  if (!response.ok || reply.success !== true) throw new Error(`local explorer refused the query: ${JSON.stringify(reply.errors)}`);
}

async function failure(promise: Promise<unknown>): Promise<PartyError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof PartyError) return error;
    throw error;
  }
  throw new Error("expected a failure");
}

function studying(endsAt: number): ProvidedFocus {
  return new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "countdown", endsAt }, phaseLength: 25 * 60 });
}

describe.skipIf(server === undefined)("party end to end (local Worker)", () => {
  const base = server ?? "";
  const transport = fetchTransport(base);
  const ana = new PartyAccount({ server: base, transport, credentials: new InMemoryPartyCredentialStore() });
  const ben = new PartyAccount({ server: base, transport, credentials: new InMemoryPartyCredentialStore() });
  let anaCode = "";
  let benCode = "";
  const deleted = new Set<string>();

  beforeAll(async () => {
    expect(await new PartyClient(transport).health()).toBe(true);
  });

  afterAll(async () => {
    /* Leave nothing behind, even after a failed step. */
    for (const [name, account] of [["ana", ana], ["ben", ben]] as const) {
      if (deleted.has(name) || (await account.credentials()) === undefined) continue;
      await account.deleteAccount().catch(() => undefined);
    }
  });

  it("registers two users with their pets", async () => {
    const anaPet = new PetProfile("Mochi", "orangeTabby", { accessories: ["scarf", "graduationCap"] });
    const benPet = new PetProfile("Biscuit", "goldenRetriever", { accessories: ["roundGlasses", "cowboyHat"] });
    const anaProfile = await ana.connect({ ...partyPetUpdate(anaPet), name: "Ana" });
    const benProfile = await ben.connect({ ...partyPetUpdate(benPet), name: "Ben" });
    anaCode = anaProfile.code;
    benCode = benProfile.code;
    expect(anaCode).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    expect(benCode).not.toBe(anaCode);
    expect(anaProfile.name).toBe("Ana");
    expect(anaProfile.costume, "the hat older apps read rides in costume").toBe("graduation");
    expect(anaProfile.accessories).toEqual(["scarf", "graduation-cap"]);
    expect(benProfile.colors).toHaveLength(10);
    expect((await ben.refreshProfile()).petName).toBe("Biscuit");
  });

  it("befriends them through an invite link: Ana asks, Ben accepts", async () => {
    const invite = parseInvite(inviteAppURL({ kind: "addFriend", code: benCode }));
    expect(invite).toEqual({ kind: "addFriend", code: benCode });
    if (invite === undefined) return;

    const flow = new PartyInviteFlow(invite, true);
    const anaState = PartyState.loaded(ana.profile ?? (await ana.refreshProfile()), [], undefined);
    anaState.didFetchFriendList({ ok: true, value: await ana.perform((client) => client.friendList()) });
    flow.update(anaState, await ana.perform((client) => client.blocks()));
    expect(flow.stage.kind).toBe("confirming");
    expect(flow.begin()).toBe(true);
    const asked = await ana.perform((client) => client.addFriend(benCode));
    flow.didAsk(asked);
    expect(asked.kind).toBe("requested");
    expect(flow.title).toBe("Request sent to Ben");

    const waiting = await ben.perform((client) => client.friendList());
    expect(waiting.incoming.map((request) => request.profile.code)).toEqual([anaCode]);
    const accepted = await ben.perform((client) => client.acceptFriend(anaCode));
    expect(accepted.kind).toBe("friends");
    expect((await ana.perform((client) => client.friends())).map((friend) => friend.profile.code)).toEqual([benCode]);
    expect((await ben.perform((client) => client.friends())).map((friend) => friend.profile.code)).toEqual([anaCode]);
  });

  it("shows Ana studying to Ben after her heartbeat", async () => {
    const tracker = new PartyPresenceTracker("pomodoro");
    const at = now();
    expect(tracker.observe(studying(at + 25 * 60), at, TIME_ZONE)).toBe(true);
    const reply = await ana.perform((client) => client.heartbeat(tracker.heartbeat(at, TIME_ZONE)));
    expect(reply.presence.status).toBe("studying");
    expect(reply.nextHeartbeat).toBeGreaterThan(0);
    await ben.perform((client) => client.heartbeat({ status: "idle" }));
    const friend = (await ben.perform((client) => client.friends()))[0];
    expect(friend?.online).toBe(true);
    expect(friend?.presence?.status).toBe("studying");
    expect(friend?.presence?.method).toBe("pomodoro");
  });

  it("shares a party session: Ana hosts, Ben joins through her", async () => {
    const created = await ana.perform((client) => client.createParty());
    expect(created.host).toBe(anaCode);
    const joined = await ben.perform((client) => client.joinPartyOf(anaCode));
    expect(joined.code).toBe(created.code);
    expect(joined.members.map((member) => member.profile.code).sort()).toEqual([anaCode, benCode].sort());

    const endsAt = Math.round(now()) + 25 * 60;
    const started = await ana.perform((client) => client.startSession("pomodoro", endsAt));
    expect(started.session?.phaseEndsAt).toBe(endsAt);

    const benState = PartyState.loaded(ben.profile ?? (await ben.refreshProfile()), [], undefined);
    benState.didFetchParty({ ok: true, value: await ben.perform((client) => client.party()) });
    const session = benState.session(now());
    expect(session?.method).toBe("pomodoro");
    expect(session?.hostName).toBe("Ana");
    expect(benState.partyPets?.map((pet) => pet.id)).toEqual([benCode, anaCode]);
    expect(benState.isHost).toBe(false);

    const ended = await ana.perform((client) => client.endSession());
    expect(ended.session).toBeUndefined();
    expect((await failure(ben.perform((client) => client.startSession("pomodoro", endsAt)))).kind, "only the host").toBe("notHost");
  });

  it("blocks: the friendship and the shared party end, and Ana can't add Ben again", async () => {
    const blocked = await ben.perform((client) => client.block(anaCode));
    expect(blocked.blocked).toBe(true);
    expect(blocked.user.code).toBe(anaCode);
    expect((await ben.perform((client) => client.blocks())).map((user) => user.code)).toEqual([anaCode]);
    expect(await ben.perform((client) => client.friends())).toEqual([]);
    expect(await ana.perform((client) => client.friends())).toEqual([]);
    expect(await ben.perform((client) => client.party()), "Ben leaves the party Ana hosts").toBeUndefined();
    expect((await failure(ana.perform((client) => client.addFriend(benCode)))).kind, "a block is never revealed").toBe("unknownCode");
    expect((await failure(ben.perform((client) => client.addFriend(anaCode)))).kind).toBe("blocked");
    expect(await ben.perform((client) => client.report({ code: anaCode, reason: "spam", note: "  e2e check  " }))).toBe(true);
    expect((await ana.perform((client) => client.leaderboard())).entries.map((entry) => entry.profile.code)).toEqual([anaCode]);
  });

  it("syncs with a 409 retry and keeps both devices' progress", async () => {
    /* Anonymous users have no sync document. */
    const anaToken = (await ana.credentials())?.token;
    expect(anaToken).toBeDefined();
    if (anaToken === undefined) return;
    expect((await failure(new SyncClient(transport, anaToken).pull())).isNoSyncAccount).toBe(true);

    await localSQL(base, "INSERT INTO apple_accounts (apple_sub, code, created_at) VALUES (?, ?, ?)", [`e2e.${anaCode}`, anaCode, Math.floor(now())]);
    const client = new SyncClient(transport, anaToken);
    expect(await client.pull()).toEqual({ revision: 0, updatedAt: undefined, document: undefined });

    const pet = new PetProfile("Mochi", "orangeTabby");
    const local = { save: new PetSave(pet, new PetPointsLedger({ earned: 120, spent: 20 })), lookChangedAt: now(), studyDays: ["2026-10-14", "2026-10-15"] };
    const first = await runSyncRound(local, new SyncState({ device: "WINDOWS-A", account: anaCode }), client, now());
    expect(first.pushed).toBe(true);
    expect(first.state.revision).toBe(1);

    /* Another device (a Mac) pushes between this device's pull and push, so the push meets a 409. */
    let raced = 0;
    const racing: PartyTransport = async (request, timeout) => {
      if (request.method === "PUT" && raced === 0) {
        raced += 1;
        const mac = new SyncClient(transport, anaToken);
        const current = await mac.pull();
        const theirs = (current.document ?? SyncDocument.empty).merged(new SyncDocument({ tallies: { "MAC-B": syncTally(55) }, studyDays: ["2026-10-13"] }));
        await mac.push(theirs, current.revision);
      }
      return transport(request, timeout);
    };
    const later = { save: new PetSave(pet, new PetPointsLedger({ earned: 130, spent: 20 })), studyDays: ["2026-10-16"] };
    const second = await runSyncRound(later, first.state, new SyncClient(racing, anaToken), now());
    expect(raced).toBe(1);
    expect(second.pushed).toBe(true);
    expect(second.state.revision).toBe(3);
    expect(second.document.tallies.get("WINDOWS-A")).toEqual(syncTally(130, 20));
    expect(second.document.tallies.get("MAC-B")).toEqual(syncTally(55));
    expect(second.save.ledger.earned).toBe(185);
    expect(second.document.currentStreak("2026-10-16")).toBe(4);

    const stored = await client.pull();
    expect(stored.revision).toBe(3);
    expect(stored.document?.equals(second.document)).toBe(true);
  });

  it("deletes both users, after which their tokens are refused", async () => {
    const tokens = [(await ana.credentials())?.token, (await ben.credentials())?.token];
    await ana.deleteAccount();
    deleted.add("ana");
    await ben.deleteAccount();
    deleted.add("ben");
    for (const token of tokens) {
      expect(token).toBeDefined();
      expect((await failure(new PartyClient(transport, token).me())).kind).toBe("unauthorized");
    }
  });
});
