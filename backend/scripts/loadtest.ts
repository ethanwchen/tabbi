/**
 * Load test for the Hub: simulates a population of Tabbi Party users against `wrangler dev` (never
 * production) and reports throughput, latency and the SQLite rows each request costs.
 *
 *   npx wrangler dev --port 8787 --var ADMIN_TOKEN:<64 hex>      # in one terminal
 *   TABBI_ADMIN_TOKEN=<same> node scripts/loadtest.ts --users 10000
 *
 * Setup registers the users (each from its own fake client IP, so per-IP limits do not apply), links
 * every user to `--friends` neighbors in both directions, and puts every tenth user in a party of
 * four. Then each stage sends the request mix of the peak hour (see PEAK_MODEL) at a multiple of its
 * rate for `--duration` seconds, open loop: requests leave on schedule whether or not earlier ones
 * have been answered, so a saturated Hub shows up as growing latency and shed requests.
 *
 * Options: --url (http://localhost:8787), --users (10000), --friends (3), --duration (30 s per stage),
 * --stages (1,2,4,8: multiples of the peak rate), --concurrency (64 setup requests in flight),
 * --max-in-flight (2000; a stage request is shed instead of sent beyond it), --json.
 * Without TABBI_ADMIN_TOKEN the row counts from GET /v1/admin/stats are left out.
 */

/** What the peak hour looks like, as shares of all registered users and per-user request intervals. */
export interface PeakModel {
  /** Share of users online in the busiest hour. */
  online: number;
  /** Share of online users studying or on a break (heartbeat every 120 s); the rest are idle (300 s). */
  studying: number;
  /** Share of online users with the Party panel open, which polls the friend list every 60 s. */
  panelOpen: number;
  /** Share of online users in a party; with the panel open the party is polled every 30 s. */
  inParty: number;
  /** Leaderboard loads per online user per hour. */
  leaderboardPerHour: number;
}

/**
 * Busy-hour assumptions: a third of all users online at once (students study in the same evening
 * hours), about half of them in a session, the Party panel open a tenth of the time.
 */
export const PEAK_MODEL: PeakModel = { online: 0.35, studying: 0.5, panelOpen: 0.1, inParty: 0.1, leaderboardPerHour: 1 };

export type Route = "heartbeat" | "friends" | "party" | "leaderboard";
export type Rates = Record<Route, number>;

/** Requests per second of each route in the peak hour for `users` registered users. */
export function peakRates(users: number, m: PeakModel = PEAK_MODEL): Rates {
  const online = users * m.online;
  return {
    heartbeat: online * (m.studying / 120 + (1 - m.studying) / 300),
    friends: (online * m.panelOpen) / 60,
    party: (online * m.inParty * m.panelOpen) / 30,
    leaderboard: (online * m.leaderboardPerHour) / 3600,
  };
}

export const totalRate = (r: Rates) => Object.values(r).reduce((a, b) => a + b, 0);

/** A distinct private client IP per simulated user, so each one gets its own per-IP limits. */
export function fakeIp(i: number, firstOctet = 10): string {
  return `${firstOctet}.${(i >> 16) & 255}.${(i >> 8) & 255}.${i & 255}`;
}

/** The value at quantile `q` (0..1) of `sorted` ascending values, or 0 when there are none. */
export function percentile(sorted: number[], q: number): number {
  if (sorted.length === 0) return 0;
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(q * sorted.length) - 1))];
}

export interface Options {
  url: string;
  users: number;
  friends: number;
  duration: number;
  stages: number[];
  concurrency: number;
  maxInFlight: number;
  json: boolean;
  adminToken?: string;
  /** First octet of the fake client IPs; tests pick one their other requests do not use. */
  ipOctet: number;
}

export function parseArgs(argv: string[], env: Record<string, string | undefined> = {}): Options {
  const o: Options = {
    url: "http://localhost:8787", users: 10_000, friends: 3, duration: 30, stages: [1, 2, 4, 8],
    concurrency: 64, maxInFlight: 2000, json: false, adminToken: env.TABBI_ADMIN_TOKEN || undefined, ipOctet: 10,
  };
  const positive = (flag: string, v: string | undefined) => {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0) throw new Error(`${flag} needs a positive number`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === "--json") { o.json = true; continue; }
    const v = argv[++i];
    switch (flag) {
      case "--url": if (!v) throw new Error("--url needs a value"); o.url = v.replace(/\/+$/, ""); break;
      case "--users": o.users = Math.floor(positive(flag, v)); break;
      case "--friends": o.friends = Math.floor(Number(v)); if (!(o.friends >= 0)) throw new Error("--friends needs a number"); break;
      case "--duration": o.duration = positive(flag, v); break;
      case "--stages": o.stages = (v ?? "").split(",").map((s) => positive(flag, s)); break;
      case "--concurrency": o.concurrency = Math.floor(positive(flag, v)); break;
      case "--max-in-flight": o.maxInFlight = Math.floor(positive(flag, v)); break;
      default: throw new Error(`unknown option ${flag}`);
    }
  }
  if (o.users < 4) throw new Error("--users must be at least 4");
  if (/^https:\/\/tabbi-friends\./.test(o.url)) throw new Error("refusing to load-test production; point --url at wrangler dev");
  return o;
}

