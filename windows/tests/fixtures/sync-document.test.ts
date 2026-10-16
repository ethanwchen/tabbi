import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import { PartyError } from "../../src/core/party/partyError";
import type { PartyHttpResponse, PartyTransport } from "../../src/core/party/partyTransport";
import { itemFromID, type PetItem } from "../../src/core/pets/petItem";
import { PetProfile } from "../../src/core/pets/petProfile";
import { PetSave } from "../../src/core/pets/petSave";
import { PetPointsLedger } from "../../src/core/pets/petUnlocks";
import { SyncClient } from "../../src/core/sync/syncClient";
import { SyncDocument } from "../../src/core/sync/syncDocument";
import { SYNC_MAX_ATTEMPTS, SyncState, runSyncRound, type SyncLocalProgress } from "../../src/core/sync/syncRound";
import { loadFixture, loadRepoJson } from "../support/fixtures";

/*
 * Replays shared/fixtures/sync-document (written by SyncDocumentGoldenTests
 * on the Mac): the sync document's exact text, lenient reads, merges, and
 * whole SyncRound runs against a scripted server with 409 retries. Only the
 * inputs are read; every recorded output is compared, documents as parsed
 * JSON objects. Every document this port writes is validated against
 * shared/schemas/sync-document.v1.schema.json.
 */

type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };
type JSONObject = { [key: string]: JSONValue };

interface FixtureSave {
  profile: JSONObject;
  earned: number;
  spent: number;
  purchased: string[];
  granted: string[];
  streakFreezes: number[];
}

interface FixtureProgress {
  save: FixtureSave;
  lookChangedAt?: number;
  studyDays?: string[];
}

interface Exchange {
  request: "pull" | "push";
  status: number;
  revision?: number;
  received?: JSONObject;
  ifMatch?: number;
  sent?: JSONObject;
}

interface Outcome {
  document: JSONObject;
  pushed: boolean;
  save: FixtureSave;
  revision: number;
  lastSyncedAt: number;
}

interface SyncFixture {
  schema: string;
  version: number;
  constants: { schemaVersion: number; keptStudyDays: number; maxAttempts: number };
  wire: { name: string; text: string; document: JSONObject }[];
  decodes: { name: string; input: string; document?: JSONObject | null }[];
  merges: {
    name: string;
    input: { local: JSONObject; remote?: JSONObject | null; today: string };
    output: {
      merged: JSONObject;
      earned: number;
      spent: number;
      ledger: { earned: number; spent: number; purchased: string[]; granted: string[] };
      currentStreak: number;
    };
  }[];
  rounds: {
    name: string;
    input: {
      device: string;
      account?: string;
      adopted: JSONObject;
      revision: number;
      local: FixtureProgress;
      server: { revision: number; document?: JSONObject };
      racers: (JSONObject | null)[];
      now: number;
      duringRound?: FixtureProgress;
    };
    output: {
      exchanges: Exchange[];
      outcome?: Outcome;
      folded?: Outcome;
      error?: string;
      server: { revision: number; document?: JSONObject };
    };
  }[];
}

const fixture = loadFixture<SyncFixture>("sync-document/sync-document.json");
const validate = new Ajv2020({ allErrors: true, strict: false }).compile(loadRepoJson("shared/schemas/sync-document.v1.schema.json"));

/** The document as written, parsed, after checking it against the shared schema. */
function written(document: SyncDocument): JSONObject {
  const parsed = JSON.parse(document.encoded()) as JSONObject;
  expect(validate(parsed), JSON.stringify(validate.errors)).toBe(true);
  return parsed;
}

function read(document: JSONObject): SyncDocument {
  return SyncDocument.decode(JSON.stringify(document));
}

function items(ids: readonly string[]): PetItem[] {
  return ids.map((id) => itemFromID(id) ?? (() => { throw new Error(`unknown item ${id}`); })());
}

function saveFrom(save: FixtureSave): PetSave {
  return new PetSave(
    PetProfile.fromJSON(save.profile),
    new PetPointsLedger({ earned: save.earned, spent: save.spent, purchased: items(save.purchased), granted: items(save.granted), streakFreezes: save.streakFreezes }),
  );
}

function saveJSON(save: PetSave): FixtureSave {
  return {
    profile: save.profile.toJSON() as JSONObject,
    earned: save.ledger.earned,
    spent: save.ledger.spent,
    purchased: [...save.ledger.purchased].sort(),
    granted: [...save.ledger.granted].sort(),
    streakFreezes: [...save.ledger.streakFreezes],
  };
}

function progress(input: FixtureProgress): SyncLocalProgress {
  return {
    save: saveFrom(input.save),
    ...(input.lookChangedAt === undefined ? {} : { lookChangedAt: input.lookChangedAt }),
    ...(input.studyDays === undefined ? {} : { studyDays: input.studyDays }),
  };
}

/**
 * The scripted server: one document with a revision; `racers[n]` is merged
 * into the server's document (bumping its revision) just before this
 * device's n-th push lands. It records every exchange as the fixture does.
 */
