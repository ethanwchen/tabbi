import { describe, expect, it } from "vitest";
import { PartyError } from "../../../src/core/party/partyError";
import type { PartyHttpRequest, PartyHttpResponse, PartyTransport } from "../../../src/core/party/partyTransport";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { accessoryItem, type PetItem } from "../../../src/core/pets/petItem";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger } from "../../../src/core/pets/petUnlocks";
import { SyncClient } from "../../../src/core/sync/syncClient";
import { SyncDocument, syncTally } from "../../../src/core/sync/syncDocument";
import { SYNC_MAX_ATTEMPTS, SyncState, runSyncRound, syncSession, type SyncLocalProgress } from "../../../src/core/sync/syncRound";

// Port of SyncRoundTests.swift: the sync client's requests, and rounds
// against a server that behaves like backend/ for the sign-in and sync
// routes (one document with a revision, 409 on a stale If-Match).

const SIGN_IN_REPLY = `{"ok":true,"token":"t-new","code":"K7QW2MZD","newAccount":false,"profile":{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":10,"level":1}}`;

class FakeSyncServer {
  revision = 0;
  stored: string | undefined;
  readonly requests: PartyHttpRequest[] = [];
  /** Run before serving each pull; returns a document another device pushes. */
  beforePull: ((pull: number) => SyncDocument | undefined) | undefined;
  private pulls = 0;

  get document(): SyncDocument | undefined {
    return this.stored === undefined ? undefined : SyncDocument.decode(this.stored);
  }

  seed(document: SyncDocument): void {
    this.stored = document.encoded();
    this.revision += 1;
  }

  readonly transport: PartyTransport = async (request) => this.send(request);

  async send(request: PartyHttpRequest): Promise<PartyHttpResponse> {
    this.requests.push(request);
    const route = `${request.method} ${request.path}`;
    if (route === "POST /v1/auth/apple") return reply(SIGN_IN_REPLY);
    if (route === "POST /v1/auth/signout") return reply(`{"ok":true}`);
    if (route === "GET /v1/sync") {
      this.pulls += 1;
      const pushed = this.beforePull?.(this.pulls);
      if (pushed !== undefined) this.seed(pushed);
      const updatedAt = this.stored === undefined ? "null" : "1791504000";
      return reply(`{"ok":true,"revision":${this.revision},"updatedAt":${updatedAt},"document":${this.stored ?? "null"}}`, 200, `"${this.revision}"`);
    }
    if (route === "PUT /v1/sync") {
      const match = Number((request.headers?.["If-Match"] ?? "").replaceAll('"', ""));
      if (match !== this.revision) return reply(`{"ok":false,"error":"revision_conflict","message":"stale"}`, 409);
      const body = JSON.parse(request.body ?? "{}") as { document?: unknown };
      this.stored = JSON.stringify(body.document);
      this.revision += 1;
      return reply(`{"ok":true,"revision":${this.revision},"updatedAt":1791504060}`, 200, `"${this.revision}"`);
    }
    return reply(`{"ok":false,"error":"not_found","message":"no route"}`, 404);
  }
}

function reply(body: string, status = 200, etag?: string): PartyHttpResponse {
  return { status, body, ...(etag === undefined ? {} : { etag }) };
}

