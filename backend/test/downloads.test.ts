import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  DOWNLOADS_PER_MIN, DOWNLOADS_REPO, DOWNLOADS_RETRY_S, DOWNLOADS_TTL_S, type Release, countDownloads, downloadMilestone, downloadsBadge,
} from "../src/downloads";
import { ADMIN_TOKEN, call, expectError, freshIp, pinClockToMinuteStart } from "./helpers";

const release = (tag: string, assets: [string, number][], draft = false): Release =>
  ({ tag_name: tag, draft, assets: assets.map(([name, download_count]) => ({ name, download_count })) });

const advance = (seconds: number) => vi.setSystemTime(Date.now() + seconds * 1000);
const RELEASES_URL = `https://api.github.com/repos/${DOWNLOADS_REPO}/releases?per_page=100&page=1`;

/** A fake GitHub releases API behind a `fetch` spy (the Hub runs in the test isolate). */
const github = {
  releases: [] as Release[],
  status: 200,
  calls: [] as { url: string; auth: string | null }[],
};

const publicDownloads = (ip = freshIp()) => call("GET", "/v1/public/downloads", undefined, undefined, ip);
const adminDownloads = () => call("GET", "/v1/admin/downloads", undefined, ADMIN_TOKEN, freshIp());
const setAppStore = (body: unknown, token: string | null = ADMIN_TOKEN) =>
  call("PUT", "/v1/admin/downloads/app-store", body, token ?? undefined, freshIp());

describe("downloadMilestone", () => {
  it("is 0 below 10,000, then the largest friendly step reached", () => {
    expect([0, 1, 9_999, Number.NaN, -5].map(downloadMilestone)).toEqual([0, 0, 0, 0, 0]);
    expect([10_000, 24_999, 25_000, 49_999, 50_000, 99_999].map(downloadMilestone))
      .toEqual([10_000, 10_000, 25_000, 25_000, 50_000, 50_000]);
    expect([100_000, 260_000, 999_999, 1_000_000, 3_000_000].map(downloadMilestone))
      .toEqual([100_000, 250_000, 500_000, 1_000_000, 2_500_000]);
  });
});

describe("countDownloads", () => {
  it("counts DMGs as installs and leaves Sparkle's zip and appcast out of them", () => {
    const d = countDownloads([
      release("v1.1.0", [["Tabbi-1.1.0.dmg", 40], ["Tabbi.dmg", 900], ["Tabbi-1.1.0.zip", 5000], ["appcast.xml", 90000], ["SHA256SUMS", 3]]),
      release("v1.2.0", [["Tabbi.dmg", 7]], true),
    ]);
    expect(d.installs).toBe(940);
    expect(d.updates).toBe(5000);
  });
});

describe("downloadsBadge", () => {
  it("shows the exact total, grouped, from zero", () => {
    expect(downloadsBadge(0)).toMatchObject({ schemaVersion: 1, label: "downloads", message: "0" });
    expect(downloadsBadge(1234567).message).toBe("1,234,567");
    expect([Number.NaN, -3, 12.9].map((n) => downloadsBadge(n).message)).toEqual(["0", "0", "12"]);
  });
});