function scriptedServer(start: { revision: number; document?: JSONObject }, racers: readonly (JSONObject | null)[]) {
  let revision = start.revision;
  let stored: JSONObject | undefined = start.document;
  let pushes = 0;
  const exchanges: Exchange[] = [];
  const reply = (body: JSONObject, status = 200): PartyHttpResponse => ({ status, body: JSON.stringify(body) });
  const transport: PartyTransport = async (request) => {
    if (request.method === "GET" && request.path === "/v1/sync") {
      exchanges.push({ request: "pull", status: 200, revision, ...(stored === undefined ? {} : { received: stored }) });
      return reply({ ok: true, revision, updatedAt: stored === undefined ? null : 1_800_000_000, document: stored ?? null });
    }
    if (request.method === "PUT" && request.path === "/v1/sync") {
      const racer = racers[pushes];
      pushes += 1;
      if (racer !== undefined && racer !== null) {
        stored = written((stored === undefined ? SyncDocument.empty : read(stored)).merged(read(racer)));
        revision += 1;
      }
      const ifMatch = Number((request.headers?.["If-Match"] ?? "").replaceAll('"', ""));
      const sent = (JSON.parse(request.body ?? "{}") as { document: JSONObject }).document;
      if (ifMatch !== revision) {
        exchanges.push({ request: "push", status: 409, ifMatch, sent });
        return reply({ ok: false, error: "revision_conflict", message: "stale" }, 409);
      }
      stored = sent;
      revision += 1;
      exchanges.push({ request: "push", status: 200, ifMatch, sent, revision });
      return reply({ ok: true, revision, updatedAt: 1_800_000_060 });
    }
    return reply({ ok: false, error: "not_found" }, 404);
  };
  return { transport, exchanges, server: () => ({ revision, ...(stored === undefined ? {} : { document: stored }) }) };
}

function outcomeJSON(outcome: { document: SyncDocument; pushed: boolean; save: PetSave; state: SyncState }): Outcome {
  expect(outcome.state.adopted.equals(outcome.document), "the state adopts the merged document").toBe(true);
  return {
    document: written(outcome.document),
    pushed: outcome.pushed,
    save: saveJSON(outcome.save),
    revision: outcome.state.revision,
    lastSyncedAt: outcome.state.lastSyncedAt ?? Number.NaN,
  };
}

describe("sync-document fixture", () => {
  it("is the recorded format", () => {
    expect(fixture.schema).toBe("tabbi.sync-document.golden");
    expect(fixture.version).toBe(1);
    expect(SyncDocument.schema.current).toBe(fixture.constants.schemaVersion);
    expect(SyncDocument.keptStudyDays).toBe(fixture.constants.keptStudyDays);
    expect(SYNC_MAX_ATTEMPTS).toBe(fixture.constants.maxAttempts);
  });

  describe("wire", () => {
    it.each(fixture.wire.map((sample) => [sample.name, sample] as const))("%s", (_, sample) => {
      const document = SyncDocument.decode(sample.text);
      expect(written(document)).toEqual(sample.document);
      expect(JSON.parse(sample.text)).toEqual(sample.document);
      expect(document.encoded().replaceAll("\\/", "/"), "the same text, slashes either way").toBe(sample.text.replaceAll("\\/", "/"));
    });
  });

  describe("decodes", () => {
    it.each(fixture.decodes.map((sample) => [sample.name, sample] as const))("%s", (_, sample) => {
      let document: SyncDocument | undefined;
      try {
        document = SyncDocument.decode(sample.input);
      } catch {
        document = undefined;
      }
      if (sample.document === null || sample.document === undefined) expect(document).toBeUndefined();
      else expect(document === undefined ? undefined : written(document)).toEqual(sample.document);
    });
  });

  describe("merges", () => {
    it.each(fixture.merges.map((sample) => [sample.name, sample] as const))("%s", (_, sample) => {
      const local = read(sample.input.local);
      const remote = sample.input.remote === null || sample.input.remote === undefined ? SyncDocument.empty : read(sample.input.remote);
      const merged = local.merged(remote);
      expect(written(merged)).toEqual(sample.output.merged);
      expect(written(remote.merged(local)), "either way round").toEqual(sample.output.merged);
      expect(written(merged.merged(remote)), "merging again changes nothing").toEqual(sample.output.merged);
      expect(merged.earned).toBe(sample.output.earned);
      expect(merged.spent).toBe(sample.output.spent);
      const ledger = merged.ledger;
      expect({
        earned: ledger.earned,
        spent: ledger.spent,
        purchased: [...ledger.purchased].sort(),
        granted: [...ledger.granted].sort(),
      }).toEqual(sample.output.ledger);
      expect(merged.currentStreak(sample.input.today)).toBe(sample.output.currentStreak);
    });
  });

  describe("rounds", () => {
    it.each(fixture.rounds.map((sample) => [sample.name, sample] as const))("%s", async (_, sample) => {
      const { input, output } = sample;
      const state = new SyncState({
        device: input.device,
        ...(input.account === undefined ? {} : { account: input.account }),
        adopted: read(input.adopted),
        revision: input.revision,
      });
      const scripted = scriptedServer(input.server, input.racers);
      const client = new SyncClient(scripted.transport, "t");
      if (output.error !== undefined) {
        let error: unknown;
        try {
          await runSyncRound(progress(input.local), state, client, input.now);
        } catch (thrown) {
          error = thrown;
        }
        expect(error instanceof PartyError && error.code).toBe(output.error);
      } else {
        const outcome = await runSyncRound(progress(input.local), state, client, input.now);
        expect(outcomeJSON(outcome)).toEqual(output.outcome);
        if (input.duringRound !== undefined) {
          expect(outcomeJSON(outcome.folding(progress(input.duringRound), state))).toEqual(output.folded);
        }
      }
      expect(scripted.exchanges).toEqual(output.exchanges);
      expect(scripted.server()).toEqual(output.server);
    });
  });
});
