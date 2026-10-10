/**
 * Client end-to-end check: two simulated Tabbi users walk through the Party flow against a running
 * Worker (`wrangler dev`, never production), making the same requests the app makes, in its order.
 *
 *   npx wrangler dev --port 8787        # in one terminal
 *   npm run e2e                          # or: node scripts/e2e.ts --url http://localhost:8787
 *
 * Ana and Ben register, become friends, see each other online, study together in Ana's party (Ben
 * joins through her, Ana starts and ends a shared session), and then Ben blocks Ana, which must end
 * the friendship and the party and keep Ana from adding him again. Both accounts are deleted at the
 * end, even after a failed step, so repeated runs leave nothing behind.
 *
 * Options: --url (http://localhost:8787), --json. Exits 1 at the first step whose reply is wrong.
 */

export interface Options {
  url: string;
  json: boolean;
  /** First octet of the two fake client IPs; tests pick one their other requests do not use. */
  ipOctet: number;
}

export function parseArgs(argv: string[]): Options {
  const o: Options = { url: "http://localhost:8787", json: false, ipOctet: 10 };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--json") { o.json = true; continue; }
    if (flag === "--url") {
      const v = argv[++i];
      if (!v) throw new Error("--url needs a value");
      o.url = v.replace(/\/+$/, "");
      continue;
    }
    throw new Error(`unknown option ${flag}`);
  }
  if (/^https:\/\/tabbi-friends\./.test(o.url)) throw new Error("refusing to run against production; point --url at wrangler dev");
  return o;
}

interface Reply { status: number; body: any } // eslint-disable-line @typescript-eslint/no-explicit-any

interface User { name: string; ip: string; token: string; code: string }

export interface StepResult { name: string; ok: boolean; ms: number; error?: string }

export interface Report { ok: boolean; steps: StepResult[] }

/** Thrown by a step whose reply is not what the app expects; the message says what came back. */
class Mismatch extends Error {}

function expectReply(r: Reply, status: number, what: string): void {
  if (r.status !== status) throw new Mismatch(`${what}: expected ${status}, got ${r.status} ${JSON.stringify(r.body)}`);
}

function check(condition: boolean, what: string, got: unknown): void {
  if (!condition) throw new Mismatch(`${what}: got ${JSON.stringify(got)}`);
}

const codesOf = (list: { profile: { code: string } }[] | undefined) => (list ?? []).map((x) => x.profile.code).sort();
const sameCodes = (a: string[], b: string[]) => a.length === b.length && [...b].sort().every((c, i) => a[i] === c);

class Client {
  private url: string;
  private fetcher: typeof fetch;

  // Plain fields, not parameter properties: Node runs this file by stripping types only.
  constructor(url: string, fetcher: typeof fetch) {
    this.url = url;
    this.fetcher = fetcher;
  }