describe("GET /v1/public/downloads", () => {
  let elapsed = 0;
  beforeEach(() => {
    pinClockToMinuteStart();
    // Each test starts far past the count the one before cached in the Hub's memory.
    elapsed += 10 * DOWNLOADS_TTL_S;
    advance(elapsed);
    github.releases = [release("v1.0.0", [["Tabbi.dmg", 6_000], ["Tabbi-1.0.0.dmg", 1_000], ["Tabbi-1.0.0.zip", 50_000]])];
    github.status = 200;
    github.calls = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = input instanceof Request ? input.url : String(input);
      github.calls.push({ url, auth: new Headers(init?.headers).get("Authorization") });
      if (url !== RELEASES_URL) throw new Error(`unexpected fetch ${url}`);
      return github.status === 200 ? Response.json(github.releases) : new Response("rate limited", { status: github.status });
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  // First in the file, while this Hub has never had an answer from GitHub.
  it("counts the App Store units alone until GitHub first answers, retrying soon", async () => {
    github.status = 500;
    await setAppStore({ units: 12_000 });
    const r = await publicDownloads();
    expect(r.status).toBe(200);
    expect(r.body.milestone).toBe(10_000);
    expect(r.headers.get("Cache-Control")).toBe(`public, max-age=${DOWNLOADS_RETRY_S}`);
    expect((await adminDownloads()).body).toMatchObject({ github: null, total: 12_000 });
    expect(github.calls).toHaveLength(1);
  });

  it("answers without a token with only the milestone, cacheable for hours", async () => {
    expect((await setAppStore({ units: 0 })).status).toBe(200);
    const r = await publicDownloads();
    expect(r.status).toBe(200);
    expect(Object.keys(r.body).sort()).toEqual(["at", "milestone", "ok"]);
    expect(r.body.milestone).toBe(0);
    expect(r.headers.get("Cache-Control")).toBe(`public, max-age=${DOWNLOADS_TTL_S}`);
    expect(r.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(github.calls.map((c) => c.url)).toEqual([RELEASES_URL]);
    expect(github.calls[0].auth).toBeNull();
  });

  it("gives the README badge the exact sum of installs and App Store units", async () => {
    await setAppStore({ units: 345 });
    const r = await call("GET", "/v1/public/downloads/badge", undefined, undefined, freshIp());
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ schemaVersion: 1, label: "downloads", message: "7,345" });
  });

  it("adds the App Store units to GitHub's installs and rounds the sum down", async () => {
    expect((await setAppStore({ units: 3_500 })).body.appStore).toMatchObject({ units: 3_500, origin: "manual" });
    expect((await publicDownloads()).body.milestone).toBe(10_000);
    expect((await setAppStore({ units: 20_000 })).status).toBe(200);
    expect((await publicDownloads()).body.milestone).toBe(25_000);
    const exact = await adminDownloads();
    expect(exact.status).toBe(200);
    expect(exact.body).toMatchObject({
      github: { installs: 7_000, updates: 50_000 }, appStore: { units: 20_000, origin: "manual" }, total: 27_000, milestone: 25_000,
    });
  });

  it("asks GitHub at most once per cache interval", async () => {
    await setAppStore({ units: 0 });
    await publicDownloads();
    github.releases = [release("v1.0.0", [["Tabbi.dmg", 30_000]])];
    advance(DOWNLOADS_TTL_S - 60);
    const cached = await publicDownloads();
    expect(cached.body.milestone).toBe(0);
    expect(cached.headers.get("Cache-Control")).toBe("public, max-age=60");
    expect(github.calls).toHaveLength(1);
    advance(60);
    expect((await publicDownloads()).body.milestone).toBe(25_000);
    expect(github.calls).toHaveLength(2);
  });

  it("keeps the last good count while GitHub fails, and tries again later", async () => {
    await setAppStore({ units: 5_000 });
    expect((await publicDownloads()).body.milestone).toBe(10_000);
    github.status = 403;
    advance(DOWNLOADS_TTL_S);
    const kept = await publicDownloads();
    expect(kept.status).toBe(200);
    expect(kept.body.milestone).toBe(10_000);
    expect(kept.headers.get("Cache-Control")).toBe(`public, max-age=${DOWNLOADS_RETRY_S}`);
    await publicDownloads();
    expect(github.calls).toHaveLength(2);
    github.status = 200;
    advance(DOWNLOADS_RETRY_S);
    await publicDownloads();
    expect(github.calls).toHaveLength(3);
  });

  it("is rate limited per client", async () => {
    const ip = freshIp();
    for (let i = 0; i < DOWNLOADS_PER_MIN; i++) expect((await publicDownloads(ip)).status).toBe(200);
    expectError(await publicDownloads(ip), 429, "rate_limited");
  });
});

describe("PUT /v1/admin/downloads/app-store", () => {
  it("looks like an unknown path without the admin token", async () => {
    for (const token of [null, "f".repeat(64)]) expectError(await setAppStore({ units: 1 }, token), 404, "not_found");
    expectError(await call("GET", "/v1/admin/downloads", undefined, undefined, freshIp()), 404, "not_found");
  });

  it("accepts only a whole number of units", async () => {
    for (const body of [{}, { units: -1 }, { units: 1.5 }, { units: "10" }, { units: 2_000_000_000 }]) {
      expectError(await setAppStore(body), 400, "invalid_field");
    }
    expectError(await setAppStore({ units: 1, origin: "app-store-connect" }), 400, "unknown_field");
  });
});
