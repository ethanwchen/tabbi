import { runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GRANTABLE_ITEMS } from "../src/grants";
import { ADMIN_TOKEN, call, expectError, freshIp, hub, linkAppleAccount, pinClockToMinuteStart, register } from "./helpers";

const CAP = "accessory.backwardsCap";
const MEDAL = "accessory.teamMedal";

const grant = (code: string, item: unknown, token = ADMIN_TOKEN) =>
  call("POST", `/v1/admin/users/${code}/grants`, { item }, token, freshIp());
const items = async (token: string) => (await call("GET", "/v1/grants", undefined, token)).body.items as string[];

/** Sets when a user's friend code was created, as if they had registered then. */
async function registeredAt(code: string, at: number): Promise<void> {
  await runInDurableObject(hub(), (_, state) => {
    state.storage.sql.exec("UPDATE users SET created_at = ? WHERE code = ?", at, code);
  });
}

describe("limited edition grants", () => {
  beforeEach(pinClockToMinuteStart);
  afterEach(() => vi.useRealTimers());

  it("lists only the limited edition items the app knows", () => {
    expect(GRANTABLE_ITEMS).toEqual([CAP, "accessory.flameHeadband", "accessory.goldenLaurel", MEDAL]);
  });

  it("start empty and reach an anonymous user and a signed-in account alike", async () => {
    const anon = await register();
    const account = await register();
    await linkAppleAccount(account.code);
    expect(await items(anon.token)).toEqual([]);

    for (const user of [anon, account]) {
      const r = await grant(user.code, CAP);
      expect(r.status).toBe(200);
      expect(r.body).toEqual({ ok: true, granted: true, grants: [CAP] });
      expect(await items(user.token)).toEqual([CAP]);
    }
  });

  it("are idempotent and keep every item a user holds", async () => {
    const a = await register();
    await grant(a.code, CAP);
    expect((await grant(a.code, CAP)).body).toEqual({ ok: true, granted: false, grants: [CAP] });
    await grant(a.code.toLowerCase(), MEDAL);
    expect(await items(a.token)).toEqual([CAP, MEDAL]);
    expect((await call("GET", `/v1/admin/users/${a.code}/grants`, undefined, ADMIN_TOKEN, freshIp())).body.grants)
      .toEqual([CAP, MEDAL]);
  });

  it("only grant limited edition items to existing users", async () => {
    const a = await register();
    for (const item of ["hat.beret", "accessory.glasses", "", 7, null]) {
      expectError(await grant(a.code, item), 400, "invalid_field");
    }
    expectError(await call("POST", `/v1/admin/users/${a.code}/grants`, { item: CAP, points: 100 }, ADMIN_TOKEN, freshIp()),
      400, "unknown_field");
    expectError(await grant("ZZZZZZZZ", CAP), 404, "unknown_code");
    expect(await items(a.token)).toEqual([]);
  });

  it("can be revoked by the maintainer", async () => {
    const a = await register();
    await grant(a.code, CAP);
    const r = await call("DELETE", `/v1/admin/users/${a.code}/grants/${CAP}`, undefined, ADMIN_TOKEN, freshIp());
    expect(r.body).toEqual({ ok: true, revoked: true, grants: [] });
    expect((await call("DELETE", `/v1/admin/users/${a.code}/grants/${CAP}`, undefined, ADMIN_TOKEN, freshIp())).body.revoked)
      .toBe(false);
    expectError(await call("DELETE", `/v1/admin/users/${a.code}/grants/hat.beret`, undefined, ADMIN_TOKEN, freshIp()),
      400, "invalid_field");
    expect(await items(a.token)).toEqual([]);
  });

  it("go to everyone registered in a window, such as the launch week", async () => {
    const now = Math.floor(Date.now() / 1000);
    const week = 7 * 86_400;
    const before = await register();
    const early = await register();
    const late = await register();
    const after = await register();
    await registeredAt(before.code, now - 3 * week);
    await registeredAt(early.code, now - 2 * week);
    await registeredAt(late.code, now - week - 1);
    await registeredAt(after.code, now - week);
    await grant(late.code, CAP);

    const r = await call("POST", "/v1/admin/grants",
      { item: CAP, registeredFrom: now - 2 * week, registeredUntil: now - week }, ADMIN_TOKEN, freshIp());
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true, granted: 1 }); // late already held it
    expect(await items(before.token)).toEqual([]);
    expect(await items(early.token)).toEqual([CAP]);
    expect(await items(late.token)).toEqual([CAP]);
    expect(await items(after.token)).toEqual([]);
  });

  it("refuse a window that has not started or is empty", async () => {
    const now = Math.floor(Date.now() / 1000);
    for (const body of [
      { item: CAP, registeredFrom: now + 60, registeredUntil: now + 120 },
      { item: CAP, registeredFrom: now - 60, registeredUntil: now - 60 },
      { item: "hat.beret", registeredFrom: now - 60, registeredUntil: now },
      { item: CAP, registeredFrom: "launch", registeredUntil: now },
    ]) {
      expectError(await call("POST", "/v1/admin/grants", body, ADMIN_TOKEN, freshIp()), 400, "invalid_field");
    }
  });

  it("look like unknown paths without the admin token", async () => {
    const a = await register();
    for (const token of [undefined, a.token]) {
      expectError(await call("POST", `/v1/admin/users/${a.code}/grants`, { item: CAP }, token, freshIp()), 404, "not_found");
      expectError(await call("POST", "/v1/admin/grants", { item: CAP, registeredFrom: 0, registeredUntil: 1 }, token, freshIp()),
        404, "not_found");
    }
    expect(await items(a.token)).toEqual([]);
  });

  it("need a token to read and go away with the account", async () => {
    expectError(await call("GET", "/v1/grants"), 401, "unauthorized");
    const a = await register();
    await grant(a.code, CAP);
    await call("DELETE", "/v1/me", undefined, a.token);
    const left = await runInDurableObject(hub(), (_, state) =>
      state.storage.sql.exec("SELECT * FROM grants WHERE code = ?", a.code).toArray());
    expect(left).toEqual([]);
  });
});
