import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  CLAUDE_LIMITS_DEFAULTS_KEY,
  CLAUDE_LIMITS_SCHEMA,
  decodeLimitsRecord,
  encodeLimitsRecord,
  loadLimitsRecord,
  saveLimitsRecord,
  type ClaudeLimitsRecord,
} from "../../../src/core/claudeUsage/claudeLimits";
import {
  CLAUDE_USAGE_SCAN_INDEX_NAME,
  ClaudeUsageLogScanner,
  decodeScanIndex,
  encodeScanIndex,
  messageKey,
  PACKED_RECORD_SIZE,
  SCAN_INDEX_VERSION,
  type ClaudeUsageScanIndex,
  type TranscriptFile,
} from "../../../src/core/claudeUsage/claudeUsageLogScanner";
import { periodMessages } from "../../../src/core/claudeUsage/claudeLocalStats";
import { sha256 } from "../../../src/core/claudeUsage/sha256";
import { InMemoryDefaults } from "../../../src/core/persistence/defaults";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";

const hex = (bytes: Uint8Array) => Buffer.from(bytes).toString("hex");

describe("sha256", () => {
  it("matches the FIPS 180-4 vectors and Node's digest", () => {
    expect(hex(sha256(new Uint8Array()))).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    expect(hex(sha256(new TextEncoder().encode("abc")))).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    for (const length of [55, 56, 63, 64, 65, 1000]) {
      const bytes = new Uint8Array(length).map((_, index) => (index * 31 + 7) & 0xff);
      expect(hex(sha256(bytes))).toBe(createHash("sha256").update(bytes).digest("hex"));
    }
  });
});

describe("ClaudeLimitsRecord persistence", () => {
  const record: ClaudeLimitsRecord = {
    snapshot: { status: "allowed", fiveHour: { utilization: 0.42, resetsAt: 1_790_912_400 } },
    fetchedAt: 1_790_900_000,
  };

  it("writes the Mac's Stored shape with dates since 2001 and the version last", () => {
    expect(encodeLimitsRecord(record)).toBe(
      `{"status":"allowed","fiveHour":{"utilization":0.42,"resetsAt":812605200},"fetchedAt":812592800,"schemaVersion":1}`,
    );
    expect(CLAUDE_LIMITS_SCHEMA.current).toBe(1);
  });

  it("restores a record saved before versions existed", () => {
    /* `fetchedAt` in JSONEncoder's default date format (seconds since 2001). */
    const legacy = `{"status":"allowed","fiveHour":{"utilization":0.42},"fetchedAt":780000000}`;
    const restored = decodeLimitsRecord(legacy);
    expect(restored?.snapshot.fiveHour?.utilization).toBe(0.42);
    expect(restored?.fetchedAt).toBe(780_000_000 + 978_307_200);
    if (!restored) throw new Error("legacy record did not decode");
    const saved = encodeLimitsRecord(restored) ?? "";
    expect(VersionedJSON.version(saved)).toBe(1);
    expect(decodeLimitsRecord(saved)).toEqual(restored);
  });

  it("reads a record from a newer build leniently", () => {
    const newer = `{"schemaVersion":7,"fetchedAt":0,"sevenDay":{"utilization":1.5,"resetsAt":null,"extra":true},"opus":{}}`;
    expect(decodeLimitsRecord(newer)).toEqual({ snapshot: { sevenDay: { utilization: 1.5 } }, fetchedAt: 978_307_200 });
  });

  it("decodes damaged documents to nothing", () => {
    expect(decodeLimitsRecord(undefined)).toBeUndefined();
    expect(decodeLimitsRecord("{")).toBeUndefined();
    expect(decodeLimitsRecord("[]")).toBeUndefined();
    expect(decodeLimitsRecord(`{"schemaVersion":1}`)).toBeUndefined();
    expect(decodeLimitsRecord(`{"fetchedAt":"today"}`)).toBeUndefined();
    expect(decodeLimitsRecord(`{"fetchedAt":1,"status":3}`)).toBeUndefined();
    expect(decodeLimitsRecord(`{"fetchedAt":1,"fiveHour":{"resetsAt":1}}`)).toBeUndefined();
    expect(decodeLimitsRecord(`{"fetchedAt":1,"fiveHour":0.5}`)).toBeUndefined();
  });

  it("loads and saves under the Mac's preferences key", () => {
    const defaults = new InMemoryDefaults();
    expect(loadLimitsRecord(defaults)).toBeUndefined();
    saveLimitsRecord(defaults, record);
    expect(defaults.get(CLAUDE_LIMITS_DEFAULTS_KEY)).toBe(encodeLimitsRecord(record));
    expect(loadLimitsRecord(defaults)).toEqual(record);
    defaults.set(CLAUDE_LIMITS_DEFAULTS_KEY, "{");
    expect(loadLimitsRecord(defaults)).toBeUndefined();
    saveLimitsRecord(defaults, { snapshot: { fiveHour: { utilization: Number.NaN } }, fetchedAt: 0 });
    expect(defaults.get(CLAUDE_LIMITS_DEFAULTS_KEY)).toBeUndefined();
  });
});

