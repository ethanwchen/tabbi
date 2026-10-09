import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { type Release, countDownloads, fetchReleases, fetchServiceStats, formatReport } from "../scripts/stats";
import { ADMIN_TOKEN, BASE } from "./helpers";

const release = (tag: string, assets: [string, number][], draft = false): Release =>
  ({ tag_name: tag, draft, assets: assets.map(([name, download_count]) => ({ name, download_count })) });

describe("countDownloads", () => {
  it("counts DMG downloads as installs and zips as updates, skipping drafts and other assets", () => {
    const d = countDownloads([
      release("v1.2.0", [["Tabbi-1.2.0.dmg", 40], ["Tabbi-1.2.0.zip", 300], ["appcast.xml", 999]]),
      release("v1.3.0-draft", [["Tabbi.dmg", 5]], true),
      release("v1.1.0", [["Tabbi-1.1.0.DMG", 60], ["Tabbi-1.1.0.zip", 10]]),
    ]);
    expect(d).toEqual({
      installs: 100,
      updates: 310,
      releases: [{ tag: "v1.2.0", installs: 40, updates: 300 }, { tag: "v1.1.0", installs: 60, updates: 10 }],
    });
  });
});

describe("fetchReleases", () => {
  it("follows pages until one is short, sending the token when given", async () => {
    const pages = [Array.from({ length: 100 }, (_, i) => release(`v${i}`, [])), [release("v-last", [])]];
    const seen: { url: string; auth: string | null }[] = [];
    const fetcher = (async (url: string, init?: RequestInit) => {
      seen.push({ url, auth: new Headers(init?.headers).get("Authorization") });
      return Response.json(pages[seen.length - 1]);
    }) as typeof fetch;
    const releases = await fetchReleases("owner/repo", "gh-token", fetcher);
    expect(releases).toHaveLength(101);
    expect(seen.map((s) => s.url)).toEqual([
      "https://api.github.com/repos/owner/repo/releases?per_page=100&page=1",
      "https://api.github.com/repos/owner/repo/releases?per_page=100&page=2",
    ]);
    expect(seen[0].auth).toBe("Bearer gh-token");
  });

  it("fails clearly when GitHub refuses", async () => {
    const fetcher = (async () => new Response("rate limited", { status: 403 })) as unknown as typeof fetch;
    await expect(fetchReleases("owner/repo", undefined, fetcher)).rejects.toThrow("GitHub answered 403");
  });
});

describe("fetchServiceStats", () => {
  const worker = ((url: string, init?: RequestInit) => SELF.fetch(url, init)) as typeof fetch;

  it("reads the admin stats route", async () => {
    const stats = (await fetchServiceStats(BASE + "/", ADMIN_TOKEN, worker)) as { ok: boolean; users: { total: number } };
    expect(stats.ok).toBe(true);
    expect(typeof stats.users.total).toBe("number");
  });

  it("explains a refused token", async () => {
    await expect(fetchServiceStats(BASE, "wrong".repeat(10), worker)).rejects.toThrow("TABBI_ADMIN_TOKEN");
  });
});

describe("formatReport", () => {
  const downloads = countDownloads([release("v1.0.0", [["Tabbi.dmg", 12], ["Tabbi.zip", 3]])]);

  it("summarizes installs and the service's counts", () => {
    const signups = Array.from({ length: 30 }, (_, i) => ({ day: `d${i}`, users: i >= 23 ? 2 : 1 }));
    const text = formatReport(downloads, {
      users: { total: 50, signedIn: 20, banned: 1 },
      active: { day: 9, week: 30, month: 45 },
      signups,
      parties: { open: 2, members: 5 },
      suggestions: 4,
    });
    expect(text).toContain("Installs (DMG downloads): 12");
    expect(text).toContain("v1.0.0: 12 installs, 3 updates");
    expect(text).toContain("Party users: 50 (20 signed in with Apple, 1 banned)");
    expect(text).toContain("Active users: 9 today, 30 this week, 45 this month");
    expect(text).toContain("New sign-ups: 2 today, 14 in the last 7 days");
  });

  it("says how to add the service's counts when there is no admin token", () => {
    expect(formatReport(downloads, null)).toContain("set TABBI_ADMIN_TOKEN");
  });
});
