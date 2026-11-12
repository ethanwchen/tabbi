import { runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import catalog from "../shared/catalog.json";
import { migrate } from "../src/hub";
import { befriend, call, expectError, hub, oldCall, register } from "./helpers";
import { check } from "./schema";

/**
 * Radiant item upgrades: the profile's `radiant` list of `<item id>:<intensity>` entries. Apps that do
 * not know Radiant never send it and ignore it in replies; apps newer than this server may name items
 * or intensities it does not know yet, which are dropped rather than refused.
 */
const LOOK = { species: "cat", breed: "tabby", costume: "white-coat", accessories: ["crown", "wizard-hat"] };
type Seen = { profile: { code: string } & Record<string, unknown> };
const codeOf = (list: Seen[], code: string) => list.find((x) => x.profile.code === code)!.profile;

describe("the Radiant catalog", () => {
  it("lists Radiant items from the catalog's costumes and accessories, and its intensities and limit", () => {
    const items = new Set([...catalog.costumes, ...catalog.accessories]);
    for (const id of catalog.radiantItems) expect(items, id).toContain(id);
    expect(new Set(catalog.radiantItems).size).toBe(catalog.radiantItems.length);
    expect(catalog.radiantItems).not.toContain("none");
    expect(catalog.radiantIntensities).toEqual(["bold", "subtle"]);
    expect(catalog.limits.maxRadiant).toBe(3);
  });
});

describe("radiant in the profile", () => {
  it("gives an app that does not know Radiant an empty list, and takes its bodies as before", async () => {
    const old = await register({ name: "Olive", ...LOOK }, true);
    expect(old.profile.radiant).toEqual([]);
    const patched = await oldCall("PATCH", "/v1/me", { petName: "Mochi", accessories: ["crown"] }, old.token);
    expect(patched.status).toBe(200);
    expect(patched.body.profile).toMatchObject({ petName: "Mochi", accessories: ["crown"], radiant: [] });
    expect(check("profileReply", patched.body)).toEqual([]);
    expect((await oldCall("GET", "/v1/me", undefined, old.token)).body.profile.radiant).toEqual([]);
  });

  it("stores what a current app sends, sorted, and shows it to friends and party members on every app", async () => {
    const body = { ...LOOK, radiant: ["white-coat:subtle", "crown:bold"] };
    expect(check("profileBody", body)).toEqual([]);
    const glowing = await register({ name: "Cleo", ...body });
    expect(glowing.profile.radiant).toEqual(["crown:bold", "white-coat:subtle"]);
    expect(check("registerReply", glowing)).toEqual([]);
    const me = await call("GET", "/v1/me", undefined, glowing.token);
    expect(me.body.profile.radiant).toEqual(["crown:bold", "white-coat:subtle"]);
    expect(check("profileReply", me.body)).toEqual([]);

    // A friend request shows the profile, and so does the accepted friendship.
    const friend = await register({ name: "Ben" });
    const asked = await call("POST", "/v1/friends", { code: friend.code }, glowing.token);
    expect(asked.body.friend.radiant).toEqual([]);
    const incoming = (await call("GET", "/v1/friends", undefined, friend.token)).body.incoming;
    expect(codeOf(incoming, glowing.code).radiant).toEqual(["crown:bold", "white-coat:subtle"]);
    const accepted = await call("POST", `/v1/friends/${glowing.code}/accept`, undefined, friend.token);
    expect(accepted.body.friend.radiant).toEqual(["crown:bold", "white-coat:subtle"]);
    const list = (await call("GET", "/v1/friends", undefined, friend.token)).body;
    expect(check("friendList", list)).toEqual([]);
    expect(codeOf(list.friends, glowing.code).radiant).toEqual(["crown:bold", "white-coat:subtle"]);

    // An app that does not know Radiant gets the same profile, with the key it ignores.
    const old = await register({ name: "Olive" }, true);
    await befriend(glowing, old);
    const oldList = (await oldCall("GET", "/v1/friends", undefined, old.token)).body;
    expect(check("friendList", oldList)).toEqual([]);
    expect(codeOf(oldList.friends, glowing.code)).toMatchObject({ ...LOOK, radiant: ["crown:bold", "white-coat:subtle"] });

    const party = (await call("POST", "/v1/party", undefined, glowing.token)).body.party;
    expect((await call("POST", "/v1/party/join", { code: party.code }, friend.token)).status).toBe(200);
    expect((await oldCall("POST", "/v1/party/join", { code: party.code }, old.token)).status).toBe(200);
    for (const [viewer, fetch] of [[friend, call], [old, oldCall]] as const) {
      const seen = (await fetch("GET", "/v1/party", undefined, viewer.token)).body;
      expect(check("partyReply", seen)).toEqual([]);
      expect(codeOf(seen.party.members, glowing.code).radiant).toEqual(["crown:bold", "white-coat:subtle"]);
      expect(codeOf(seen.party.members, old.code).radiant).toEqual([]);
    }
  });

  it("drops entries it cannot read, items it does not know and repeated items, keeping the first per item", async () => {
    const a = await register();
    const r = await call("PATCH", "/v1/me", {
      radiant: [42, null, { item: "crown" }, "", "crown", "crown:bold:extra", ":bold", "crown:", "halo:bold", "crown:loud",
        "future-wings:bold", "crown:subtle-x", "Crown:bold", "crown:bold", "crown:subtle", "wizard-hat:subtle"],
    }, a.token);
    expect(r.status).toBe(200);
    expect(r.body.profile.radiant).toEqual(["crown:bold", "wizard-hat:subtle"]);
    // A list with nothing this server knows is no Radiant at all.
    const none = await call("PATCH", "/v1/me", { radiant: ["future-wings:bold", "crown:dazzling"] }, a.token);
    expect(none.body.profile.radiant).toEqual([]);
  });

  it("refuses a radiant that is not a list", async () => {
    const a = await register();
    for (const radiant of ["crown:bold", { crown: "bold" }, null, 3, true]) {
      expectError(await call("PATCH", "/v1/me", { radiant }, a.token), 400, "invalid_field");
    }
    const refused = await call("POST", "/v1/register", { radiant: "crown:bold" });
    expectError(refused, 400, "invalid_field");
    expect((await call("GET", "/v1/me", undefined, a.token)).body.profile.radiant).toEqual([]);
  });

  it(`keeps the first ${catalog.limits.maxRadiant} it can read, sorted`, async () => {
    const a = await register({
      radiant: ["rain-cloud:subtle", "unknown:bold", "astronaut-helmet:bold", "crown:subtle", "white-coat:bold", "graduation-cap:bold"],
    });
    expect(a.profile.radiant).toEqual(["astronaut-helmet:bold", "crown:subtle", "rain-cloud:subtle"]);
  });

  it("keeps the stored list through bodies that leave it out, and clears it with an empty one", async () => {
    const a = await register({ radiant: ["dinosaur-hoodie:bold"] });
    expect((await call("PATCH", "/v1/me", { petName: "Kiwi", level: 3 }, a.token)).body.profile.radiant).toEqual(["dinosaur-hoodie:bold"]);
    expect((await oldCall("PATCH", "/v1/me", { costume: "pirate" }, a.token)).body.profile.radiant).toEqual(["dinosaur-hoodie:bold"]);
    expect((await call("POST", "/v1/register", { name: "Maya" }, a.token)).body.profile.radiant).toEqual(["dinosaur-hoodie:bold"]);
    expect((await call("GET", "/v1/me", undefined, a.token)).body.profile).toMatchObject({ petName: "Kiwi", costume: "pirate", radiant: ["dinosaur-hoodie:bold"] });
    expect((await call("PATCH", "/v1/me", { radiant: [] }, a.token)).body.profile.radiant).toEqual([]);
    expect((await call("GET", "/v1/me", undefined, a.token)).body.profile.radiant).toEqual([]);
  });
});

describe("schema step 15", () => {
  it("adds the radiant column to a database at version 14, reading its users as wearing none", async () => {
    await runInDurableObject(hub(), (_, state) => {
      const sql = state.storage.sql;
      sql.exec("ALTER TABLE users DROP COLUMN radiant");
      sql.exec("UPDATE schema_version SET version = 14");
      sql.exec(`INSERT INTO users (code, token_hash, name, pet_name, species, breed, colors, costume, accessories, points, level, created_at)
        VALUES ('RADNT2AA', 'radiant-migration', 'n', 'p', 'cat', 'tabby', '[]', 'none', '["crown"]', 5, 1, 0)`);
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 15 }]);
      expect(sql.exec("SELECT accessories, points, radiant FROM users WHERE code = 'RADNT2AA'").toArray())
        .toEqual([{ accessories: '["crown"]', points: 5, radiant: "[]" }]);
    });
  });
});
