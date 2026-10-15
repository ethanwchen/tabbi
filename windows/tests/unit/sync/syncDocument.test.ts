import { describe, expect, it } from "vitest";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { accessoryItem, type PetItem } from "../../../src/core/pets/petItem";
import type { PetBreed } from "../../../src/core/pets/petKinds";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger } from "../../../src/core/pets/petUnlocks";
import { SyncDays, SyncDocument, SyncedPet, iso8601, parseISO8601, syncTally } from "../../../src/core/sync/syncDocument";

// Port of SyncDocumentTests.swift: the merge rules (per-device points,
// unlock and study-day unions, longest streak maximum, last-writer-wins
// look), folding a device's local save in and out, streaks and coding.
// No shared sync-document fixture exists yet, so these follow the Swift
// tests closely; the coding tests pin the Mac's JSON shape.

const early = 1_800_000_000;
const late = 1_800_000_600;

function pet(name: string, at: number, breed: PetBreed = "britishShorthair"): SyncedPet {
  return new SyncedPet(new PetProfile(name, breed), at);
}

function save(earned: number, options: { spent?: number; purchased?: PetItem[]; name?: string } = {}): PetSave {
  return new PetSave(
    new PetProfile(options.name ?? "Mochi", "britishShorthair"),
    new PetPointsLedger({ earned, spent: options.spent ?? 0, purchased: options.purchased ?? [] }),
  );
}

function same(a: SyncDocument, b: SyncDocument): boolean {
  return a.equals(b) && a.encoded() === b.encoded();
}

describe("SyncDocument merge", () => {
  const samples = [
    SyncDocument.empty,
    new SyncDocument({
      pet: pet("Mochi", early),
      tallies: { a: syncTally(120, 30) },
      unlocks: ["accessory.beanie"],
      studyDays: ["2027-01-01", "2027-01-02"],
    }),
    new SyncDocument({
      pet: pet("Biscuit", late, "goldenRetriever"),
      tallies: { a: syncTally(90, 45), b: syncTally(40) },
      unlocks: ["accessory.roundGlasses", "accessory.fromTheFuture"],
      studyDays: ["2027-01-03"],
      longestStreak: 9,
    }),
    new SyncDocument({ pet: pet("Tofu", late), tallies: { c: syncTally(5) }, studyDays: ["2026-12-31"] }),
  ];

  it("is commutative, associative and idempotent", () => {
    for (const a of samples) {
      expect(same(a.merged(a), a)).toBe(true);
      for (const b of samples) {
        expect(same(a.merged(b), b.merged(a))).toBe(true);
        for (const c of samples) expect(same(a.merged(b).merged(c), a.merged(b.merged(c)))).toBe(true);
      }
    }
  });

  it("never loses progress", () => {
    const merged = samples[1]?.merged(samples[2] ?? SyncDocument.empty) ?? SyncDocument.empty;
    expect(merged.tallies.get("a")).toEqual(syncTally(120, 45));
    expect(merged.tallies.get("b")).toEqual(syncTally(40));
    expect(merged.earned).toBe(160);
    expect(merged.spent).toBe(45);
    expect([...merged.unlocks].sort()).toEqual(["accessory.beanie", "accessory.fromTheFuture", "accessory.roundGlasses"]);
    expect([...merged.studyDays].sort()).toEqual(["2027-01-01", "2027-01-02", "2027-01-03"]);
    expect(merged.longestStreak).toBe(9);
  });

  it("lets the newest look win", () => {
    const merged = samples[1]?.merged(samples[2] ?? SyncDocument.empty);
    expect(merged?.pet?.profile.name).toBe("Biscuit");
    expect(merged?.pet?.profile.breed).toBe("goldenRetriever");
    expect(SyncDocument.empty.merged(samples[1] ?? SyncDocument.empty).pet?.profile.name).toBe("Mochi");
  });

  it("picks the same pet either way on equal timestamps", () => {
    const first = new SyncDocument({ pet: pet("Alpha", early) });
    const second = new SyncDocument({ pet: pet("Beta", early) });
    const a = first.merged(second).pet;
    const b = second.merged(first).pet;
    expect(a && b && a.equals(b)).toBe(true);
  });

  it("sums the devices' points in the ledger and skips unknown items", () => {
    const ledger = samples[2]?.ledger;
    expect(ledger?.earned).toBe(130);
    expect(ledger?.spent).toBe(45);
    expect([...(ledger?.purchased ?? [])]).toEqual([accessoryItem("roundGlasses")]);
  });
});