  async send(method: string, path: string, ip: string, token?: string, body?: unknown): Promise<Reply> {
    const headers: Record<string, string> = { "CF-Connecting-IP": ip };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    const res = await this.fetcher(this.url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let parsed: unknown = null;
    try { parsed = text ? JSON.parse(text) : null; } catch { parsed = text; }
    return { status: res.status, body: parsed };
  }

  as(u: User) {
    return {
      get: (path: string) => this.send("GET", path, u.ip, u.token),
      post: (path: string, body?: unknown) => this.send("POST", path, u.ip, u.token, body),
      patch: (path: string, body: unknown) => this.send("PATCH", path, u.ip, u.token, body),
      del: (path: string) => this.send("DELETE", path, u.ip, u.token),
    };
  }
}

/**
 * Runs the scenario and reports every step. It stops at the first failed step (later steps depend on
 * it) and always tries to delete both accounts.
 */
export async function runE2E(o: Options, fetcher: typeof fetch = fetch, log: (s: string) => void = () => {}): Promise<Report> {
  const c = new Client(o.url, fetcher);
  const steps: StepResult[] = [];
  const users: User[] = [];
  let failed = false;

  const step = async (name: string, body: () => Promise<void>) => {
    if (failed) return;
    const t0 = performance.now();
    try {
      await body();
      steps.push({ name, ok: true, ms: Math.round(performance.now() - t0) });
      log(`ok    ${name}`);
    } catch (e) {
      failed = true;
      const error = e instanceof Error ? e.message : String(e);
      steps.push({ name, ok: false, ms: Math.round(performance.now() - t0), error });
      log(`FAIL  ${name}: ${error}`);
    }
  };

  const now = () => Math.floor(Date.now() / 1000);
  let ana!: User;
  let ben!: User;
  let partyCode = "";
  const phaseEndsAt = now() + 25 * 60;

  await step("the Worker is up", async () => {
    expectReply(await c.send("GET", "/v1/health", "127.0.0.1"), 200, "GET /v1/health");
  });

  await step("Ana and Ben register", async () => {
    for (const [i, name] of ["Ana", "Ben"].entries()) {
      const ip = `${o.ipOctet}.250.0.${i + 1}`;
      const r = await c.send("POST", "/v1/register", ip, undefined, { name });
      expectReply(r, 201, `register ${name}`);
      check(/^[0-9a-f]{64}$/.test(r.body.token) && /^[A-HJ-NP-Z2-9]{8}$/.test(r.body.code), `${name}'s token and code`, r.body);
      users.push({ name, ip, token: r.body.token, code: r.body.code });
    }
    [ana, ben] = users;
    const me = await c.as(ana).get("/v1/me");
    expectReply(me, 200, "GET /v1/me");
    check(me.body.profile?.code === ana.code && me.body.profile?.name === "Ana", "Ana's profile", me.body);
  });

  await step("Ana adds Ben by his friend code, and both see the friendship", async () => {
    // The app normalizes a pasted code; the server must accept it lowercased with spaces too.
    const r = await c.as(ana).post("/v1/friends", { code: ` ${ben.code.toLowerCase()} ` });
    expectReply(r, 200, "POST /v1/friends");
    check(r.body.added === true && r.body.friend?.code === ben.code, "the added friend", r.body);
    const again = await c.as(ben).post("/v1/friends", { code: ana.code });
    expectReply(again, 200, "Ben adding Ana back");
    check(again.body.added === false, "adding an existing friend is a no-op", again.body);
    for (const [u, other] of [[ana, ben], [ben, ana]]) {
      const list = await c.as(u).get("/v1/friends");
      expectReply(list, 200, `${u.name}'s friends`);
      check(sameCodes(codesOf(list.body.friends), [other.code]), `${u.name}'s friend list`, list.body.friends);
    }
  });

  await step("Ana starts studying and Ben sees her online", async () => {
    const r = await c.as(ana).post("/v1/presence", { status: "studying", method: "pomodoro", phaseEndsAt, sessionMinutes: 0, todayMinutes: 25, streakDays: 2 });
    expectReply(r, 200, "Ana's heartbeat");
    check(typeof r.body.heartbeatSeconds === "number" && r.body.heartbeatSeconds > 0, "the heartbeat interval", r.body);
    const friend = (await c.as(ben).get("/v1/friends")).body.friends?.[0];
    check(friend?.online === true && friend?.presence?.status === "studying" && friend?.presence?.phaseEndsAt === phaseEndsAt, "Ana as Ben's friend", friend);
  });

  await step("Ana hosts a party and Ben joins through her", async () => {
    const created = await c.as(ana).post("/v1/party");
    expectReply(created, 201, "POST /v1/party");
    partyCode = created.body.party?.code;
    check(typeof partyCode === "string" && created.body.party.host === ana.code, "the new party", created.body);
    const seen = (await c.as(ben).get("/v1/friends")).body.friends?.[0]?.party;
    check(seen?.code === partyCode && seen?.size === 1, "Ana's party in Ben's friend list", seen);
    const join = await c.as(ben).post("/v1/party/join", { friend: ana.code });
    expectReply(join, 200, "Ben joining through Ana");
    check(join.body.joined === true && join.body.party?.code === partyCode, "Ben's join", join.body);
    const view = (await c.as(ana).get("/v1/party")).body.party;
    check(sameCodes(codesOf(view?.members), [ana.code, ben.code]), "the party members Ana sees", view);
  });

  await step("Ana starts a shared session and Ben follows it", async () => {
    const start = await c.as(ana).post("/v1/party/session", { method: "pomodoro", phaseEndsAt });
    expectReply(start, 200, "starting the session");
    const notHost = await c.as(ben).post("/v1/party/session", { method: "pomodoro", phaseEndsAt });
    expectReply(notHost, 403, "a guest starting a session");
    check(notHost.body?.error === "not_host", "the guest's error", notHost.body);
    const session = (await c.as(ben).get("/v1/party")).body.party?.session;
    check(session?.method === "pomodoro" && session?.phaseEndsAt === phaseEndsAt, "the session Ben sees", session);
  });

  await step("Ben studies along, and both show up studying", async () => {
    const r = await c.as(ben).post("/v1/presence", { status: "studying", method: "pomodoro", phaseEndsAt, sessionMinutes: 10, todayMinutes: 40, streakDays: 1 });
    expectReply(r, 200, "Ben's heartbeat");
    const member = (await c.as(ana).get("/v1/party")).body.party?.members?.find((m: { profile: { code: string } }) => m.profile.code === ben.code);
    check(member?.online === true && member?.presence?.status === "studying" && member?.presence?.sessionMinutes === 10, "Ben in Ana's party", member);
    const board = await c.as(ben).get("/v1/leaderboard");
    expectReply(board, 200, "GET /v1/leaderboard");
    check(sameCodes(codesOf(board.body.entries), [ana.code, ben.code]), "the leaderboard", board.body.entries);
  });

  await step("Ana ends the session and takes a break", async () => {
    expectReply(await c.as(ana).del("/v1/party/session"), 200, "ending the session");
    const party = (await c.as(ben).get("/v1/party")).body.party;
    check(party?.code === partyCode && party?.session === null, "the party after the session", party);
    expectReply(await c.as(ana).post("/v1/presence", { status: "break", method: "pomodoro", phaseEndsAt: now() + 300 }), 200, "Ana's break heartbeat");
    const friend = (await c.as(ben).get("/v1/friends")).body.friends?.[0];
    check(friend?.presence?.status === "break", "Ana on a break", friend);
  });

  await step("Ben blocks Ana: the friendship and the party end", async () => {
    const r = await c.as(ben).post("/v1/blocks", { code: ana.code });
    expectReply(r, 200, "POST /v1/blocks");
    check(r.body.blocked === true && r.body.block?.code === ana.code, "the block", r.body);
    for (const u of [ana, ben]) {
      const list = await c.as(u).get("/v1/friends");
      check(list.status === 200 && list.body.friends?.length === 0, `${u.name}'s friend list after the block`, list.body);
    }
    check((await c.as(ben).get("/v1/party")).body.party === null, "Ben out of the party", null);
    const party = (await c.as(ana).get("/v1/party")).body.party;
    check(sameCodes(codesOf(party?.members), [ana.code]), "Ana's party after the block", party);
    const blocks = (await c.as(ben).get("/v1/blocks")).body.blocks;
    check(blocks?.length === 1 && blocks[0].code === ana.code && blocks[0].name === "Ana", "Ben's block list", blocks);
  });

  await step("Ana cannot reach Ben again, and is not told why", async () => {
    // A blocked user's requests look like an unknown code or party, so the block is never revealed.
    const add = await c.as(ana).post("/v1/friends", { code: ben.code });
    expectReply(add, 404, "Ana adding Ben");
    check(add.body?.error === "unknown_code", "Ana's add error", add.body);
    const own = await c.as(ben).post("/v1/party");
    expectReply(own, 201, "Ben's own party");
    const join = await c.as(ana).post("/v1/party/join", { code: own.body.party.code });
    expectReply(join, 404, "Ana joining Ben's party");
    check(join.body?.error === "party_not_found", "Ana's join error", join.body);
    const report = await c.as(ana).post("/v1/reports", { code: ben.code, reason: "spam" });
    expectReply(report, 404, "Ana reporting Ben");
    const board = (await c.as(ana).get("/v1/leaderboard")).body.entries;
    check(sameCodes(codesOf(board), [ana.code]), "Ana's leaderboard", board);
  });

  await step("Ben unblocks Ana: no friendship comes back until one adds the other", async () => {
    const r = await c.as(ben).del(`/v1/blocks/${ana.code}`);
    check(r.status === 200 && r.body.unblocked === true, "the unblock", r.body);
    check((await c.as(ana).get("/v1/friends")).body.friends?.length === 0, "Ana's friends after the unblock", null);
    const add = await c.as(ana).post("/v1/friends", { code: ben.code });
    check(add.status === 200 && add.body.added === true, "Ana adding Ben again", add.body);
  });

  // Cleanup runs whatever happened, so a failed run against wrangler dev leaves no accounts behind.
  const cleanup = async () => {
    for (const u of users) expectReply(await c.as(u).del("/v1/me"), 200, `deleting ${u.name}`);
    if (ana) expectReply(await c.as(ana).get("/v1/me"), 401, "a deleted account's token");
  };
  if (failed) {
    try { await cleanup(); } catch { /* the failed step is what the report is about */ }
  } else {
    await step("both accounts are deleted", cleanup);
  }

  return { ok: !failed, steps };
}

export function formatReport(r: Report): string {
  const lines = r.steps.map((s) => `${s.ok ? "ok  " : "FAIL"}  ${s.name} (${s.ms} ms)${s.error ? `\n      ${s.error}` : ""}`);
  lines.push("", r.ok ? `All ${r.steps.length} steps passed.` : `Failed at step ${r.steps.length}: ${r.steps.at(-1)?.name}.`);
  return lines.join("\n");
}

declare const process: { argv: string[]; exitCode?: number };

if ((import.meta as { main?: boolean }).main) {
  try {
    const o = parseArgs(process.argv.slice(2));
    const report = await runE2E(o, fetch);
    console.log(o.json ? JSON.stringify(report, null, 2) : formatReport(report));
    if (!report.ok) process.exitCode = 1;
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    process.exitCode = 1;
  }
}
