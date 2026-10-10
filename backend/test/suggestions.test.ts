import { SELF, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  ADMIN_SUGGESTIONS_PAGE, MAX_SUGGESTIONS_PER_DAY, MAX_SUGGESTION_MESSAGE, SUGGESTIONS_PER_DAY, SUGGESTIONS_PER_MIN,
  SUGGESTION_RETENTION_DAYS, THANKS_URL, cleanAppFact, cleanEmail, cleanMessage, parseSuggestion,
} from "../src/suggestions";
import { migrate } from "../src/hub";
import { BASE, admin, call, expectError, freshIp, hub, pinClockToMinuteStart, register } from "./helpers";

const IDEA = "A tab for my plants, so I remember to water them.";
/** What a suggestion without the app's facts stores for them. */
const NO_APP = { appVersion: null, macos: null, edition: null };

/** Posts the website's form the way a browser does, without following the redirect. */
function postForm(fields: Record<string, string> | string, ip = freshIp()) {
  return SELF.fetch(BASE + "/v1/suggestions", {
    method: "POST",
    redirect: "manual",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "CF-Connecting-IP": ip, Origin: "https://tabbinotch.com" },
    body: typeof fields === "string" ? fields : new URLSearchParams(fields).toString(),
  });
}

const suggest = (body: unknown, ip = freshIp()) => call("POST", "/v1/suggestions", body, undefined, ip);
const inbox = async (query = "") => (await admin("GET", "/suggestions" + query)).body;
const stored = async (message: string) =>
  (await inbox()).suggestions.filter((s: { message: string }) => s.message === message);
const sql = (query: string, ...params: unknown[]) =>
  runInDurableObject(hub(), (_, state) => state.storage.sql.exec(query, ...params).toArray());

beforeEach(pinClockToMinuteStart);
afterEach(() => vi.useRealTimers());

describe("parseSuggestion", () => {
  it("accepts the four categories of the website form", () => {
    for (const category of ["tab", "integration", "improvement", "other"]) {
      expect(parseSuggestion({ category, message: IDEA })).toEqual({ category, message: IDEA, email: null, ...NO_APP });
    }
    expect(() => parseSuggestion({ category: "new tab", message: IDEA })).toThrow("invalid category");
    expect(() => parseSuggestion({ message: IDEA })).toThrow("category is required");
  });

  it("returns null for a filled-in honeypot before validating anything else", () => {
    expect(parseSuggestion({ website: "http://spam.example", category: "nope" })).toBeNull();
    expect(parseSuggestion({ website: "", category: "tab", message: IDEA })).not.toBeNull();
  });

  it("keeps line breaks in a message and strips other control and invisible characters", () => {
    expect(cleanMessage("  First line\r\nsecond\tline\u0007​  ")).toBe("First line\nsecond line");
    expect(() => cleanMessage("too short")).toThrow("message must be 10 to 2000 characters");
    expect(() => cleanMessage("x".repeat(MAX_SUGGESTION_MESSAGE + 1))).toThrow("message must be");
    expect(cleanMessage("\u{1F431}".repeat(MAX_SUGGESTION_MESSAGE))).toHaveLength(MAX_SUGGESTION_MESSAGE * 2);
    expect(() => cleanMessage(42)).toThrow("message is required");
  });

  it("takes an optional, plausible email", () => {
    expect(cleanEmail(undefined)).toBeNull();
    expect(cleanEmail("   ")).toBeNull();
    expect(cleanEmail(" ada@example.org ")).toBe("ada@example.org");
    for (const bad of ["ada", "ada@example", "a b@example.org", "<ada@example.org>", `${"a".repeat(250)}@x.org`, 7]) {
      expect(() => cleanEmail(bad)).toThrow("invalid email");
    }
  });

  it("takes the app version, macOS version and edition the app fills in, in the shape the app cleans them to", () => {
    expect(parseSuggestion({ category: "other", message: IDEA, version: "1.4.0 (52)", macos: "15.1.0", edition: "tabbi" }))
      .toEqual({ category: "other", message: IDEA, email: null, appVersion: "1.4.0 (52)", macos: "15.1.0", edition: "tabbi" });
    expect(parseSuggestion({ category: "other", message: IDEA, version: "", macos: " ", edition: "" })).toEqual({
      category: "other", message: IDEA, email: null, ...NO_APP,
    });
    expect(cleanAppFact(" development ", "version")).toBe("development");
    expect(cleanAppFact("x".repeat(32), "version")).toHaveLength(32);
    for (const bad of ["x".repeat(33), "1.4<script>", "15.1\nmore", "a&b=c", "ada@example.org", 15]) {
      expect(() => cleanAppFact(bad, "macos")).toThrow("invalid macos");
    }
  });
});

