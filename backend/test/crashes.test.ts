import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  ADMIN_CRASHES_PAGE, CRASHES_PER_DAY, CRASHES_PER_MIN, CRASH_RETENTION_DAYS, MAX_CRASHES_PER_DAY, MAX_CRASH_FRAMES,
  MAX_CRASH_THREADS, parseCrash,
} from "../src/crashes";
import { migrate } from "../src/hub";
import { admin, call, expectError, freshIp, hub, pinClockToMinuteStart, register } from "./helpers";

/** A report shaped like the one the app sends after a crash on the main thread. */
const REPORT = {
  version: "1.4.0 (52)",
  macos: "15.1.0",
  edition: "tabbi",
  kind: "signal",
  name: "SIGSEGV",
  threads: [
    {
      name: "com.apple.main-thread",
      crashed: true,
      frames: ["0   Tabbi   0x0000000100a1b2c3 $s5Tabbi10TodayStoreC6reloadyyF + 52", "1   AppKit   0x000000019a2b3c4d -[NSApplication run] + 476"],
    },
    { name: "", crashed: false, frames: ["0   libsystem_kernel.dylib   0x000000018f0a1b2c __workq_kernreturn + 8"] },
  ],
};
type Report = typeof REPORT;
const withField = (field: string, value: unknown): Record<string, unknown> => ({ ...REPORT, [field]: value });
const withThread = (thread: Record<string, unknown>): Record<string, unknown> => ({ ...REPORT, threads: [thread] });

const send = (body: unknown, ip = freshIp()) => call("POST", "/v1/crashes", body, undefined, ip);
const inbox = async (query = "") => (await admin("GET", "/crashes" + query)).body;
const sql = (query: string, ...params: unknown[]) =>
  runInDurableObject(hub(), (_, state) => state.storage.sql.exec(query, ...params).toArray());
/** Stored reports whose first frame carries `tag`, so tests sharing the Hub never see each other's. */
const stored = async (tag: string) =>
  (await inbox()).crashes.filter((c: { threads: Report["threads"] }) => c.threads[0].frames[0].includes(tag));
const tagged = (tag: string): Report => ({
  ...REPORT,
  threads: [{ ...REPORT.threads[0], frames: [`0   Tabbi   0x1 ${tag}`] }, REPORT.threads[1]],
});

beforeEach(pinClockToMinuteStart);
afterEach(() => vi.useRealTimers());