interface User { token: string; code: string; ip: string; studying: boolean; party: boolean }

/** SQLite use of the Hub since it started, from GET /v1/admin/stats. */
interface HubUsage { requests: number; rowsRead: number; rowsWritten: number }

export interface StageResult {
  multiple: number;
  targetRps: number;
  sentRps: number;
  shed: number;
  /** Replies by HTTP status ("network" for a failed fetch). */
  statuses: Record<string, number>;
  latencyMs: { p50: number; p95: number; p99: number; max: number };
  perRoute: Record<Route, { sent: number; p95: number }>;
  /** Rows per Hub request during the stage, when the admin token was given. */
  rows: { readPerRequest: number; writtenPerRequest: number } | null;
}

export interface Report {
  users: number;
  friendsPerUser: number;
  parties: number;
  setup: { requests: number; seconds: number; failures: number };
  peak: Rates & { total: number };
  stages: StageResult[];
}

class Client {
  private o: Options;
  private fetcher: typeof fetch;

  // Plain fields, not parameter properties: Node runs this file by stripping types only.
  constructor(o: Options, fetcher: typeof fetch) {
    this.o = o;
    this.fetcher = fetcher;
  }

  async send(method: string, path: string, ip: string, token?: string, body?: unknown): Promise<{ status: number; body: any }> { // eslint-disable-line @typescript-eslint/no-explicit-any
    const headers: Record<string, string> = { "CF-Connecting-IP": ip };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    const res = await this.fetcher(this.o.url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    let parsed: unknown = null;
    try { parsed = text ? JSON.parse(text) : null; } catch { /* a non-JSON reply only matters through its status */ }
    return { status: res.status, body: parsed };
  }

  async usage(): Promise<HubUsage | null> {
    if (!this.o.adminToken) return null;
    const r = await this.send("GET", "/v1/admin/stats", "127.0.0.1", this.o.adminToken);
    if (r.status !== 200) throw new Error(`GET /v1/admin/stats answered ${r.status}; check TABBI_ADMIN_TOKEN`);
    return r.body.hub as HubUsage;
  }
}

/** Runs `jobs` with at most `limit` in flight; returns how many threw or answered outside 2xx. */
async function pool(jobs: (() => Promise<boolean>)[], limit: number): Promise<number> {
  let next = 0;
  let failures = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      try { if (!(await job())) failures++; } catch { failures++; }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, jobs.length) }, worker));
  return failures;
}

async function setup(c: Client, o: Options, log: (s: string) => void): Promise<{ users: User[]; parties: number; requests: number; failures: number }> {
  const users: User[] = [];
  let requests = 0;
  let failures = 0;
  log(`registering ${o.users} users`);
  failures += await pool(Array.from({ length: o.users }, (_, i) => async () => {
    requests++;
    const ip = fakeIp(i, o.ipOctet);
    // The default profile: numbered names would trip the name filter's leetspeak rules ("455").
    const r = await c.send("POST", "/v1/register", ip, undefined, {});
    if (r.status !== 201) return false;
    users[i] = { token: r.body.token, code: r.body.code, ip, studying: i % 2 === 0, party: false };
    return true;
  }), o.concurrency);
  const live = users.filter(Boolean);
  log(`linking ${o.friends} friends per user`);
  const adds: (() => Promise<boolean>)[] = [];
  for (let i = 0; i < live.length; i++) {
    for (let k = 1; k <= Math.min(o.friends, live.length - 1); k++) {
      const [a, b] = [live[i], live[(i + k) % live.length]];
      adds.push(async () => { requests++; return (await c.send("POST", "/v1/friends", a.ip, a.token, { code: b.code })).status === 200; });
    }
  }
  failures += await pool(adds, o.concurrency);
  log("forming parties");
  let parties = 0;
  const groups: User[][] = [];
  for (let i = 0; i + 3 < live.length; i += 40) groups.push(live.slice(i, i + 4));
  failures += await pool(groups.map((g) => async () => {
    requests++;
    const host = await c.send("POST", "/v1/party", g[0].ip, g[0].token);
    if (host.status !== 201) return false;
    parties++;
    g[0].party = true;
    for (const m of g.slice(1)) {
      requests++;
      const r = await c.send("POST", "/v1/party/join", m.ip, m.token, { code: host.body.party.code });
      if (r.status === 200) m.party = true;
    }
    return true;
  }), o.concurrency);
  return { users: live, parties, requests, failures };
}

