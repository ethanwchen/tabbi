import { runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Hub } from "../src/hub";
import { call, expectError, freshIp, hub, pinClockToMinuteStart, register } from "./helpers";

/**
 * Friend codes (8 characters) and party codes (6) are drawn at random, and a draw that is already taken
 * is drawn again, up to 20 more times, before the request gives up with a 503. A collision is too rare to
 * meet by chance, so these tests script the draws: `crypto.getRandomValues` (shared by the test and the
 * Hub, which run in one isolate) hands out the given codes for arrays of the code's length and real
 * randomness for everything else (tokens are 32 bytes).
 */
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function scriptCodes(length: number, codes: string[]) {
  const real = crypto.getRandomValues.bind(crypto);
  const queue = [...codes];
  const spy = vi.spyOn(crypto, "getRandomValues").mockImplementation(((array: Uint8Array) => {
    if (!(array instanceof Uint8Array) || array.length !== length) return real(array);
    // The last scripted code repeats once the list runs out, so "always taken" needs only one entry.
    const code = queue.length > 1 ? queue.shift()! : queue[0];
    array.set(Array.from(code, (c) => ALPHABET.indexOf(c)));
    return array;
  }) as typeof crypto.getRandomValues);
  return { draws: () => spy.mock.calls.filter(([a]) => a instanceof Uint8Array && a.length === length).length };
}

const userCount = () => runInDurableObject(hub(), (_hub: Hub, state) =>
  state.storage.sql.exec("SELECT COUNT(*) AS n FROM users").one().n as number);

const partyCount = () => runInDurableObject(hub(), (_hub: Hub, state) =>
  state.storage.sql.exec("SELECT COUNT(*) AS n FROM parties").one().n as number);

beforeEach(pinClockToMinuteStart);

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe("friend code allocation", () => {
  it("draws again when a code is taken, and leaves the owner's account alone", async () => {
    scriptCodes(8, ["TAKENAAA"]);
    const owner = await register({ name: "Ana" });
    expect(owner.code).toBe("TAKENAAA");

    vi.restoreAllMocks();
    const script = scriptCodes(8, ["TAKENAAA", "TAKENAAA", "FRESHBBB"]);
    const next = await register({ name: "Ben" });
    expect(next.code).toBe("FRESHBBB");
    expect(script.draws()).toBe(3);

    const me = await call("GET", "/v1/me", undefined, owner.token);
    expect(me.status).toBe(200);
    expect(me.body.profile.code).toBe("TAKENAAA");
    expect(me.body.profile.name).toBe("Ana");
  });

  it("gives up with a 503 after 21 taken draws and creates no account", async () => {
    scriptCodes(8, ["FULLCCCC"]);
    await register();
    const users = await userCount();

    vi.restoreAllMocks();
    const script = scriptCodes(8, ["FULLCCCC"]);
    const r = await call("POST", "/v1/register", { name: "Cy" }, undefined, freshIp());
    expectError(r, 503, "unavailable");
    expect(r.body.token).toBeUndefined();
    expect(script.draws()).toBe(21);
    expect(await userCount()).toBe(users);

    // Once codes are free again, the same client simply retries.
    vi.restoreAllMocks();
    const retry = await register({ name: "Cy" });
    expect(retry.code).not.toBe("FULLCCCC");
    expect(await userCount()).toBe(users + 1);
  });
});

describe("party code allocation", () => {
  it("draws again when a party code is taken", async () => {
    const ana = await register();
    const ben = await register();
    scriptCodes(6, ["PARTYA"]);
    const first = await call("POST", "/v1/party", undefined, ana.token);
    expect(first.status).toBe(201);
    expect(first.body.party.code).toBe("PARTYA");

    vi.restoreAllMocks();
    const script = scriptCodes(6, ["PARTYA", "PARTYB"]);
    const second = await call("POST", "/v1/party", undefined, ben.token);
    expect(second.status).toBe(201);
    expect(second.body.party.code).toBe("PARTYB");
    expect(script.draws()).toBe(2);

    // Ana's party still has her as its host and only member.
    const mine = await call("GET", "/v1/party", undefined, ana.token);
    expect(mine.body.party.code).toBe("PARTYA");
    expect(mine.body.party.members.map((m: { profile: { code: string } }) => m.profile.code)).toEqual([ana.code]);
  });

  it("gives up with a 503 and keeps the caller in the party they were in", async () => {
    const ana = await register();
    const ben = await register();
    scriptCodes(6, ["BUSYPP"]);
    expect((await call("POST", "/v1/party", undefined, ana.token)).status).toBe(201);
    vi.restoreAllMocks();
    scriptCodes(6, ["BENSPP"]);
    expect((await call("POST", "/v1/party", undefined, ben.token)).status).toBe(201);
    const parties = await partyCount();

    vi.restoreAllMocks();
    const script = scriptCodes(6, ["BUSYPP"]);
    const r = await call("POST", "/v1/party", undefined, ben.token);
    expectError(r, 503, "unavailable");
    expect(script.draws()).toBe(21);
    expect(await partyCount()).toBe(parties);

    // The failed create happens before Ben leaves, so he is still hosting his own party.
    const still = await call("GET", "/v1/party", undefined, ben.token);
    expect(still.body.party.code).toBe("BENSPP");
    expect(still.body.party.host).toBe(ben.code);
  });
});
