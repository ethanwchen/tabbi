/**
 * The App Review demo friend: a Party account an App Store reviewer can add by its friend code, so Party's
 * friend, party, report and block steps can be tried by one person (docs/appstore.md, Notes for the reviewer).
 *
 *   node scripts/demo-friend.ts create --url <server> --token-file <file>   # once; prints the friend code
 *   node scripts/demo-friend.ts show   --url <server> --token-file <file>   # the code, name and friends
 *   node scripts/demo-friend.ts study  --url <server> --token-file <file> [--hours 48] [--party] [--crew]
 *   node scripts/demo-friend.ts delete --url <server> --token-file <file>
 *
 * The account registers and sends every request without a Tabbi-Protocol header, as a protocol 1 app does, so
 * a friend request to it becomes a friendship at once (docs/party-compatibility.md): nobody has to accept the
 * reviewer's request. It is an ordinary user in every other way: it shares only a name and a pet, the reviewer
 * can report it (the report reaches the moderation queue like any other) and block it (which ends the
 * friendship), and it never adds anyone itself.
 *
 * `study` keeps it online for the review: it heartbeats "studying" every two minutes and, with --party, hosts
 * a party the reviewer can join from their friend list. With --crew it also keeps a public Study Crew named
 * REVIEW_CREW_NAME (creating it the first time), reports each 25 minutes it studied there, and approves every
 * request to join it as soon as a heartbeat says one waits, so the reviewer finds the crew in Find crews, asks to
 * join, is let in within two minutes, and sees it on the weekly board. It stops by itself after --hours
 * (8 by default), or on Ctrl-C, sending a last "offline".
 *
 * The secret token goes only into --token-file (created with mode 0600, never printed): keep that file out of
 * the repository. `create` refuses to overwrite a token file, so an account is never lost by accident.
 */

export type Command = "create" | "show" | "study" | "delete";

export interface Options {
  command: Command;
  url: string;
  tokenFile: string;
  name: string;
  hours: number;
  party: boolean;
  crew: boolean;
}

/** The public crew the demo friend keeps for App Review with --crew. */
export const REVIEW_CREW_NAME = "Tabbi Review Crew";
/** How often, while studying with --crew, the demo friend reports a finished focus session. */
const CREW_SESSION_MS = 25 * 60_000;

const COMMANDS: readonly Command[] = ["create", "show", "study", "delete"];