/** The body of a heartbeat: studying users are in a 25-minute pomodoro that started at a fixed time. */
function heartbeatBody(u: User, epoch: number, now: number): Record<string, unknown> {
  if (!u.studying) return { status: "idle", todayMinutes: 30, streakDays: 3 };
  const phase = 1500;
  const ends = epoch + (Math.floor((now - epoch) / phase) + 1) * phase;
  return { status: "studying", method: "pomodoro", phaseEndsAt: ends, sessionMinutes: 10, todayMinutes: 60, streakDays: 3 };
}

async function runStage(c: Client, o: Options, users: User[], multiple: number, epoch: number): Promise<StageResult> {
  const rates = peakRates(users.length);
  const target = totalRate(rates) * multiple;
  const routes = Object.keys(rates) as Route[];
  const inParty = users.filter((u) => u.party);
  const latencies: number[] = [];
  const perRoute = Object.fromEntries(routes.map((r) => [r, [] as number[]])) as Record<Route, number[]>;
  const statuses: Record<string, number> = {};
  let inFlight = 0;
  let shed = 0;
  let sent = 0;
  const pick = (list: User[]) => list[Math.floor(Math.random() * list.length)];
  const before = await c.usage();
  const pending: Promise<void>[] = [];
  const start = performance.now();
  const end = start + o.duration * 1000;
  const interval = 1000 / target;
  let due = start;

  const fire = (route: Route) => {
    if (inFlight >= o.maxInFlight) { shed++; return; }
    const u = route === "party" && inParty.length > 0 ? pick(inParty) : pick(users);
    const now = Math.floor(Date.now() / 1000);
    const request = route === "heartbeat" ? c.send("POST", "/v1/presence", u.ip, u.token, heartbeatBody(u, epoch, now))
      : route === "friends" ? c.send("GET", "/v1/friends", u.ip, u.token)
      : route === "party" ? c.send("GET", "/v1/party", u.ip, u.token)
      : c.send("GET", "/v1/leaderboard", u.ip, u.token);
    const t0 = performance.now();
    inFlight++;
    sent++;
    pending.push(request.then(
      (r) => { statuses[r.status] = (statuses[r.status] ?? 0) + 1; },
      () => { statuses.network = (statuses.network ?? 0) + 1; },
    ).then(() => {
      const ms = performance.now() - t0;
      latencies.push(ms);
      perRoute[route].push(ms);
      inFlight--;
    }));
  };

  const weights = routes.map((r) => rates[r] / totalRate(rates));
  const choose = (): Route => {
    let x = Math.random();
    for (let i = 0; i < routes.length; i++) if ((x -= weights[i]) < 0) return routes[i];
    return routes[routes.length - 1];
  };
  while (performance.now() < end) {
    // Fire every request that is due, then yield; timers are too coarse for one request per tick.
    while (due <= performance.now() && due < end) { fire(choose()); due += interval; }
    await new Promise((r) => setTimeout(r, Math.max(1, Math.min(10, due - performance.now()))));
  }
  const elapsed = (performance.now() - start) / 1000;
  await Promise.all(pending);
  const after = await c.usage();
  // A stats call scans two tables, so its own rows are measured with a second call and taken out.
  const again = await c.usage();
  latencies.sort((a, b) => a - b);
  const hubRequests = before && after ? after.requests - before.requests - 1 : 0;
  return {
    multiple,
    targetRps: round(target),
    sentRps: round(sent / elapsed),
    shed,
    statuses,
    latencyMs: { p50: round(percentile(latencies, 0.5)), p95: round(percentile(latencies, 0.95)), p99: round(percentile(latencies, 0.99)), max: round(latencies.at(-1) ?? 0) },
    perRoute: Object.fromEntries(routes.map((r) => {
      const l = perRoute[r].sort((a, b) => a - b);
      return [r, { sent: l.length, p95: round(percentile(l, 0.95)) }];
    })) as StageResult["perRoute"],
    rows: before && after && again && hubRequests > 0
      ? {
        readPerRequest: round((after.rowsRead - before.rowsRead - (again.rowsRead - after.rowsRead)) / hubRequests),
        writtenPerRequest: round((after.rowsWritten - before.rowsWritten - (again.rowsWritten - after.rowsWritten)) / hubRequests),
      }
      : null,
  };
}