describe("ClaudeUsageLogScanner index", () => {
  const sample = (): ClaudeUsageScanIndex => ({
    files: new Map([["C:/u/.claude/projects/a.jsonl", { offset: 42, identity: "18446744073709551615" }]]),
    records: new Map([
      [messageKey("msg_1"), { model: "claude-opus-4-5", timestamp: 1_790_900_000.5, usage: { input: 1, output: 2, cacheRead: 3, cacheCreation: 4 } }],
      [messageKey("msg_2"), { model: "claude-haiku-4-5", timestamp: 1_790_900_100, usage: { input: 5, output: 6, cacheRead: 0, cacheCreation: 0 } }],
      [messageKey("msg_3"), { model: "claude-opus-4-5", timestamp: 1_790_900_200, usage: { input: 0, output: 9, cacheRead: 0, cacheCreation: 0 } }],
    ]),
  });

  it("keys records by the first 128 bits of the message id's SHA-256", () => {
    expect(messageKey("msg_1")).toBe(createHash("sha256").update("msg_1").digest("hex").slice(0, 32));
  });

  it("writes the Mac's version 2 shape with packed little-endian records", () => {
    const text = encodeScanIndex(sample());
    const json = JSON.parse(text) as { version: number; files: unknown; models: string[]; records: string };
    expect(Object.keys(json)).toEqual(["version", "files", "models", "records"]);
    expect(json.version).toBe(SCAN_INDEX_VERSION);
    expect(text).toContain(`"files":{"C:\\/u\\/.claude\\/projects\\/a.jsonl":{"offset":42,"identity":18446744073709551615}}`);
    expect(json.models).toEqual(["claude-opus-4-5", "claude-haiku-4-5"]);
    const packed = Buffer.from(json.records, "base64");
    expect(packed.length).toBe(3 * PACKED_RECORD_SIZE);
    expect(PACKED_RECORD_SIZE).toBe(60);
    expect(packed.subarray(0, 16).toString("hex")).toBe(messageKey("msg_1"));
    expect(packed.readUInt32LE(16)).toBe(0);
    expect(packed.readDoubleLE(20)).toBe(1_790_900_000.5);
    expect([28, 36, 44, 52].map((at) => packed.readBigInt64LE(at))).toEqual([1n, 2n, 3n, 4n]);
    expect(packed.readUInt32LE(PACKED_RECORD_SIZE + 16)).toBe(1);
    expect(packed.readUInt32LE(2 * PACKED_RECORD_SIZE + 16)).toBe(0);
  });

  it("writes one sample exactly", () => {
    const index: ClaudeUsageScanIndex = {
      files: new Map([["a.jsonl", { offset: 7, identity: "12" }]]),
      records: new Map([["000102030405060708090a0b0c0d0e0f", { model: "m", timestamp: 0, usage: { input: 1, output: 0, cacheRead: 0, cacheCreation: 0 } }]]),
    };
    expect(encodeScanIndex(index)).toBe(
      `{"version":2,"files":{"a.jsonl":{"offset":7,"identity":12}},"models":["m"],"records":"AAECAwQFBgcICQoLDA0ODwAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}`,
    );
  });

  it("round-trips, keeping a 64-bit identity exact", () => {
    expect(decodeScanIndex(encodeScanIndex(sample()))).toEqual(sample());
  });

  it("reads nothing from a damaged or foreign index", () => {
    const small: ClaudeUsageScanIndex = { ...sample(), files: new Map([["a.jsonl", { offset: 1, identity: "5" }]]) };
    const good = JSON.parse(encodeScanIndex(small)) as Record<string, unknown>;
    expect(decodeScanIndex(JSON.stringify(good))).toEqual(small);
    const variant = (changes: Record<string, unknown>) => JSON.stringify({ ...good, ...changes });
    expect(decodeScanIndex("{not json")).toBeUndefined();
    expect(decodeScanIndex("[]")).toBeUndefined();
    expect(decodeScanIndex(variant({ version: 1 }))).toBeUndefined();
    expect(decodeScanIndex(variant({ version: undefined }))).toBeUndefined();
    expect(decodeScanIndex(variant({ schemaVersion: 2, version: undefined }))).toBeUndefined();
    expect(decodeScanIndex(variant({ files: { a: { offset: "x", identity: 1 } } }))).toBeUndefined();
    expect(decodeScanIndex(variant({ files: { a: { offset: -1, identity: 1 } } }))).toBeUndefined();
    expect(decodeScanIndex(variant({ files: { a: { offset: 1 } } }))).toBeUndefined();
    expect(decodeScanIndex(variant({ models: ["claude-opus-4-5"] }))).toBeUndefined();
    expect(decodeScanIndex(variant({ models: [1, 2] }))).toBeUndefined();
    expect(decodeScanIndex(variant({ records: "AAAA" }))).toBeUndefined();
    expect(decodeScanIndex(variant({ records: "not base64!" }))).toBeUndefined();
    expect(decodeScanIndex(variant({ unknown: true }))).toEqual(small);
    expect(decodeScanIndex(variant({ files: { a: { offset: 1, identity: 1, inode: 3 } } }))?.files.get("a")).toEqual({ offset: 1, identity: "1" });
  });
});