describe("parseCrash", () => {
  it("accepts the report the app sends", () => {
    expect(parseCrash(REPORT)).toEqual({
      appVersion: "1.4.0 (52)", macos: "15.1.0", edition: "tabbi", kind: "signal", name: "SIGSEGV", threads: REPORT.threads,
    });
    expect(parseCrash({ ...REPORT, kind: "exception", name: "NSInvalidArgumentException" }).kind).toBe("exception");
    expect(parseCrash({ ...REPORT, kind: "hang", name: "hang" }).kind).toBe("hang");
  });

  it("requires every field", () => {
    for (const field of ["version", "macos", "edition", "kind", "name", "threads"]) {
      const body: Record<string, unknown> = { ...REPORT };
      delete body[field];
      expect(() => parseCrash(body)).toThrow(`${field} is required`);
    }
  });

  it("takes the app's facts only in the shape the app cleans them to", () => {
    for (const bad of ["", "x".repeat(33), "1.4<script>", "15.1\nmore", 15]) {
      expect(() => parseCrash(withField("version", bad))).toThrow("invalid version");
      expect(() => parseCrash(withField("macos", bad))).toThrow("invalid macos");
      expect(() => parseCrash(withField("edition", bad))).toThrow("invalid edition");
    }
    expect(() => parseCrash(withField("kind", "panic"))).toThrow("invalid kind");
  });

  it("takes a signal or exception type, never free text such as an exception's reason", () => {
    for (const bad of ["", "*** -[__NSArrayM objectAtIndex:]: index 3 beyond bounds", "SIG SEGV", "x".repeat(65), 11]) {
      expect(() => parseCrash(withField("name", bad))).toThrow("invalid name");
    }
  });

  it("rejects threads that are malformed, too many, too long or carry unknown fields", () => {
    const main = REPORT.threads[0];
    expect(() => parseCrash(withField("threads", []))).toThrow("invalid threads");
    expect(() => parseCrash(withField("threads", "main"))).toThrow("invalid threads");
    expect(() => parseCrash(withField("threads", Array(MAX_CRASH_THREADS + 1).fill(REPORT.threads[1])))).toThrow("invalid threads");
    expect(parseCrash(withField("threads", Array(MAX_CRASH_THREADS).fill(REPORT.threads[1]))).threads).toHaveLength(MAX_CRASH_THREADS);
    expect(() => parseCrash(withField("threads", [main, main]))).toThrow("at most one thread crashed");
    expect(() => parseCrash(withThread({ ...main, frames: [] }))).toThrow("at least one frame");
    expect(() => parseCrash(withThread({ ...main, user: "ada" }))).toThrow("unknown field: threads.user");
    expect(() => parseCrash(withThread({ ...main, name: "x".repeat(65) }))).toThrow("invalid threads.name");
    expect(() => parseCrash(withThread({ ...main, name: "café" }))).toThrow("invalid threads.name");
    expect(() => parseCrash(withThread({ ...main, crashed: "yes" }))).toThrow("invalid threads.crashed");
    expect(() => parseCrash(withThread({ ...main, frames: Array(MAX_CRASH_FRAMES + 1).fill("0 Tabbi 0x1") }))).toThrow("invalid threads.frames");
    for (const bad of ["", "x".repeat(513), "0 Tabbi\n0x1", "0 Tabbi 0x1 café", 3]) {
      expect(() => parseCrash(withThread({ ...main, frames: [bad] }))).toThrow("invalid threads.frames");
    }
  });

  it("rejects a frame that still names a home folder", () => {
    for (const path of ["/Users/ada/Library/Tabbi.app", "/home/ada/x"]) {
      expect(() => parseCrash(withThread({ ...REPORT.threads[0], frames: [`0 Tabbi 0x1 ${path}`] })))
        .toThrow("frames must not contain home folder paths");
    }
    expect(parseCrash(withThread({ ...REPORT.threads[0], frames: ["0 Tabbi 0x1 ~/Library/x"] })).threads).toHaveLength(1);
  });
});

