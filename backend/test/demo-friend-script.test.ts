import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { DEMO_PROFILE, REVIEW_CREW_NAME, parseArgs, run, type Deps, type TokenStore } from "../scripts/demo-friend";
import { BASE, call, freshIp, register } from "./helpers";

/** The Worker, as the script reaches it, from a client IP of its own so no rate limit is shared. */
function worker(): typeof fetch {
  const ip = freshIp();
  return ((url: string, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    headers.set("CF-Connecting-IP", ip);
    return SELF.fetch(url, { ...init, headers });
  }) as typeof fetch;
}

/** A token file in memory. */
function memoryTokens(): TokenStore & { value: { token: string; code: string } | null } {
  const store = {
    value: null as { token: string; code: string } | null,
    async read() { return store.value; },
    async write(value: { token: string; code: string }) { store.value = value; },
    async remove() { store.value = null; },
  };
  return store;
}

function deps(tokens: TokenStore, lines: string[] = [], fetcher = worker()): Deps {
  let clock = Date.now();
  return {
    fetcher, tokens, log: (s) => lines.push(s),
    sleep: async (ms) => { clock += ms; },
    now: () => clock,
  };
}

const options = (command: string, ...extra: string[]) =>
  parseArgs([command, "--url", BASE, "--token-file", "/unused", ...extra]);

describe("parseArgs", () => {
  it("needs a command, the server and a token file", () => {
    expect(parseArgs(["create", "--url", "http://localhost:8787/", "--token-file", "t.json"]))
      .toEqual({ command: "create", url: "http://localhost:8787", tokenFile: "t.json", name: "Demo Friend", hours: 8, party: false, crew: false });
    expect(parseArgs(["study", "--url", "https://x.example", "--token-file", "t", "--hours", "48", "--party", "--crew"]))
      .toMatchObject({ command: "study", hours: 48, party: true, crew: true });
    expect(() => parseArgs(["make", "--url", "https://x.example", "--token-file", "t"])).toThrow(/first argument/);
    expect(() => parseArgs(["create", "--token-file", "t"])).toThrow(/--url/);
    expect(() => parseArgs(["create", "--url", "https://x.example"])).toThrow(/--token-file/);
    expect(() => parseArgs(["study", "--url", "https://x.example", "--token-file", "t", "--hours", "0"])).toThrow(/--hours/);
    expect(() => parseArgs(["create", "--url", "https://x.example", "--token-file", "t", "--bogus", "1"])).toThrow(/unknown option/);
  });
});

