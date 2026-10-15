import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ENTITLEMENTS, ENTITLEMENT_SOURCES, FOUNDING, FOUNDING_DAYS, badgesOf, foundingEnd, isFounding, itemsOf,
} from "../src/entitlements";
import { GRANTABLE_ITEMS } from "../src/grants";
import { migrate } from "../src/hub";
import { identityToken, installFakeApple } from "./fake-apple";
import { ADMIN_TOKEN, call, freshIp, hub, register, befriend } from "./helpers";

installFakeApple();

const PIN = "accessory.foundersPin";
const CAP = "accessory.backwardsCap";
const DAY = 86_400;
/** FOUNDING_LAUNCH in vitest.config.ts: March 1, 2026, midnight UTC. */
const LAUNCH = Date.parse("2026-03-01T00:00:00Z") / 1000;
const WINDOW_END = LAUNCH + FOUNDING_DAYS * DAY;

/** Moves the Hub's clock to unix second `at`. */
function at(seconds: number): void {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(seconds * 1000);
}

const signIn = async (sub: string, token?: string) => {
  const r = await call("POST", "/v1/auth/apple", { identityToken: await identityToken(sub) }, token, freshIp());
  expect(r.status).toBe(200);
  return r.body as { token: string; code: string };
};
const grants = async (token: string) => (await call("GET", "/v1/grants", undefined, token)).body as { items: string[]; entitlements: string[] };

async function entitlementRows(code: string) {
  return runInDurableObject(hub(), (_, state) =>
    state.storage.sql.exec("SELECT entitlement, source, reference, ends_at FROM entitlements WHERE code = ?", code).toArray());
}

describe("the founding window", () => {
  it("is read from FOUNDING_LAUNCH as unix seconds or an ISO date", () => {
    expect(env.FOUNDING_LAUNCH).toBe("2026-03-01");
    expect(foundingEnd({ FOUNDING_LAUNCH: "2026-03-01" })).toBe(WINDOW_END);
    expect(foundingEnd({ FOUNDING_LAUNCH: String(LAUNCH) })).toBe(WINDOW_END);
    expect(foundingEnd({ FOUNDING_LAUNCH: " 2026-03-01T00:00:00Z " })).toBe(WINDOW_END);
    expect(foundingEnd({ FOUNDING_LAUNCH: "2026-03-01T01:00:00+01:00" })).toBe(WINDOW_END);
  });

  it("has no end while FOUNDING_LAUNCH is unset, so nobody is left out before the launch", () => {
    for (const unset of [undefined, "", "  "]) {
      expect(foundingEnd({ FOUNDING_LAUNCH: unset })).toBeNull();
      expect(isFounding(0, foundingEnd({ FOUNDING_LAUNCH: unset }))).toBe(true);
      expect(isFounding(4_000_000_000, foundingEnd({ FOUNDING_LAUNCH: unset }))).toBe(true);
    }
  });

  it("grants nothing new when FOUNDING_LAUNCH cannot be read", () => {
    for (const typo of ["next week", "03/01/2026", "2026-13-45", "12", "1.5e9", "-1772323200"]) {
      const end = foundingEnd({ FOUNDING_LAUNCH: typo });
      expect(end).toBe(-Infinity);
      expect(isFounding(0, end)).toBe(false);
    }
  });

  it("covers everyone who first signed in before launch + 100 days, beta testers included", () => {
    expect(isFounding(LAUNCH - 365 * DAY, WINDOW_END)).toBe(true);
    expect(isFounding(LAUNCH, WINDOW_END)).toBe(true);
    expect(isFounding(WINDOW_END - 1, WINDOW_END)).toBe(true);
    expect(isFounding(WINDOW_END, WINDOW_END)).toBe(false);
  });
});