describe("SyncDocument local state", () => {
  const now = 1_800_000_000;

  it("merges progress from both devices on the first sign-in", () => {
    const server = SyncDocument.empty.recording(save(50, { name: "Tofu" }), now, "b");
    const local = SyncDocument.empty.recording(save(100, { spent: 30, purchased: [accessoryItem("beanie")] }), now - 60, "a");
    const adopted = local.merged(server).applied(save(100, { spent: 30, purchased: [accessoryItem("beanie")] }));
    expect(adopted.ledger.earned).toBe(150);
    expect(adopted.ledger.spent).toBe(30);
    expect(adopted.ledger.owns(accessoryItem("beanie"))).toBe(true);
    expect(adopted.profile.name, "the newer look wins").toBe("Tofu");
  });

  it("counts only what this device added on a later recording", () => {
    const base = new SyncDocument({ tallies: { a: syncTally(100), b: syncTally(50) } });
    const next = base.recording(save(160), undefined, "a");
    expect(next.tallies.get("a")).toEqual(syncTally(110));
    expect(next.tallies.get("b")).toEqual(syncTally(50));
    expect(next.earned).toBe(160);
  });

  it("adds up offline progress on two devices", () => {
    const base = new SyncDocument({ tallies: { a: syncTally(100), b: syncTally(50) } });
    const fromA = base.recording(save(170), undefined, "a");
    const fromB = base.recording(save(175), undefined, "b");
    expect(fromA.merged(fromB).earned).toBe(150 + 20 + 25);
  });

  it("syncs limited items as granted, not bought", () => {
    const local = save(40);
    local.ledger.grant(accessoryItem("flameHeadband"));
    const document = SyncDocument.empty.recording(local, undefined, "a");
    expect(document.unlocks.has(accessoryItem("flameHeadband"))).toBe(true);
    const otherDevice = document.applied(save(0));
    expect([...otherDevice.ledger.granted]).toEqual([accessoryItem("flameHeadband")]);
    expect(otherDevice.ledger.purchased.size).toBe(0);
    expect(otherDevice.ledger.spent, "a limited item costs nothing on any device").toBe(0);
  });

  it("brings a server-granted event item through unlocks", () => {
    const adopted = new SyncDocument({ unlocks: [accessoryItem("backwardsCap")] }).applied(save(10));
    expect(adopted.ledger.owns(accessoryItem("backwardsCap"))).toBe(true);
  });

  it("never takes a grant back", () => {
    const local = save(0);
    local.ledger.grant(accessoryItem("teamMedal"));
    expect(SyncDocument.empty.applied(local).ledger.owns(accessoryItem("teamMedal"))).toBe(true);
  });

  it("keeps the synced look when recording without a change", () => {
    const base = new SyncDocument({ pet: new SyncedPet(new PetProfile("Tofu", "calico"), now) });
    expect(base.recording(save(0), undefined, "a").pet?.profile.name).toBe("Tofu");
  });

  it("keeps local focus bookkeeping and restricts the look", () => {
    const local = save(0);
    local.creditedFocusCount = 4;
    local.creditedFocusSource = "focus";
    const wearing = new PetProfile("Tofu", "calico", { accessories: ["roundGlasses"] });
    const applied = new SyncDocument({ pet: new SyncedPet(wearing, now) }).applied(local);
    expect(applied.creditedFocusCount).toBe(4);
    expect(applied.creditedFocusSource).toBe("focus");
    expect(applied.profile.accessories, "glasses that are not owned come off").toEqual([]);
  });

  it("leaves a signed-out save untouched without a synced pet", () => {
    const local = save(42, { name: "Pip" });
    const applied = SyncDocument.empty.recording(local, undefined, "a").applied(local);
    expect(applied.toJSON()).toEqual(local.toJSON());
  });
});