describe("ClaudeUsageLogScanner with a store", () => {
  const now = Date.parse("2026-10-01T15:00:00Z") / 1000;
  const line = (id: string) =>
    JSON.stringify({
      type: "assistant",
      sessionId: "s",
      timestamp: "2026-10-01T10:00:00Z",
      message: { id, model: "claude-opus-4-5", role: "assistant", content: [], usage: { input_tokens: 4, output_tokens: 6 } },
    }) + "\n";

  class CountingStore extends InMemoryDocumentStore {
    writes = 0;
    override async write(name: string, text: string): Promise<void> {
      this.writes += 1;
      await super.write(name, text);
    }
  }

  it("saves only when a scan changed something, and never without a store", async () => {
    const bytes = new TextEncoder().encode(line("m1"));
    const files: TranscriptFile[] = [{ path: "a.jsonl", size: bytes.length, identity: "9007199254740993", modified: now }];
    const read = async (_path: string, offset: number) => bytes.subarray(offset);
    const store = new CountingStore();
    const scanner = new ClaudeUsageLogScanner({ store });
    await scanner.scan(files, read, now, "UTC");
    expect(store.writes).toBe(1);
    await scanner.scan(files, read, now, "UTC");
    expect(store.writes).toBe(1);
    await scanner.scan([], read, now, "UTC");
    expect(store.writes).toBe(2);
    expect(decodeScanIndex(store.snapshot()[CLAUDE_USAGE_SCAN_INDEX_NAME] ?? "")?.files.size).toBe(0);

    const reads: number[] = [];
    const relaunched = new InMemoryDocumentStore();
    await new ClaudeUsageLogScanner({ store: relaunched }).scan(files, read, now, "UTC");
    const stats = await new ClaudeUsageLogScanner({ store: relaunched }).scan(files, async (path, offset) => (reads.push(offset), read(path, offset)), now, "UTC");
    expect(reads).toEqual([]);
    expect(periodMessages(stats.today)).toBe(1);
  });

  it("ignores a store that can't be read or written", async () => {
    const broken = new InMemoryDocumentStore();
    broken.read = async () => Promise.reject(new Error("locked"));
    broken.write = async () => Promise.reject(new Error("full"));
    const bytes = new TextEncoder().encode(line("m1"));
    const stats = await new ClaudeUsageLogScanner({ store: broken }).scan(
      [{ path: "a.jsonl", size: bytes.length, identity: "1", modified: now }],
      async () => bytes,
      now,
      "UTC",
    );
    expect(periodMessages(stats.today)).toBe(1);
  });
});