describe("the demo friend", () => {
  it("is created once, keeps its token out of the log, and shares only a name and a pet", async () => {
    const tokens = memoryTokens();
    const lines: string[] = [];
    await run(options("create"), deps(tokens, lines));
    const saved = tokens.value!;
    expect(saved.code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    expect(lines.join("\n")).toContain(saved.code);
    expect(lines.join("\n")).not.toContain(saved.token);
    const me = await call("GET", "/v1/me", undefined, saved.token, freshIp());
    expect(me.body.profile).toMatchObject({ name: "Demo Friend", petName: DEMO_PROFILE.petName, species: "cat" });
    await expect(run(options("create"), deps(tokens))).rejects.toThrow(/already holds/);
  });

  it("becomes a reviewer's friend at once, without anyone accepting, and can be reported and blocked", async () => {
    const tokens = memoryTokens();
    await run(options("create"), deps(tokens));
    const demo = tokens.value!;
    const reviewer = await register({ name: "Reviewer" });
    // The current app sends a friend request; the demo friend speaks protocol 1, so it is a friendship.
    const add = await call("POST", "/v1/friends", { code: demo.code }, reviewer.token, freshIp());
    expect(add.status).toBe(200);
    expect(add.body).toMatchObject({ added: true });
    const friends = await call("GET", "/v1/friends", undefined, reviewer.token, freshIp());
    expect(friends.body.friends.map((f: { profile: { code: string } }) => f.profile.code)).toEqual([demo.code]);
    const report = await call("POST", "/v1/reports", { code: demo.code, reason: "spam" }, reviewer.token, freshIp());
    expect(report.status).toBe(201);
    const block = await call("POST", "/v1/blocks", { code: demo.code }, reviewer.token, freshIp());
    expect(block.status).toBe(200);
    expect((await call("GET", "/v1/friends", undefined, reviewer.token, freshIp())).body.friends).toEqual([]);
  });

  it("studies for the given hours, hosts a party friends can join, then goes offline", async () => {
    const tokens = memoryTokens();
    await run(options("create"), deps(tokens));
    const demo = tokens.value!;
    const reviewer = await register({ name: "Reviewer" });
    await call("POST", "/v1/friends", { code: demo.code }, reviewer.token, freshIp());
    const lines: string[] = [];
    const study = deps(tokens, lines);
    let checked = false;
    const sleep = study.sleep;
    study.sleep = async (ms) => {
      if (!checked) {
        // While it studies, the reviewer sees it online in a party and joins through it.
        checked = true;
        const seen = (await call("GET", "/v1/friends", undefined, reviewer.token, freshIp())).body.friends[0];
        expect(seen).toMatchObject({ online: true, presence: { status: "studying" } });
        expect(seen.party?.size).toBe(1);
        const join = await call("POST", "/v1/party/join", { friend: demo.code }, reviewer.token, freshIp());
        expect(join.body).toMatchObject({ joined: true });
      }
      await sleep(ms);
    };
    await run(options("study", "--hours", "0.1", "--party"), study);
    expect(checked).toBe(true);
    expect(lines[0]).toMatch(/^Hosting party [A-Z0-9]{6}/);
    expect(lines.at(-1)).toMatch(/^Studied for 0.1 h \(\d+ heartbeats\), now offline\.$/);
    const after = (await call("GET", "/v1/friends", undefined, reviewer.token, freshIp())).body.friends[0];
    expect(after.online).toBe(false);
  });

  it("keeps a public review crew that a reviewer finds and joins, once", async () => {
    const tokens = memoryTokens();
    await run(options("create"), deps(tokens));
    const lines: string[] = [];
    await run(options("study", "--hours", "0.05", "--crew"), deps(tokens, lines));
    expect(lines[0]).toBe(`Created crew ${REVIEW_CREW_NAME}; reviewers find it in Find crews.`);
    await run(options("study", "--hours", "0.05", "--crew"), deps(tokens, lines));
    expect(lines.at(-2)).toBe(`In crew ${REVIEW_CREW_NAME}; reviewers find it in Find crews.`);
    const reviewer = await register({ name: "Reviewer" });
    const found = await call("GET", `/v1/crews?q=${encodeURIComponent("review crew")}`, undefined, reviewer.token, freshIp());
    const crew = found.body.crews.find((c: { name: string }) => c.name === REVIEW_CREW_NAME);
    expect(crew).toMatchObject({ visibility: "public", memberCount: 1 });
    // Joining a public crew asks its owner; the studying demo friend lets the reviewer in.
    const asked = await call("POST", "/v1/crews/join", { crew: crew.id }, reviewer.token, freshIp());
    expect(asked.body).toMatchObject({ joined: false, requested: true, crew: { memberCount: 1 } });
    await run(options("study", "--hours", "0.05", "--crew"), deps(tokens, lines));
    expect(lines).toContain("Let Reviewer into the crew.");
    const mine = await call("GET", "/v1/crews/mine", undefined, reviewer.token, freshIp());
    expect(mine.body.crew).toMatchObject({ name: REVIEW_CREW_NAME, memberCount: 2 });
    await run(options("delete"), deps(tokens));
  });

  it("deletes the account and the token file", async () => {
    const tokens = memoryTokens();
    await run(options("create"), deps(tokens));
    const token = tokens.value!.token;
    await run(options("delete"), deps(tokens));
    expect(tokens.value).toBeNull();
    expect((await call("GET", "/v1/me", undefined, token, freshIp())).status).toBe(401);
    await expect(run(options("show"), deps(tokens))).rejects.toThrow(/run create first/);
  });
});