describe("the entitlements catalog", () => {
  it("has Founding Member, which brings the Founder's Pin and shows a badge", () => {
    expect(ENTITLEMENTS).toEqual([{ id: FOUNDING, badge: true, items: [PIN] }]);
    expect(ENTITLEMENT_SOURCES).toEqual([FOUNDING]);
    expect(itemsOf([FOUNDING, "unknown"])).toEqual([PIN]);
    expect(badgesOf([FOUNDING, "unknown"])).toEqual([FOUNDING]);
    expect(itemsOf([])).toEqual([]);
  });

  it("only brings limited edition items the app knows", () => {
    for (const e of ENTITLEMENTS) for (const item of e.items) expect(GRANTABLE_ITEMS).toContain(item);
  });
});

describe("Founding Member", () => {
  afterEach(() => vi.useRealTimers());

  it("is recorded at sign-in inside the window and comes back through GET /v1/grants", async () => {
    at(LAUNCH + 30 * DAY);
    const account = await signIn("sub.founding.in");
    expect(await grants(account.token)).toEqual({ ok: true, items: [PIN], entitlements: [FOUNDING] });
    expect(await entitlementRows(account.code)).toEqual([{ entitlement: FOUNDING, source: FOUNDING, reference: null, ends_at: null }]);
  });

  it("is not given to an account that first signs in once the window has ended", async () => {
    at(WINDOW_END);
    const late = await signIn("sub.founding.late");
    expect(await grants(late.token)).toEqual({ ok: true, items: [], entitlements: [] });
    expect(await entitlementRows(late.code)).toEqual([]);
  });

  it("is never given to a Party identity that has not signed in, however early", async () => {
    at(LAUNCH + DAY);
    const anon = await register();
    expect(await grants(anon.token)).toEqual({ ok: true, items: [], entitlements: [] });
  });

  it("counts the first sign-in, not when the friend code was made", async () => {
    at(LAUNCH + DAY);
    const early = await register();
    at(WINDOW_END + DAY);
    await signIn("sub.founding.code-early", early.token);
    expect((await grants(early.token)).entitlements).toEqual([]);

    at(WINDOW_END - DAY);
    const anon = await register();
    await signIn("sub.founding.code-in", anon.token);
    at(WINDOW_END + 10 * DAY);
    expect((await grants(anon.token)).entitlements).toEqual([FOUNDING]);
  });

  it("reaches accounts from before the rule (beta testers) on their next grants request, with no admin run", async () => {
    at(WINDOW_END + 50 * DAY);
    const beta = await register();
    await runInDurableObject(hub(), (_, state) => {
      state.storage.sql.exec("INSERT INTO apple_accounts (apple_sub, code, refresh_token, created_at) VALUES (?, ?, NULL, ?)",
        "sub.founding.beta", beta.code, LAUNCH - 90 * DAY);
    });
    expect(await entitlementRows(beta.code)).toEqual([]);
    expect(await grants(beta.token)).toEqual({ ok: true, items: [PIN], entitlements: [FOUNDING] });
  });

  it("is idempotent and follows the account to a new Mac and a reinstall", async () => {
    at(LAUNCH + 10 * DAY);
    const mac1 = await signIn("sub.founding.macs");
    await grants(mac1.token);
    await signIn("sub.founding.macs", mac1.token);
    at(WINDOW_END + 200 * DAY);
    const mac2 = await signIn("sub.founding.macs");
    expect(mac2.code).toBe(mac1.code);
    expect(await grants(mac2.token)).toEqual({ ok: true, items: [PIN], entitlements: [FOUNDING] });
    expect(await entitlementRows(mac1.code)).toHaveLength(1);
  });

  it("is listed after the maintainer's grants without repeating an item", async () => {
    at(LAUNCH + 10 * DAY);
    const account = await signIn("sub.founding.with-grants");
    for (const item of [CAP, PIN]) {
      await call("POST", `/v1/admin/users/${account.code}/grants`, { item }, ADMIN_TOKEN, freshIp());
    }
    expect((await grants(account.token)).items).toEqual([CAP, PIN]);
    const listed = await call("GET", `/v1/admin/users/${account.code}/grants`, undefined, ADMIN_TOKEN, freshIp());
    expect(listed.body).toEqual({ ok: true, grants: [CAP, PIN], entitlements: [FOUNDING] });
  });

  it("stays with the account when an anonymous Mac folds into it", async () => {
    at(LAUNCH + 10 * DAY);
    const account = await signIn("sub.founding.fold");
    const otherMac = await register();
    at(WINDOW_END + DAY);
    const folded = await signIn("sub.founding.fold", otherMac.token);
    expect(folded.code).toBe(account.code);
    expect((await grants(folded.token)).entitlements).toEqual([FOUNDING]);
  });

  it("goes away with the account", async () => {
    at(LAUNCH + 10 * DAY);
    const account = await signIn("sub.founding.delete");
    expect(await entitlementRows(account.code)).toHaveLength(1);
    expect((await call("DELETE", "/v1/me", undefined, account.token)).status).toBe(200);
    expect(await entitlementRows(account.code)).toEqual([]);
  });

  it("shows as a badge to friends and party members, and nobody else gets one", async () => {
    at(LAUNCH + 10 * DAY);
    const founder = await signIn("sub.founding.badge");
    const friend = await register();
    await befriend(friend, founder);

    const friends = (await call("GET", "/v1/friends", undefined, friend.token)).body.friends;
    expect(friends.map((f: { profile: { badges: string[] } }) => f.profile.badges)).toEqual([[FOUNDING]]);
    const theirs = (await call("GET", "/v1/friends", undefined, founder.token)).body.friends;
    expect(theirs.map((f: { profile: { badges: string[] } }) => f.profile.badges)).toEqual([[]]);

    const party = (await call("POST", "/v1/party", undefined, founder.token)).body.party;
    const joined = (await call("POST", "/v1/party/join", { code: party.code }, friend.token)).body.party;
    expect(joined.members.map((m: { profile: { code: string; badges: string[] } }) => [m.profile.code, m.profile.badges]))
      .toEqual([[founder.code, [FOUNDING]], [friend.code, []]]);
  });

  it("ignores an entitlement that has not started or has ended", async () => {
    at(WINDOW_END + DAY);
    const account = await signIn("sub.founding.ended");
    const now = Math.floor(Date.now() / 1000);
    await runInDurableObject(hub(), (_, state) => {
      state.storage.sql.exec(
        `INSERT INTO entitlements (code, entitlement, source, reference, starts_at, ends_at, created_at)
         VALUES (?, ?, ?, NULL, ?, ?, ?)`, account.code, FOUNDING, FOUNDING, now - 10 * DAY, now - DAY, now - 10 * DAY);
    });
    expect((await grants(account.token)).entitlements).toEqual([]);
    await runInDurableObject(hub(), (_, state) => {
      state.storage.sql.exec("UPDATE entitlements SET starts_at = ?, ends_at = NULL WHERE code = ?", now + DAY, account.code);
    });
    expect((await grants(account.token)).entitlements).toEqual([]);
  });

  it("records a store reference at most once per source", async () => {
    const [a, b] = [await register(), await register()];
    const insert = (code: string) => runInDurableObject(hub(), (_, state) => {
      state.storage.sql.exec(
        `INSERT INTO entitlements (code, entitlement, source, reference, starts_at, ends_at, created_at)
         VALUES (?, 'plus', 'app-store', 'txn-1', 0, NULL, 0)`, code);
    });
    await insert(a.code);
    await expect(insert(b.code)).rejects.toThrow(/UNIQUE/);
  });
});

describe("schema step 13", () => {
  it("adds the entitlements table to a database at version 12 and keeps its accounts", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("version-12"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE entitlements");
      sql.exec("DROP TABLE friend_requests");
      sql.exec("ALTER TABLE users DROP COLUMN protocol");
      sql.exec("UPDATE schema_version SET version = 12");
      sql.exec("INSERT INTO apple_accounts (apple_sub, code, refresh_token, created_at) VALUES ('s', 'CCCCCCCC', 'r', 0)");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 14 }]);
      expect(sql.exec("SELECT apple_sub, code FROM apple_accounts").toArray()).toEqual([{ apple_sub: "s", code: "CCCCCCCC" }]);
      expect(sql.exec("SELECT * FROM entitlements").toArray()).toEqual([]);
    });
  });
});