export function parseArgs(argv: string[]): Options {
  const [command, ...rest] = argv;
  if (!COMMANDS.includes(command as Command)) throw new Error(`the first argument must be one of: ${COMMANDS.join(", ")}`);
  const o: Options = { command: command as Command, url: "", tokenFile: "", name: "Demo Friend", hours: 8, party: false, crew: false };
  for (let i = 0; i < rest.length; i++) {
    const flag = rest[i];
    if (flag === "--party") { o.party = true; continue; }
    if (flag === "--crew") { o.crew = true; continue; }
    const value = rest[++i];
    if (value === undefined) throw new Error(`${flag} needs a value`);
    if (flag === "--url") o.url = value.replace(/\/+$/, "");
    else if (flag === "--token-file") o.tokenFile = value;
    else if (flag === "--name") o.name = value;
    else if (flag === "--hours") {
      o.hours = Number(value);
      if (!Number.isFinite(o.hours) || o.hours <= 0 || o.hours > 24 * 14) throw new Error("--hours must be between 0 and 336");
    } else throw new Error(`unknown option ${flag}`);
  }
  if (!/^https?:\/\//.test(o.url)) throw new Error("--url must name the friends server (https://..., or http://localhost:8787)");
  if (!o.tokenFile) throw new Error("--token-file is required: the secret token is kept there, never printed");
  return o;
}

interface Reply { status: number; body: any } // eslint-disable-line @typescript-eslint/no-explicit-any

/** Where the token lives: a small JSON file the script reads and writes, injected so tests need no disk. */
export interface TokenStore {
  read(): Promise<{ token: string; code: string } | null>;
  write(value: { token: string; code: string }): Promise<void>;
  remove(): Promise<void>;
}

export interface Deps {
  fetcher: typeof fetch;
  tokens: TokenStore;
  log: (line: string) => void;
  /** Waits between heartbeats; tests pass one that returns at once. */
  sleep: (ms: number) => Promise<void>;
  now: () => number;
}

/** A demo pet: a cozy cat, nothing a reviewer could mistake for a real person's. */
export const DEMO_PROFILE = { petName: "Mochi", species: "cat" } as const;

async function send(d: Deps, o: Options, method: string, path: string, token?: string, body?: unknown): Promise<Reply> {
  // No Tabbi-Protocol header: the server files the account as protocol 1 (see the header comment).
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await d.fetcher(o.url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let parsed: unknown = null;
  try { parsed = text ? JSON.parse(text) : null; } catch { parsed = text; }
  return { status: res.status, body: parsed };
}

function expect(r: Reply, status: number, what: string): void {
  if (r.status !== status) throw new Error(`${what}: expected ${status}, got ${r.status} ${JSON.stringify(r.body)}`);
}

async function stored(d: Deps): Promise<{ token: string; code: string }> {
  const saved = await d.tokens.read();
  if (!saved) throw new Error("no demo friend in the token file yet; run create first");
  return saved;
}

export async function run(o: Options, d: Deps): Promise<void> {
  switch (o.command) {
    case "create": {
      if (await d.tokens.read()) throw new Error("the token file already holds a demo friend; delete it first or use another file");
      const r = await send(d, o, "POST", "/v1/register", undefined, { name: o.name, ...DEMO_PROFILE });
      expect(r, 201, "registering");
      await d.tokens.write({ token: r.body.token, code: r.body.code });
      d.log(`Created ${o.name}. Friend code for the reviewer notes: ${r.body.code}`);
      return;
    }
    case "show": {
      const { token } = await stored(d);
      const me = await send(d, o, "GET", "/v1/me", token);
      expect(me, 200, "GET /v1/me");
      const friends = await send(d, o, "GET", "/v1/friends", token);
      expect(friends, 200, "GET /v1/friends");
      d.log(`${me.body.profile.name} (${me.body.profile.code}), ${friends.body.friends.length} friends`);
      return;
    }
    case "study": {
      const { token } = await stored(d);
      if (o.party) {
        const party = await send(d, o, "POST", "/v1/party", token);
        expect(party, 201, "hosting a party");
        d.log(`Hosting party ${party.body.party.code}; friends see it in their list and can join.`);
      }
      if (o.crew) await joinReviewCrew(d, o, token);
      const end = d.now() + o.hours * 3600_000;
      let heartbeats = 0;
      let studiedSince = d.now();
      while (d.now() < end) {
        if (o.crew && d.now() - studiedSince >= CREW_SESSION_MS) {
          const start = Math.floor(studiedSince / 1000);
          const stop = Math.floor(d.now() / 1000);
          const r = await send(d, o, "POST", "/v1/crews/sessions", token,
            { sessions: [{ start, end: stop, minutes: Math.floor((stop - start) / 60) }] });
          expect(r, 200, "reporting a crew session");
          studiedSince = d.now();
        }
        const phaseEndsAt = Math.floor(d.now() / 1000) + 25 * 60;
        const r = await send(d, o, "POST", "/v1/presence", token,
          { status: "studying", method: "pomodoro", phaseEndsAt, sessionMinutes: 0, todayMinutes: 25, streakDays: 3 });
        expect(r, 200, "heartbeat");
        heartbeats += 1;
        if (o.crew && Number(r.body.crews?.requests) > 0) await approveRequests(d, o, token);
        await d.sleep(Math.max(30, Math.min(Number(r.body.heartbeatSeconds) || 120, 120)) * 1000);
      }
      expect(await send(d, o, "POST", "/v1/presence", token, { status: "offline" }), 200, "going offline");
      d.log(`Studied for ${o.hours} h (${heartbeats} heartbeats), now offline.`);
      return;
    }
    case "delete": {
      const { token } = await stored(d);
      expect(await send(d, o, "DELETE", "/v1/me", token), 200, "DELETE /v1/me");
      await d.tokens.remove();
      d.log("Deleted the demo friend and its token file.");
      return;
    }
  }
}

/**
 * Puts the demo friend in the public review crew: its own crew if it is in one already, otherwise a new crew
 * with REVIEW_CREW_NAME and the first frame, emblem and color of the server's crews catalog.
 */
async function joinReviewCrew(d: Deps, o: Options, token: string): Promise<void> {
  const mine = await send(d, o, "GET", "/v1/crews/mine", token);
  expect(mine, 200, "GET /v1/crews/mine");
  if (mine.body.crew) {
    d.log(`In crew ${mine.body.crew.name}; reviewers find it in Find crews.`);
    return;
  }
  const catalog = await send(d, o, "GET", "/v1/catalog");
  expect(catalog, 200, "GET /v1/catalog");
  const crews = catalog.body.crews;
  if (!crews) throw new Error("this server has no Study Crews (protocol 3) yet");
  const created = await send(d, o, "POST", "/v1/crews", token, {
    name: REVIEW_CREW_NAME, description: "The App Review demo crew. Join to see how crews work.",
    frame: crews.frames[0], emblem: crews.emblems[0], color: Object.keys(crews.colors)[0], visibility: "public",
  });
  expect(created, 201, "creating the review crew");
  d.log(`Created crew ${REVIEW_CREW_NAME}; reviewers find it in Find crews.`);
}

/** Lets in everyone waiting to join the review crew. */
async function approveRequests(d: Deps, o: Options, token: string): Promise<void> {
  const mine = await send(d, o, "GET", "/v1/crews/mine", token);
  expect(mine, 200, "GET /v1/crews/mine");
  for (const request of mine.body.crew?.requests ?? []) {
    const r = await send(d, o, "POST", `/v1/crews/mine/requests/${request.ref}/approve`, token);
    // Someone who joined another crew meanwhile, or a full crew, is skipped; nothing else should fail.
    if (r.status !== 409) expect(r, 200, "approving a request");
    if (r.status === 200) d.log(`Let ${request.name} into the crew.`);
  }
}

declare const process: { argv: string[]; exitCode?: number; on(event: string, listener: () => void): void; exit(code?: number): void };

/** The few file calls the command line needs; typed here, since the Worker build has no Node types. */
interface Files {
  readFile(path: string, encoding: "utf8"): Promise<string>;
  writeFile(path: string, data: string, options: { mode: number; flag: string }): Promise<void>;
  rm(path: string, options: { force: boolean }): Promise<void>;
}

if ((import.meta as { main?: boolean }).main) {
  const files = "node:fs/promises";
  const fs = (await import(files)) as Files;
  try {
    const o = parseArgs(process.argv.slice(2));
    const tokens: TokenStore = {
      async read() {
        try { return JSON.parse(await fs.readFile(o.tokenFile, "utf8")); } catch { return null; }
      },
      async write(value) { await fs.writeFile(o.tokenFile, JSON.stringify(value) + "\n", { mode: 0o600, flag: "wx" }); },
      async remove() { await fs.rm(o.tokenFile, { force: true }); },
    };
    if (o.command === "study") {
      // Ctrl-C sends the last heartbeat as offline, so friends don't see a stale "studying".
      process.on("SIGINT", () => {
        void (async () => {
          const saved = await tokens.read();
          if (saved) await fetch(o.url + "/v1/presence", {
            method: "POST", headers: { Authorization: `Bearer ${saved.token}`, "Content-Type": "application/json" },
            body: JSON.stringify({ status: "offline" }),
          }).catch(() => undefined);
          process.exit(0);
        })();
      });
    }
    await run(o, { fetcher: fetch, tokens, log: (s) => console.log(s), sleep: (ms) => new Promise((r) => setTimeout(r, ms)), now: () => Date.now() });
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    process.exitCode = 1;
  }
}
