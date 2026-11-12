import { describe, expect, it } from "vitest";
import catalog from "../shared/catalog.json";
import fixture from "../../shared/fixtures/party/party.json";
import { PROTOCOL_HEADER } from "../src/lib";
import { BASE, call, oldCall, register } from "./helpers";
import { check, checkCrews } from "./schema";
import { crewBody } from "./crewHelpers";

/**
 * Apps on different versions (and the Mac and Windows apps) Party and stay friends together. "Old" is an
 * app up to 1.0.0: it sends no Tabbi-Protocol header, knows only the catalog version 1 ids, reads only
 * the reply fields it had then, and has no friend requests. See docs/party-compatibility.md.
 */
type User = { code: string; token: string };
const codes = (list: { profile: { code: string } }[]) => list.map((x) => x.profile.code);

/** The reply fields an app up to 1.0.0 decodes; every one must still be there. */
const OLD_PROFILE_FIELDS = ["code", "name", "petName", "species", "breed", "colors", "costume", "accessories", "points", "level"];
const expectOldProfile = (profile: Record<string, unknown>) => {
  for (const field of OLD_PROFILE_FIELDS) expect(profile, field).toHaveProperty(field);
};

/** How the current app dresses a pet: an outfit, a hat and four more items, and ten colors. */
const NEW_LOOK = {
  petName: "Nova", species: "dog", breed: "corgi", costume: "dinosaur-hoodie",
  accessories: ["snow-scarf", "heart-glasses", "wizard-hat", "angel-wings", "sparkle-trail"],
  colors: ["#D98C4A", "#B06A33", "#F2C38B", "#5A3A22", "#FFF1DE", "#3E7CB1", "#2E5E88", "#FFFFFF", "#E2557A", "#B83D5E"],
};
/** How an app up to 1.0.0 sent a graduation cap with no outfit: in costume, with six colors. */
const OLD_LOOK = {
  petName: "Mochi", species: "cat", breed: "tabby", costume: "graduation", accessories: ["glasses", "scarf"],
  colors: ["#D98C4A", "#B06A33", "#F2C38B", "#5A3A22", "#FFF1DE", "#3E7CB1"],
};

describe("friends across app versions", () => {
  it("an older app's add waits as a request that the current app accepts", async () => {
    const old = await register({ name: "Olive" }, true);
    const current = await register({ name: "Cleo" });
    const asked = await oldCall("POST", "/v1/friends", { code: current.code }, old.token);
    expect(asked.status).toBe(200);
    // The reply the old app reads: ok, added and friend, as before.
    expect(asked.body).toMatchObject({ ok: true, added: false, friend: { code: current.code } });
    expectOldProfile(asked.body.friend);

    expect(codes((await call("GET", "/v1/friends", undefined, current.token)).body.incoming)).toEqual([old.code]);
    const oldList = await oldCall("GET", "/v1/friends", undefined, old.token);
    expect(oldList.body.friends).toEqual([]);

    await call("POST", `/v1/friends/${old.code}/accept`, undefined, current.token);
    const after = await oldCall("GET", "/v1/friends", undefined, old.token);
    expect(codes(after.body.friends)).toEqual([current.code]);
    expectOldProfile(after.body.friends[0].profile);
  });

  it("the current app's request to an older app, which cannot show one, is a friendship at once", async () => {
    const current = await register();
    const old = await register({}, true);
    const asked = await call("POST", "/v1/friends", { code: old.code }, current.token);
    expect(asked.body).toMatchObject({ ok: true, added: true, status: "friends" });
    expect(codes((await oldCall("GET", "/v1/friends", undefined, old.token)).body.friends)).toEqual([current.code]);
    expect(codes((await call("GET", "/v1/friends", undefined, current.token)).body.friends)).toEqual([old.code]);
    // Two older apps add each other at once, as they always did.
    const other = await register({}, true);
    expect((await oldCall("POST", "/v1/friends", { code: other.code }, old.token)).body).toMatchObject({ added: true });
  });

  it("asks for an answer once the older app updates, and an older Mac of the same user never undoes that", async () => {
    const current = await register();
    const updated = await register({}, true);
    await call("GET", "/v1/me", undefined, updated.token);
    expect((await call("POST", "/v1/friends", { code: updated.code }, current.token)).body.status).toBe("requested");
    await oldCall("GET", "/v1/me", undefined, updated.token);
    const another = await register();
    expect((await call("POST", "/v1/friends", { code: updated.code }, another.token)).body.status).toBe("requested");
    expect((await call("GET", "/v1/friends", undefined, updated.token)).body.incoming).toHaveLength(2);
  });

  it("reads a protocol it does not know yet as its own newest, and an unreadable one as 1", async () => {
    const future = await SELFRegister("9");
    const garbled = await SELFRegister("two");
    const asker = await register();
    expect((await call("POST", "/v1/friends", { code: future.code }, asker.token)).body.status).toBe("requested");
    expect((await call("POST", "/v1/friends", { code: garbled.code }, asker.token)).body.status).toBe("friends");
  });
});