describe("POST /v1/crashes", () => {
  it("stores a report for the maintainer, with nothing that identifies the sender", async () => {
    const r = await send(tagged("stored"));
    expect(r.status).toBe(201);
    expect(r.body).toEqual({ ok: true });
    expect(r.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(await stored("stored")).toEqual([{
      id: expect.any(Number), createdAt: Math.floor(Date.now() / 1000), appVersion: "1.4.0 (52)", macos: "15.1.0", edition: "tabbi",
      kind: "signal", name: "SIGSEGV", threads: tagged("stored").threads,
    }]);
    const columns = await sql("SELECT name FROM pragma_table_info('crashes')");
    expect(columns.map((c) => c.name)).toEqual(["id", "app_version", "macos", "edition", "kind", "name", "threads", "created_at"]);
  });

  it("rejects invalid posts with the usual error replies", async () => {
    expectError(await send(withField("kind", "panic")), 400, "invalid_field");
    expectError(await send({ ...REPORT, email: "ada@example.org" }), 400, "unknown_field");
    expectError(await send({ ...REPORT, reason: "the document Ada.txt could not be saved" }), 400, "unknown_field");
    expectError(await send("not json"), 400, "invalid_json");
    expectError(await send(withThread({ ...REPORT.threads[0], frames: Array(MAX_CRASH_FRAMES).fill("x".repeat(512)) })), 413, "body_too_large");
    expectError(await call("GET", "/v1/crashes", undefined, undefined, freshIp()), 401, "unauthorized");
  });

  it("limits posts per IP per minute and per day", async () => {
    const ip = freshIp();
    for (let i = 0; i < CRASHES_PER_MIN; i++) expect((await send(REPORT, ip)).status).toBe(201);
    const r = await send(REPORT, ip);
    expectError(r, 429, "rate_limited");
    expect(r.headers.get("Retry-After")).toBe("60");

    const day = freshIp();
    for (let i = 0; i < CRASHES_PER_DAY; i++) {
      if (i > 0 && i % CRASHES_PER_MIN === 0) vi.setSystemTime(Date.now() + 60_000);
      expect((await send(REPORT, day)).status).toBe(201);
    }
    vi.setSystemTime(Date.now() + 60_000);
    expectError(await send(REPORT, day), 429, "rate_limited");
    expect((await send(REPORT, freshIp())).status).toBe(201);
  });

  it("refuses new reports once a day's worth from everyone is stored", async () => {
    const now = Math.floor(Date.now() / 1000);
    await sql(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < ?)
      INSERT INTO crashes (app_version, macos, edition, kind, name, threads, created_at)
      SELECT '1', '15', 'filler', 'hang', 'hang', '[]', ? FROM n`, MAX_CRASHES_PER_DAY, now);
    expectError(await send(REPORT), 503, "inbox_full");
    await sql("UPDATE crashes SET created_at = ? WHERE edition = 'filler'", now - 86_400);
    expect((await send(REPORT)).status).toBe(201);
    await sql("DELETE FROM crashes WHERE edition = 'filler'");
  });
});

describe("crash reports for the maintainer", () => {
  it("are listed newest first in pages, and can be deleted", async () => {
    const tag = `page${Date.now()}`;
    for (let i = 0; i < 3; i++) {
      vi.setSystemTime(Date.now() + 60_000);
      expect((await send(tagged(`${tag}.${i}`))).status).toBe(201);
    }
    const first = await inbox();
    expect(first.crashes.length).toBeLessThanOrEqual(ADMIN_CRASHES_PAGE);
    const mine = await stored(tag);
    expect(mine.map((c: Report) => c.threads[0].frames[0].at(-1))).toEqual(["2", "1", "0"]);
    expect((await inbox(`?before=${mine[0].id}`)).crashes[0].id).toBe(mine[1].id);
    expectError(await admin("GET", "/crashes?before=abc"), 400, "invalid_field");

    expect((await admin("DELETE", `/crashes/${mine[0].id}`)).body).toEqual({ ok: true, deleted: true });
    expect((await admin("DELETE", `/crashes/${mine[0].id}`)).body).toEqual({ ok: true, deleted: false });
    expect(await stored(`${tag}.2`)).toEqual([]);
  });

  it("are hidden from anyone without the admin token", async () => {
    const user = await register();
    expectError(await call("GET", "/v1/admin/crashes", undefined, user.token, freshIp()), 404, "not_found");
    expectError(await call("GET", "/v1/admin/crashes", undefined, undefined, freshIp()), 404, "not_found");
  });

  it("are deleted by the retention sweep", async () => {
    expect((await send(tagged("old"))).status).toBe(201);
    await sql("UPDATE crashes SET created_at = created_at - ? WHERE threads LIKE '%old%'", CRASH_RETENTION_DAYS * 86_400 + 1);
    await runDurableObjectAlarm(hub());
    expect(await stored("old")).toEqual([]);
  });
});

describe("schema step 10", () => {
  it("adds the crashes table to a database at version 9 and keeps its data", async () => {
    const user = await register({ name: "Kept" });
    await runInDurableObject(hub(), (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE crashes");
      sql.exec("UPDATE schema_version SET version = 9");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 10 }]);
      expect(sql.exec("SELECT name FROM users WHERE code = ?", user.code).toArray()).toEqual([{ name: "Kept" }]);
      expect(sql.exec("SELECT * FROM crashes").toArray()).toEqual([]);
    });
    expect((await send(REPORT)).status).toBe(201);
  });
});