describe("POST /v1/suggestions", () => {
  it("stores a form post and redirects the browser to the thank-you page", async () => {
    const message = `${IDEA}\nAnd a watering streak. (form)`;
    const res = await postForm({ category: "tab", message, email: "ada@example.org", website: "" });
    expect(res.status).toBe(303);
    expect(res.headers.get("Location")).toBe(THANKS_URL);
    expect(await stored(message)).toEqual([
      { id: expect.any(Number), createdAt: Math.floor(Date.now() / 1000), category: "tab", message, email: "ada@example.org", ...NO_APP },
    ]);
  });

  it("stores the app's facts the form carries when the app opened it", async () => {
    const message = `${IDEA} (from the app)`;
    const res = await postForm({ category: "other", message, email: "", website: "", version: "1.4.0 (52)", macos: "15.1.0", edition: "tabbi" });
    expect(res.status).toBe(303);
    expect((await stored(message))[0]).toMatchObject({ appVersion: "1.4.0 (52)", macos: "15.1.0", edition: "tabbi", email: null });
    const page = await postForm({ category: "other", message, version: "1.4.0", macos: "15.1.0; rm -rf" });
    expect(page.status).toBe(400);
    expect(await page.text()).toContain("invalid macos");
  });

  it("stores a JSON post sent with CORS and answers JSON", async () => {
    const preflight = await SELF.fetch(BASE + "/v1/suggestions", {
      method: "OPTIONS",
      headers: { Origin: "https://tabbinotch.com", "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type" },
    });
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(preflight.headers.get("Access-Control-Allow-Headers")).toContain("Content-Type");

    const message = `${IDEA} (json)`;
    const r = await suggest({ category: "integration", message });
    expect(r.status).toBe(201);
    expect(r.body).toEqual({ ok: true });
    expect(r.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect((await stored(message))[0]).toMatchObject({ category: "integration", email: null });
  });

  it("accepts a filled-in honeypot like a real post but stores nothing", async () => {
    const message = `${IDEA} (bot)`;
    const res = await postForm({ category: "tab", message, website: "http://spam.example" });
    expect(res.status).toBe(303);
    expect(res.headers.get("Location")).toBe(THANKS_URL);
    expect((await suggest({ category: "tab", message, website: "x" })).status).toBe(201);
    expect(await stored(message)).toEqual([]);
  });

  it("rejects invalid JSON posts with the usual error replies", async () => {
    expectError(await suggest({ category: "tab", message: "short" }), 400, "invalid_field");
    expectError(await suggest({ category: "wish", message: IDEA }), 400, "invalid_field");
    expectError(await suggest({ category: "tab", message: IDEA, email: "nope" }), 400, "invalid_field");
    expectError(await suggest({ category: "tab", message: IDEA, name: "Ada" }), 400, "unknown_field");
    expectError(await suggest("not json"), 400, "invalid_json");
    expectError(await suggest({ category: "tab", message: "x".repeat(40_000) }), 413, "body_too_large");
    const r = await SELF.fetch(BASE + "/v1/suggestions", {
      method: "POST", headers: { "Content-Type": "text/plain", "CF-Connecting-IP": freshIp() }, body: IDEA,
    });
    expect(r.status).toBe(415);
  });

  it("answers a form post it cannot accept with a page that links back to the form", async () => {
    for (const body of [{ category: "tab", message: "short" } as Record<string, string>, { category: "tab", message: IDEA, extra: "1" }, "category=tab&category=other&message=" + IDEA]) {
      const res = await postForm(body);
      expect(res.status).toBe(400);
      expect(res.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
      const page = await res.text();
      expect(page).toContain("Suggestion not sent");
      expect(page).toContain('href="https://tabbinotch.com/suggest"');
    }
    const res = await postForm({ category: "tab", message: "<script>alert(1)</script>", extra: "<b>" });
    expect(await res.text()).not.toContain("<b>");
  });

  it("limits posts per IP per minute and per day", async () => {
    const ip = freshIp();
    for (let i = 0; i < SUGGESTIONS_PER_MIN; i++) expect((await suggest({ category: "other", message: `${IDEA} ${i}` }, ip)).status).toBe(201);
    const r = await suggest({ category: "other", message: IDEA }, ip);
    expectError(r, 429, "rate_limited");
    expect(r.headers.get("Retry-After")).toBe("60");
    const page = await postForm({ category: "other", message: IDEA }, ip);
    expect(page.status).toBe(429);
    expect(await page.text()).toContain("wait a minute");

    const day = freshIp();
    for (let i = 0; i < SUGGESTIONS_PER_DAY; i++) {
      if (i > 0 && i % SUGGESTIONS_PER_MIN === 0) vi.setSystemTime(Date.now() + 60_000);
      expect((await suggest({ category: "other", message: `${IDEA} day ${i}` }, day)).status).toBe(201);
    }
    vi.setSystemTime(Date.now() + 60_000);
    expectError(await suggest({ category: "other", message: IDEA }, day), 429, "rate_limited");
    expect((await suggest({ category: "other", message: IDEA }, freshIp())).status).toBe(201);
  });

  it("refuses new suggestions once the inbox holds a day's worth from everyone", async () => {
    const now = Math.floor(Date.now() / 1000);
    await sql(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < ?)
      INSERT INTO suggestions (category, message, email, created_at) SELECT 'other', 'filler', NULL, ? FROM n`, MAX_SUGGESTIONS_PER_DAY, now);
    expectError(await suggest({ category: "tab", message: IDEA }), 503, "inbox_full");
    expect(await (await postForm({ category: "tab", message: IDEA })).text()).toContain("inbox is full");
    await sql("UPDATE suggestions SET created_at = ? WHERE message = 'filler'", now - 86_400);
    expect((await suggest({ category: "tab", message: IDEA })).status).toBe(201);
    await sql("DELETE FROM suggestions WHERE message = 'filler'");
  });
});

describe("suggestions for the maintainer", () => {
  it("are listed newest first in pages, and can be deleted", async () => {
    const tag = `page ${Date.now()}`;
    for (let i = 0; i < 3; i++) {
      vi.setSystemTime(Date.now() + 60_000);
      await suggest({ category: "improvement", message: `${IDEA} ${tag} ${i}` });
    }
    const first = await inbox();
    expect(first.suggestions.length).toBeLessThanOrEqual(ADMIN_SUGGESTIONS_PAGE);
    const mine = first.suggestions.filter((s: { message: string }) => s.message.includes(tag));
    expect(mine.map((s: { message: string }) => s.message.at(-1))).toEqual(["2", "1", "0"]);
    const older = await inbox(`?before=${mine[0].id}`);
    expect(older.suggestions[0].id).toBe(mine[1].id);
    expectError(await admin("GET", "/suggestions?before=abc"), 400, "invalid_field");

    expect((await admin("DELETE", `/suggestions/${mine[0].id}`)).body).toEqual({ ok: true, deleted: true });
    expect((await admin("DELETE", `/suggestions/${mine[0].id}`)).body).toEqual({ ok: true, deleted: false });
    expect((await stored(mine[0].message))).toEqual([]);
  });

  it("are hidden from anyone without the admin token", async () => {
    const user = await register();
    expectError(await call("GET", "/v1/admin/suggestions", undefined, user.token, freshIp()), 404, "not_found");
    expectError(await call("GET", "/v1/admin/suggestions", undefined, undefined, freshIp()), 404, "not_found");
  });

  it("are deleted by the retention sweep after a year", async () => {
    const message = `${IDEA} (old)`;
    await suggest({ category: "other", message });
    await sql("UPDATE suggestions SET created_at = created_at - ? WHERE message = ?", SUGGESTION_RETENTION_DAYS * 86_400 + 1, message);
    await runDurableObjectAlarm(hub());
    expect(await stored(message)).toEqual([]);
  });
});

describe("schema step 9", () => {
  it("adds the app's facts to suggestions stored before them, as null", async () => {
    await runInDurableObject(hub(), (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE suggestions");
      sql.exec("DROP TABLE crashes");
      sql.exec("DROP TABLE web_sign_ins");
      sql.exec("ALTER TABLE apple_accounts DROP COLUMN client_id");
      sql.exec("UPDATE schema_version SET version = 7");
      migrate(state.storage);
      sql.exec("DELETE FROM suggestions");
    });
    await runInDurableObject(hub(), (_, state) => {
      const sql = state.storage.sql;
      sql.exec("ALTER TABLE suggestions DROP COLUMN app_version");
      sql.exec("ALTER TABLE suggestions DROP COLUMN macos");
      sql.exec("ALTER TABLE suggestions DROP COLUMN edition");
      sql.exec("DROP TABLE crashes");
      sql.exec("DROP TABLE web_sign_ins");
      sql.exec("ALTER TABLE apple_accounts DROP COLUMN client_id");
      sql.exec("INSERT INTO suggestions (category, message, email, created_at) VALUES ('tab', 'Kept from before', NULL, 1)");
      sql.exec("UPDATE schema_version SET version = 8");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 11 }]);
      expect(sql.exec("SELECT message, app_version, macos, edition FROM suggestions").toArray())
        .toEqual([{ message: "Kept from before", app_version: null, macos: null, edition: null }]);
      sql.exec("DELETE FROM suggestions");
    });
  });
});

describe("schema step 8", () => {
  it("adds the suggestions table to a database at version 7 and keeps its data", async () => {
    const user = await register({ name: "Kept" });
    await runInDurableObject(hub(), (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE suggestions");
      sql.exec("DROP TABLE crashes");
      sql.exec("DROP TABLE web_sign_ins");
      sql.exec("ALTER TABLE apple_accounts DROP COLUMN client_id");
      sql.exec("UPDATE schema_version SET version = 7");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 11 }]);
      expect(sql.exec("SELECT name FROM users WHERE code = ?", user.code).toArray()).toEqual([{ name: "Kept" }]);
      expect(sql.exec("SELECT * FROM suggestions").toArray()).toEqual([]);
    });
    expect((await suggest({ category: "tab", message: IDEA })).status).toBe(201);
  });
});