/** Registers with a raw Tabbi-Protocol header value. */
async function SELFRegister(protocol: string): Promise<User> {
  const { SELF } = await import("cloudflare:test");
  const res = await SELF.fetch(`${BASE}/v1/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json", [PROTOCOL_HEADER]: protocol, "CF-Connecting-IP": `10.9.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}` },
    body: "{}",
  });
  expect(res.status).toBe(201);
  return await res.json() as User;
}

describe("a party across app versions", () => {
  it("seats an older and a current app together, each seeing the other's pet as sent", async () => {
    const current = await register({ name: "Cleo", ...NEW_LOOK });
    const old = await register({ name: "Olive", ...OLD_LOOK }, true);
    const party = (await call("POST", "/v1/party", undefined, current.token)).body.party;
    const joined = await oldCall("POST", "/v1/party/join", { code: party.code }, old.token);
    expect(joined.status).toBe(200);
    await oldCall("POST", "/v1/presence", { status: "studying", method: "pomodoro", todayMinutes: 5 }, old.token);
    await call("POST", "/v1/party/session", { method: "pomodoro", phaseEndsAt: Math.floor(Date.now() / 1000) + 1500 }, current.token);

    for (const [viewer, fetch] of [[old, oldCall], [current, call]] as const) {
      const seen = (await fetch("GET", "/v1/party", undefined, viewer.token)).body.party;
      expect(check("party", seen)).toEqual([]);
      const byCode = Object.fromEntries(seen.members.map((m: { profile: { code: string } }) => [m.profile.code, m.profile]));
      expect(byCode[current.code]).toMatchObject(NEW_LOOK);
      expect(byCode[old.code]).toMatchObject(OLD_LOOK);
      for (const member of seen.members) expectOldProfile(member.profile);
      expect(seen.session).toMatchObject({ method: "pomodoro" });
    }
  });

  it("shows an older app a breed added after its catalog as it is, for the app to fall back on", async () => {
    const current = await register({ name: "Cleo", ...NEW_LOOK, species: "cat", breed: "british-longhair" });
    const old = await register({ name: "Olive", ...OLD_LOOK }, true);
    const party = (await call("POST", "/v1/party", undefined, current.token)).body.party;
    expect((await oldCall("POST", "/v1/party/join", { code: party.code }, old.token)).status).toBe(200);
    const seen = (await oldCall("GET", "/v1/party", undefined, old.token)).body.party;
    expect(check("party", seen)).toEqual([]);
    const cleo = seen.members.find((m: { profile: { code: string } }) => m.profile.code === current.code);
    expect(cleo.profile).toMatchObject({ species: "cat", breed: "british-longhair" });
    expectOldProfile(cleo.profile);
  });

  it("carries the mastery outfits of catalog version 4 to friends and party members on older apps", async () => {
    const MASTERY_LOOK = {
      petName: "Sage", species: "cat", breed: "tuxedo", costume: "sages-robe",
      accessories: ["bandana", "owl-spectacles", "nightcap", "tiny-lantern"],
      colors: NEW_LOOK.colors,
    };
    expect(catalog.version).toBeGreaterThanOrEqual(4);
    const current = await register({ name: "Mia", ...MASTERY_LOOK });
    const old = await register({ name: "Olive", ...OLD_LOOK }, true);
    expect((await call("POST", "/v1/friends", { code: old.code }, current.token)).body).toMatchObject({ added: true });
    const friends = (await oldCall("GET", "/v1/friends", undefined, old.token)).body.friends;
    expect(friends[0].profile).toMatchObject(MASTERY_LOOK);
    expectOldProfile(friends[0].profile);

    const party = (await call("POST", "/v1/party", undefined, current.token)).body.party;
    expect((await oldCall("POST", "/v1/party/join", { code: party.code }, old.token)).status).toBe(200);
    for (const [viewer, fetch] of [[old, oldCall], [current, call]] as const) {
      const seen = (await fetch("GET", "/v1/party", undefined, viewer.token)).body.party;
      expect(check("party", seen)).toEqual([]);
      const mia = seen.members.find((m: { profile: { code: string } }) => m.profile.code === current.code);
      expect(mia.profile).toMatchObject(MASTERY_LOOK);
    }
    // The pajamas and the bandana reuse ids every catalog had, so an older server takes them too.
    const patched = await oldCall("PATCH", "/v1/me", { costume: "pajamas", accessories: ["bandana"] }, old.token);
    expect(patched.body.profile).toMatchObject({ costume: "pajamas", accessories: ["bandana"] });
  });

  it("carries release 7's items of catalog version 5 to friends and party members on older apps", async () => {
    const RELEASE7_LOOK = {
      petName: "Juno", species: "dog", breed: "corgi", costume: "rain-slicker",
      accessories: ["daisy-chain", "mushroom-cap", "fireflies", "glasses"],
      colors: NEW_LOOK.colors,
    };
    expect(catalog.version).toBe(5);
    for (const id of ["librarian-cardigan", "varsity-jacket", "keepers-peacoat", "rain-slicker", "koi-yukata", "sushi-chef", "snow-day-puffer"]) {
      expect(catalog.costumes).toContain(id);
    }
    for (const id of ["daisy-chain", "sailor-collar", "strawberry-cap", "mushroom-cap", "cactus-pot", "sun-hat", "aviator-cap", "fireflies"]) {
      expect(catalog.accessories).toContain(id);
    }
    const current = await register({ name: "June", ...RELEASE7_LOOK });
    const old = await register({ name: "Otto", ...OLD_LOOK }, true);
    expect((await call("POST", "/v1/friends", { code: old.code }, current.token)).body).toMatchObject({ added: true });
    const friends = (await oldCall("GET", "/v1/friends", undefined, old.token)).body.friends;
    expect(friends[0].profile).toMatchObject(RELEASE7_LOOK);
    expectOldProfile(friends[0].profile);

    const party = (await call("POST", "/v1/party", undefined, current.token)).body.party;
    expect((await oldCall("POST", "/v1/party/join", { code: party.code }, old.token)).status).toBe(200);
    for (const [viewer, fetch] of [[old, oldCall], [current, call]] as const) {
      const seen = (await fetch("GET", "/v1/party", undefined, viewer.token)).body.party;
      expect(check("party", seen)).toEqual([]);
      const june = seen.members.find((m: { profile: { code: string } }) => m.profile.code === current.code);
      expect(june.profile).toMatchObject(RELEASE7_LOOK);
    }
  });

  it("keeps taking what an older app sends: catalog version 1 ids and six colors", async () => {
    const old = await register({}, true);
    const patched = await oldCall("PATCH", "/v1/me", { costume: "pirate", accessories: ["crown", "bow", "halo", "glasses"], colors: OLD_LOOK.colors }, old.token);
    expect(patched.status).toBe(200);
    expect(patched.body.profile).toMatchObject({ costume: "pirate", accessories: ["crown", "bow", "halo", "glasses"] });
  });

  it("serves every id an app may send, the current catalog's and every older one's", () => {
    const v1Costumes = ["none", "scrubs", "white-coat", "surgical-cap", "stethoscope", "lab-goggles", "graduation", "hoodie",
      "sweater", "pajamas", "raincoat", "wizard", "chef", "pirate", "astronaut", "superhero", "witch", "santa", "pumpkin", "bunny"];
    const v1Accessories = ["glasses", "sunglasses", "headphones", "bow", "bandana", "scarf", "collar-bell", "crown", "flower",
      "party-hat", "beanie", "coffee-mug", "pencil", "book", "id-badge", "reflex-hammer", "face-mask", "halo"];
    const v2CatBreeds = ["domestic-shorthair", "domestic-longhair", "tabby", "tuxedo", "calico", "tortoiseshell", "siamese",
      "persian", "maine-coon", "british-shorthair", "ragdoll", "bengal", "sphynx", "scottish-fold", "russian-blue",
      "abyssinian", "norwegian-forest", "black-cat"];
    expect(catalog.breeds.cat).toEqual(expect.arrayContaining(v2CatBreeds));
    expect(catalog.costumes).toEqual(expect.arrayContaining(v1Costumes));
    expect(catalog.accessories).toEqual(expect.arrayContaining(v1Accessories));
    expect(catalog.limits.maxAccessories).toBeGreaterThanOrEqual(4);
    expect(catalog.limits.maxColors).toBeGreaterThanOrEqual(6);
  });
});

describe("the shared wire contract (shared/schemas/party.v1.schema.json)", () => {
  it("describes every reply the server sends to the current and to an older app", async () => {
    const health = await call("GET", "/");
    expect(check("health", health.body)).toEqual([]);
    const a = await register({ name: "Ana", ...NEW_LOOK });
    const b = await register({ name: "Ben" });
    const old = await register({}, true);
    expect(check("registerReply", a)).toEqual([]);
    expect(check("profileReply", (await call("GET", "/v1/me", undefined, a.token)).body)).toEqual([]);
    expect(check("profileReply", (await call("PATCH", "/v1/me", { petName: "Kiwi" }, a.token)).body)).toEqual([]);
    expect(check("addFriendReply", (await call("POST", "/v1/friends", { code: b.code }, a.token)).body)).toEqual([]);
    expect(check("addFriendReply", (await call("POST", "/v1/friends", { code: old.code }, a.token)).body)).toEqual([]);
    expect(check("friendList", (await call("GET", "/v1/friends", undefined, b.token)).body)).toEqual([]);
    expect(check("addFriendReply", (await call("POST", `/v1/friends/${a.code}/accept`, undefined, b.token)).body)).toEqual([]);
    expect(check("heartbeatReply", (await call("POST", "/v1/presence", { status: "studying", todayMinutes: 3 }, a.token)).body)).toEqual([]);
    expect(check("heartbeatReply", (await oldCall("POST", "/v1/presence", { status: "offline" }, old.token)).body)).toEqual([]);
    expect(check("friendList", (await call("GET", "/v1/friends", undefined, a.token)).body)).toEqual([]);
    expect(check("friendList", (await oldCall("GET", "/v1/friends", undefined, old.token)).body)).toEqual([]);
    expect(check("partyReply", (await call("GET", "/v1/party", undefined, a.token)).body)).toEqual([]);
    const party = await call("POST", "/v1/party", undefined, a.token);
    expect(check("partyReply", party.body)).toEqual([]);
    expect(check("partyReply", (await call("POST", "/v1/party/join", { friend: a.code }, b.token)).body)).toEqual([]);
    expect(check("removeFriendReply", (await call("DELETE", `/v1/friends/${old.code}`, undefined, a.token)).body)).toEqual([]);
    expect(check("error", (await call("POST", "/v1/friends/AAAAAAAA/accept", undefined, a.token)).body)).toEqual([]);
  });

  it("describes the request bodies the apps send, and the shared fixtures the apps decode", () => {
    expect(check("profileBody", NEW_LOOK)).toEqual([]);
    expect(check("profileBody", { ...NEW_LOOK, cardDeck: "x" })).not.toEqual([]);
    for (const update of fixture.updates) expect(check("profileBody", update.body), update.name).toEqual([]);
    for (const reply of fixture.replies) expect(check(reply.schema, reply.json), reply.name).toEqual([]);
    for (const update of fixture.updates) {
      for (const id of update.body.accessories ?? []) expect(catalog.accessories, `${update.name}: ${id}`).toContain(id);
      if (update.body.costume) expect(catalog.costumes, update.name).toContain(update.body.costume);
    }
  });
});

/**
 * shared/fixtures/crews/crews.json, written by the Mac app's golden tests, pins the Crews requests the
 * apps send and the replies they decode; every one must fit shared/schemas/crews.v1.schema.json.
 */
const crewFixtures = import.meta.glob<{
  requests?: { name: string; method: string; path: string; schema: string; body: unknown }[];
  replies?: { name: string; schema: string; json: unknown }[];
}>("../../shared/fixtures/crews/crews.json", { eager: true, import: "default" });

describe("the Crews wire contract (shared/schemas/crews.v1.schema.json)", () => {
  it("describes the request bodies the apps send", () => {
    expect(checkCrews("createBody", crewBody())).toEqual([]);
    expect(checkCrews("createBody", { ...crewBody(), deck: "x" })).not.toEqual([]);
    expect(checkCrews("updateBody", { description: "" })).toEqual([]);
    expect(checkCrews("joinBody", { code: "K7QW2MZ" })).toEqual([]);
    expect(checkCrews("joinBody", { crew: "K7QW2MZD3F" })).toEqual([]);
    expect(checkCrews("joinBody", { code: "K7QW2MZ", crew: "K7QW2MZD3F" })).not.toEqual([]);
    expect(checkCrews("sessionsBody", { sessions: [{ start: 1, end: 61, minutes: 1 }] })).toEqual([]);
    expect(checkCrews("sessionsBody", { sessions: [] })).not.toEqual([]);
    expect(checkCrews("memberSettingsBody", { showPet: false })).toEqual([]);
    expect(checkCrews("reportBody", { crew: "K7QW2MZD3F", reason: "cheating" })).toEqual([]);
    expect(checkCrews("blockBody", { crew: "K7QW2MZD3F", member: "K7QW2MZD3F" })).toEqual([]);
  });

  it("describes every request and reply in the shared Crews fixture, when there is one", () => {
    for (const fixture of Object.values(crewFixtures)) {
      for (const r of fixture.requests ?? []) {
        // A route without a body schema (leave, remove) sends an empty object or nothing.
        if (r.schema) expect(checkCrews(r.schema, r.body), r.name).toEqual([]);
        else expect(r.body === undefined || r.body === null || Object.keys(r.body).length === 0, r.name).toBe(true);
        expect(r.path, r.name).toMatch(/^\/v1\/crews/);
      }
      // A "newer server" reply carries ids and fields this server never sends, to pin how the
      // app reads them; it is the app's leniency under test, not this server's shape.
      for (const r of fixture.replies ?? []) {
        if (!r.name.startsWith("newer server")) expect(checkCrews(r.schema, r.json), r.name).toEqual([]);
      }
    }
  });
});