const round = (n: number) => Math.round(n * 100) / 100;

export async function loadTest(o: Options, fetcher: typeof fetch = fetch, log: (s: string) => void = () => {}): Promise<Report> {
  const c = new Client(o, fetcher);
  const health = await c.send("GET", "/v1/health", "127.0.0.1");
  if (health.status !== 200) throw new Error(`${o.url}/v1/health answered ${health.status}; is wrangler dev running?`);
  const t0 = performance.now();
  const s = await setup(c, o, log);
  const setupSeconds = (performance.now() - t0) / 1000;
  if (s.users.length < 4) throw new Error(`only ${s.users.length} users registered; is the Hub refusing registrations?`);
  // Everyone sends a first heartbeat, as the app does on launch, so stages measure steady state.
  const epoch = Math.floor(Date.now() / 1000);
  log("first heartbeats");
  s.failures += await pool(s.users.map((u) => async () =>
    (await c.send("POST", "/v1/presence", u.ip, u.token, heartbeatBody(u, epoch, epoch))).status === 200), o.concurrency);
  const stages: StageResult[] = [];
  for (const multiple of o.stages) {
    log(`stage x${multiple}: ${round(totalRate(peakRates(s.users.length)) * multiple)} req/s for ${o.duration} s`);
    stages.push(await runStage(c, o, s.users, multiple, epoch));
  }
  const peak = peakRates(s.users.length);
  return {
    users: s.users.length,
    friendsPerUser: 2 * Math.min(o.friends, s.users.length - 1),
    parties: s.parties,
    setup: { requests: s.requests, seconds: round(setupSeconds), failures: s.failures },
    peak: { ...(Object.fromEntries(Object.entries(peak).map(([k, v]) => [k, round(v)])) as Rates), total: round(totalRate(peak)) },
    stages,
  };
}

export function formatReport(r: Report): string {
  const lines = [
    `${r.users} users, ${r.friendsPerUser} friends each, ${r.parties} parties of 4`,
    `Setup: ${r.setup.requests} requests in ${r.setup.seconds} s (${round(r.setup.requests / Math.max(r.setup.seconds, 0.01))} req/s), ${r.setup.failures} failed`,
    `Peak hour: ${r.peak.total} req/s (heartbeats ${r.peak.heartbeat}, friend lists ${r.peak.friends}, party ${r.peak.party}, leaderboard ${r.peak.leaderboard})`,
    "",
    "stage  target/s  sent/s  shed  2xx%    p50 ms  p95 ms  p99 ms  rows read/req  rows written/req",
  ];
  for (const s of r.stages) {
    const total = Object.values(s.statuses).reduce((a, b) => a + b, 0);
    const ok = Object.entries(s.statuses).filter(([k]) => k.startsWith("2")).reduce((a, [, n]) => a + n, 0);
    lines.push([
      `x${s.multiple}`.padEnd(6), String(s.targetRps).padStart(8), String(s.sentRps).padStart(7), String(s.shed).padStart(5),
      `${total ? round((100 * ok) / total) : 0}`.padStart(6), String(s.latencyMs.p50).padStart(8), String(s.latencyMs.p95).padStart(7),
      String(s.latencyMs.p99).padStart(7), String(s.rows?.readPerRequest ?? "-").padStart(14), String(s.rows?.writtenPerRequest ?? "-").padStart(17),
    ].join(" "));
    const other = Object.entries(s.statuses).filter(([k]) => !k.startsWith("2"));
    if (other.length > 0) lines.push(`       non-2xx: ${other.map(([k, n]) => `${k} x${n}`).join(", ")}`);
  }
  return lines.join("\n");
}

declare const process: { argv: string[]; env: Record<string, string | undefined>; exitCode?: number };

if ((import.meta as { main?: boolean }).main) {
  try {
    const o = parseArgs(process.argv.slice(2), process.env);
    const report = await loadTest(o, fetch, (s) => { if (!o.json) console.log(s); });
    console.log(o.json ? JSON.stringify(report, null, 2) : "\n" + formatReport(report));
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    process.exitCode = 1;
  }
}