describe("SyncDocument streaks", () => {
  it("ends the current streak today or yesterday", () => {
    const document = new SyncDocument({ studyDays: ["2027-02-27", "2027-02-28", "2027-03-01", "2027-02-20"] });
    expect(document.currentStreak("2027-03-01")).toBe(3);
    expect(document.currentStreak("2027-03-02")).toBe(3);
    expect(document.currentStreak("2027-03-03")).toBe(0);
    expect(document.longestStreak).toBe(3);
  });

  it("joins days from two devices into one streak", () => {
    const merged = new SyncDocument({ studyDays: ["2027-01-01", "2027-01-03"] }).merged(new SyncDocument({ studyDays: ["2027-01-02"] }));
    expect(merged.currentStreak("2027-01-03")).toBe(3);
    expect(merged.longestStreak).toBe(3);
  });

  it("trims old days but keeps the longest streak", () => {
    const start = SyncDays.date("2025-01-01") ?? 0;
    const days = Array.from({ length: SyncDocument.keptStudyDays + 50 }, (_, index) => SyncDays.string(start + index * 86_400));
    const document = new SyncDocument().addingStudyDays(days);
    expect(document.studyDays.size).toBe(SyncDocument.keptStudyDays);
    expect(document.longestStreak).toBe(SyncDocument.keptStudyDays + 50);
    expect(document.studyDays.has(days[days.length - 1] ?? "")).toBe(true);
  });

  it("ignores invalid days", () => {
    const document = new SyncDocument({ studyDays: ["2027-02-30", "yesterday", "2027-1-01", "2027-01-05"] });
    expect([...document.studyDays]).toEqual(["2027-01-05"]);
  });
});

describe("SyncDocument coding", () => {
  it("round-trips with a schema version", () => {
    const document = new SyncDocument({
      pet: new SyncedPet(new PetProfile("Mochi", "tuxedo", { accessories: ["scarf"] }), 1_800_000_000),
      tallies: { a: syncTally(12, 3) },
      unlocks: ["accessory.beanie", "hat.fromTheFuture"],
      studyDays: ["2027-01-01"],
    });
    const text = document.encoded();
    expect(VersionedJSON.version(text)).toBe(SyncDocument.schema.current);
    expect(SyncDocument.decode(text).equals(document)).toBe(true);
  });

  it("writes the Mac's shape: sorted keys, ISO 8601 seconds, sorted sets", () => {
    const document = new SyncDocument({
      pet: new SyncedPet(new PetProfile("Mochi", "tuxedo"), 1_800_000_000.9),
      tallies: { b: syncTally(2), a: syncTally(1) },
      unlocks: ["z", "a"],
      studyDays: ["2027-01-02", "2027-01-01"],
    });
    const parsed = JSON.parse(document.encoded()) as Record<string, unknown>;
    expect(Object.keys(parsed)).toEqual(["longestStreak", "pet", "schemaVersion", "studyDays", "tallies", "unlocks"]);
    expect((parsed.pet as Record<string, unknown>).updatedAt).toBe("2027-01-15T08:00:00Z");
    expect(parsed.unlocks).toEqual(["a", "z"]);
    expect(parsed.studyDays).toEqual(["2027-01-01", "2027-01-02"]);
    expect(parsed.longestStreak).toBe(2);
    expect(parsed.schemaVersion).toBe(1);
  });

  it("keeps the rest when a field is bad", () => {
    const json = `{"schemaVersion": 1, "pet": {"profile": {"breed": "notABreed"}}, "tallies": {"a": {"earned": 7, "spent": 0}},
      "unlocks": "oops", "studyDays": ["2027-01-01"], "somethingNew": true}`;
    const document = SyncDocument.decode(json);
    expect(document.pet).toBeUndefined();
    expect(document.earned).toBe(7);
    expect(document.unlocks.size).toBe(0);
    expect([...document.studyDays]).toEqual(["2027-01-01"]);
  });

  it("decodes an empty object as empty", () => {
    expect(SyncDocument.decode("{}").equals(SyncDocument.empty)).toBe(true);
  });

  it("reads and writes ISO 8601 dates as Foundation does", () => {
    expect(iso8601(1_800_000_000.75)).toBe("2027-01-15T08:00:00Z");
    expect(parseISO8601("2027-01-15T08:00:00Z")).toBe(1_800_000_000);
    expect(parseISO8601("2027-01-15T09:00:00+01:00")).toBe(1_800_000_000);
    expect(parseISO8601("2027-01-15T08:00:00.000Z")).toBeUndefined();
    expect(parseISO8601("yesterday")).toBeUndefined();
  });
});