/** Lets another device push between this device's pull and push, so the push meets a 409 (once, or every time). */
function racing(server: FakeSyncServer, otherDevice: SyncDocument, every = false): { transport: PartyTransport; conflicts: () => number } {
  let raced = 0;
  return {
    conflicts: () => raced,
    transport: async (request) => {
      if (request.method === "PUT" && (every || raced === 0)) {
        raced += 1;
        server.seed((server.document ?? SyncDocument.empty).merged(otherDevice));
      }
      return server.send(request);
    },
  };
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

describe("SyncClient", () => {
  it("signs in with the Apple tokens and the current Party token", async () => {
    const server = new FakeSyncServer();
    const result = await new SyncClient(server.transport, "t-old").signInWithApple("jwt", "code");
    expect(result.credentials).toEqual({ token: "t-new", code: "K7QW2MZD" });
    expect(result.newAccount).toBe(false);
    expect(result.profile.petName).toBe("Mochi");
    const request = server.requests[server.requests.length - 1];
    expect(request?.token).toBe("t-old");
    expect(JSON.parse(request?.body ?? "")).toEqual({ identityToken: "jwt", authorizationCode: "code" });
  });

  it("sends neither token nor code when it has none", async () => {
    const server = new FakeSyncServer();
    await new SyncClient(server.transport).signInWithApple("jwt");
    const request = server.requests[server.requests.length - 1];
    expect(request?.token).toBeUndefined();
    expect(JSON.parse(request?.body ?? "")).toEqual({ identityToken: "jwt" });
  });

  it("pulls nothing before any push", async () => {
    const pull = await new SyncClient(new FakeSyncServer().transport, "t").pull();
    expect(pull).toEqual({ revision: 0, updatedAt: undefined, document: undefined });
  });

  it("pushes with the revision as If-Match and round-trips", async () => {
    const server = new FakeSyncServer();
    const client = new SyncClient(server.transport, "t");
    const document = new SyncDocument({ tallies: { a: syncTally(40) }, unlocks: ["accessory.beanie"], studyDays: ["2026-10-07"] });
    expect(await client.push(document, 0)).toBe(1);
    const sent = server.requests[server.requests.length - 1];
    expect(sent?.headers?.["If-Match"]).toBe('"0"');
    expect(Object.keys(JSON.parse(sent?.body ?? "{}") as object), "exactly the documented field").toEqual(["document"]);
    const pull = await client.pull();
    expect(pull.revision).toBe(1);
    expect(pull.document?.equals(document)).toBe(true);
    expect(pull.updatedAt).toBe(1_791_504_000);
  });

  it("refuses a document over 64 KiB without sending it", async () => {
    const server = new FakeSyncServer();
    const big = new SyncDocument({ unlocks: Array.from({ length: 4000 }, (_, index) => `accessory.item${index}`) });
    const error = await failure(new SyncClient(server.transport, "t").push(big, 0));
    expect(error.kind).toBe("invalidRequest");
    expect(error.code).toBe("body_too_large");
    expect(server.requests).toEqual([]);
  });

  it("signs out with the token and needs one", async () => {
    const server = new FakeSyncServer();
    await new SyncClient(server.transport, "t-device").signOut();
    const request = server.requests[server.requests.length - 1];
    expect(request?.method).toBe("POST");
    expect(request?.path).toBe("/v1/auth/signout");
    expect(request?.token).toBe("t-device");
    expect((await failure(new SyncClient(server.transport).signOut())).kind).toBe("unauthorized");
  });

  it("needs a token for the sync routes", async () => {
    expect((await failure(new SyncClient(new FakeSyncServer().transport).pull())).kind).toBe("unauthorized");
  });

  it("recognizes the sync errors by code", () => {
    expect(PartyError.fromServer("revision_conflict", 409, undefined).isRevisionConflict).toBe(true);
    expect(PartyError.fromServer("no_account", 403, undefined).isNoSyncAccount).toBe(true);
    expect(PartyError.fromServer("invalid_identity_token", 401, undefined).isRejectedAppleSignIn).toBe(true);
    expect(PartyError.of("unauthorized").isRevisionConflict).toBe(false);
    expect(PartyError.fromServer("apple_unavailable", 503, undefined).kind).toBe("serverUnavailable");
  });
});

describe("SyncRound", () => {
  const now = 1_800_000_000;

  function save(earned: number, options: { spent?: number; purchased?: PetItem[]; name?: string } = {}): PetSave {
    return new PetSave(
      new PetProfile(options.name ?? "Mochi", "britishShorthair"),
      new PetPointsLedger({ earned, spent: options.spent ?? 0, purchased: options.purchased ?? [] }),
    );
  }

  function run(local: SyncLocalProgress, state: SyncState, server: FakeSyncServer) {
    return runSyncRound(local, state, new SyncClient(server.transport, "t"), now);
  }

  it("pushes local progress on the first sync", async () => {
    const server = new FakeSyncServer();
    const local = { save: save(100, { spent: 30, purchased: [accessoryItem("beanie")] }), lookChangedAt: now, studyDays: ["2026-10-06", "2026-10-07"] };
    const outcome = await run(local, new SyncState({ device: "a", account: "K7QW2MZD" }), server);
    expect(outcome.pushed).toBe(true);
    expect(outcome.state.revision).toBe(1);
    expect(outcome.state.lastSyncedAt).toBe(now);
    expect(server.document?.equals(outcome.document)).toBe(true);
    expect(outcome.document.tallies.get("a")).toEqual(syncTally(100, 30));
    expect(outcome.document.currentStreak("2026-10-07")).toBe(2);
    expect(outcome.save.ledger.equals(local.save.ledger)).toBe(true);
    expect(outcome.save.profile.name).toBe("Mochi");
  });

  it("merges into an account with progress on the first sign-in", async () => {
    const server = new FakeSyncServer();
    server.seed(SyncDocument.empty.recording(save(50, { name: "Tofu" }), now, "b"));
    const local = { save: save(100, { purchased: [accessoryItem("beanie")] }), lookChangedAt: now - 3600 };
    const outcome = await run(local, new SyncState({ device: "a", account: "K7QW2MZD" }), server);
    expect(outcome.save.ledger.earned, "points from both devices add up").toBe(150);
    expect(outcome.save.ledger.owns(accessoryItem("beanie"))).toBe(true);
    expect(outcome.save.profile.name, "the newer look wins").toBe("Tofu");
    expect(server.document?.earned).toBe(150);
  });

  it("lets an unknown local look time lose to the account's look", async () => {
    const server = new FakeSyncServer();
    server.seed(SyncDocument.empty.recording(save(0, { name: "Tofu" }), now, "b"));
    const outcome = await run({ save: save(5) }, new SyncState({ device: "a" }), server);
    expect(outcome.save.profile.name).toBe("Tofu");
  });

  it("does not push when nothing is new", async () => {
    const server = new FakeSyncServer();
    const first = await run({ save: save(20), lookChangedAt: now }, new SyncState({ device: "a" }), server);
    const second = await run({ save: first.save }, first.state, server);
    expect(second.pushed).toBe(false);
    expect(second.state.revision).toBe(1);
    expect(server.requests.filter((request) => request.method === "PUT").length).toBe(1);
  });

  it("settles a fractional look time after one round trip", async () => {
    const server = new FakeSyncServer();
    const changed = now + 0.75;
    const first = await run({ save: save(1, { name: "Pip" }), lookChangedAt: changed }, new SyncState({ device: "a" }), server);
    const second = await run({ save: first.save, lookChangedAt: changed }, first.state, server);
    expect(second.pushed).toBe(false);
  });

  it("pulls, merges and retries on a 409 without losing either device", async () => {
    const server = new FakeSyncServer();
    const first = await run({ save: save(100), lookChangedAt: now }, new SyncState({ device: "a" }), server);
    server.beforePull = (pull) => (pull === 2 ? first.document.recording(save(125), undefined, "b") : undefined);
    const race = racing(server, first.document.recording(save(140), undefined, "c"));
    const outcome = await runSyncRound({ save: save(110) }, first.state, new SyncClient(race.transport, "t"), now);
    expect(outcome.pushed).toBe(true);
    expect(outcome.document.tallies.get("a")).toEqual(syncTally(110));
    expect(outcome.document.tallies.get("b")).toEqual(syncTally(25));
    expect(outcome.document.tallies.get("c")).toEqual(syncTally(40));
    expect(outcome.save.ledger.earned).toBe(175);
    expect(server.document?.equals(outcome.document)).toBe(true);
    expect(race.conflicts()).toBe(1);
  });

  it("gives up after repeated conflicts", async () => {
    const server = new FakeSyncServer();
    const race = racing(server, SyncDocument.empty, true);
    const error = await failure(runSyncRound({ save: save(10) }, new SyncState({ device: "a" }), new SyncClient(race.transport, "t"), now));
    expect(error.isRevisionConflict).toBe(true);
    expect(race.conflicts()).toBe(SYNC_MAX_ATTEMPTS);
  });

  it("counts only what this device added in later rounds", async () => {
    const server = new FakeSyncServer();
    const a = await run({ save: save(100), lookChangedAt: now }, new SyncState({ device: "a" }), server);
    const b = await run({ save: save(50) }, new SyncState({ device: "b" }), server);
    expect(b.save.ledger.earned).toBe(150);
    const next = a.save.copy();
    next.ledger = new PetPointsLedger({ earned: 110 });
    const again = await run({ save: next }, a.state, server);
    expect(again.save.ledger.earned).toBe(160);
    expect(Object.fromEntries(again.document.tallies)).toEqual({ a: syncTally(110), b: syncTally(50) });
  });

  it("folds a change made during a round on top of it", async () => {
    const server = new FakeSyncServer();
    server.seed(new SyncDocument({ tallies: { b: syncTally(50) } }));
    const base = new SyncState({ device: "a" });
    const sent = new PetSave(new PetProfile("Mochi", "britishShorthair"), new PetPointsLedger({ earned: 10 }));
    const client = new SyncClient(server.transport, "t");
    const outcome = await runSyncRound({ save: sent, lookChangedAt: now }, base, client, now);
    expect(outcome.save.ledger.earned).toBe(60);

    const current = sent.copy();
    current.ledger = new PetPointsLedger({ earned: 15 });
    const folded = outcome.folding({ save: current, lookChangedAt: now, studyDays: ["2026-10-08"] }, base);
    expect(folded.pushed).toBe(false);
    expect(folded.save.ledger.earned, "the other device's 50 plus this device's 15").toBe(65);
    expect(folded.state.revision).toBe(outcome.state.revision);
    expect(folded.document.studyDays.has("2026-10-08")).toBe(true);

    const next = await runSyncRound({ save: folded.save }, folded.state, client, now);
    expect(next.pushed).toBe(true);
    expect(server.document?.earned).toBe(65);
    expect(next.save.ledger.earned).toBe(65);
  });
});

describe("SyncState", () => {
  it("round-trips with its schema version", () => {
    const state = new SyncState({ device: "a", account: "K7QW2MZD", adopted: new SyncDocument({ tallies: { a: syncTally(3) } }), revision: 4, lastSyncedAt: 1_800_000_000 });
    const text = state.encoded();
    expect(VersionedJSON.version(text)).toBe(SyncState.schema.current);
    expect(SyncState.decode(text).equals(state)).toBe(true);
  });

  it("starts over for another account but keeps the device", () => {
    const state = new SyncState({ device: "a", account: "K7QW2MZD", adopted: new SyncDocument({ unlocks: ["x"] }), revision: 4 });
    expect(state.signedIn("K7QW2MZD").equals(state)).toBe(true);
    expect(state.signedIn("B3NX9QRT").equals(new SyncState({ device: "a", account: "B3NX9QRT" }))).toBe(true);
  });

  it("keeps what was synced when signing out, and goes on when signing back in", () => {
    const session = syncSession("  Ana  ", 1_800_000_000);
    expect(session.name).toBe("Ana");
    expect(syncSession(" ", 0).name).toBeUndefined();
    const synced = new SyncState({ device: "a", account: "K7QW2MZD", adopted: new SyncDocument({ unlocks: ["x"] }), revision: 4 }).signedIn("K7QW2MZD", session);
    expect(synced.isSignedIn).toBe(true);
    expect(SyncState.decode(synced.encoded()).equals(synced)).toBe(true);
    const out = synced.signedOut();
    expect(out.isSignedIn).toBe(false);
    expect(out.adopted.equals(synced.adopted)).toBe(true);
    expect(out.revision).toBe(4);
    expect(out.signedIn("K7QW2MZD", session).equals(synced)).toBe(true);
  });

  it("keeps only the device after the account was deleted", () => {
    const state = new SyncState({ device: "a", account: "K7QW2MZD", adopted: new SyncDocument({ unlocks: ["x"] }), revision: 4, session: syncSession(undefined, 0) });
    expect(state.forgettingAccount().equals(new SyncState({ device: "a" }))).toBe(true);
  });

  it("reads a state without a session as signed out", () => {
    const text = `{"schemaVersion":1,"device":"a","adopted":{"tallies":{},"unlocks":[],"studyDays":[],"longestStreak":0},"revision":0}`;
    expect(SyncState.decode(text).isSignedIn).toBe(false);
  });
});
