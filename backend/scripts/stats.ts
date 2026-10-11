/**
 * The maintainer's numbers in one place: the service's aggregate counts from GET /v1/admin/stats, the
 * download counts GitHub keeps for each release asset (a DMG download is an install; the zip is what
 * Sparkle fetches for an update), and the App Store units and website total from GET
 * /v1/admin/downloads. Nothing here comes from the app.
 *
 *   TABBI_ADMIN_TOKEN=... node scripts/stats.ts            # a readable summary
 *   TABBI_ADMIN_TOKEN=... node scripts/stats.ts --json     # the same as JSON
 *
 * TABBI_BACKEND_URL overrides the production Worker, GITHUB_REPO the repository (owner/name), and an
 * optional GITHUB_TOKEN raises GitHub's limit of 60 unauthenticated requests per hour.
 * Without TABBI_ADMIN_TOKEN only the GitHub numbers are shown.
 */
import { DOWNLOADS_REPO, type Downloads, type StoredCount, countDownloads, fetchReleases } from "../src/downloads.ts";

export { type Downloads, type Release, countDownloads, fetchReleases } from "../src/downloads.ts";

export const DEFAULT_BACKEND_URL = "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev";
export const DEFAULT_REPO = DOWNLOADS_REPO;

/** GET /v1/admin/stats on `baseURL`. */
export async function fetchServiceStats(baseURL: string, adminToken: string, fetcher: typeof fetch = fetch): Promise<unknown> {
  const res = await fetcher(`${baseURL.replace(/\/+$/, "")}/v1/admin/stats`, { headers: { Authorization: `Bearer ${adminToken}` } });
  if (!res.ok) throw new Error(`the service answered ${res.status}; check TABBI_ADMIN_TOKEN and TABBI_BACKEND_URL`);
  return res.json();
}

/** What GET /v1/admin/downloads answers. */
export interface DownloadTotals {
  appStore: StoredCount | null;
  total: number;
  milestone: number;
}

/** GET /v1/admin/downloads on `baseURL`: the App Store units and the total behind the website's figure. */
export async function fetchDownloadTotals(baseURL: string, adminToken: string, fetcher: typeof fetch = fetch): Promise<DownloadTotals> {
  const res = await fetcher(`${baseURL.replace(/\/+$/, "")}/v1/admin/downloads`, { headers: { Authorization: `Bearer ${adminToken}` } });
  if (!res.ok) throw new Error(`the service answered ${res.status}; check TABBI_ADMIN_TOKEN and TABBI_BACKEND_URL`);
  return (await res.json()) as DownloadTotals;
}

interface ServiceStats {
  users: { total: number; signedIn: number; banned: number };
  active: { day: number; week: number; month: number };
  signups: { day: string; users: number }[];
  parties: { open: number; members: number };
  suggestions: number;
}

/** The plain-text report. */
export function formatReport(downloads: Downloads, service: ServiceStats | null, totals: DownloadTotals | null = null): string {
  const lines = [`Installs (DMG downloads): ${downloads.installs}`, `Update downloads: ${downloads.updates}`];
  for (const r of downloads.releases.slice(0, 5)) lines.push(`  ${r.tag}: ${r.installs} installs, ${r.updates} updates`);
  if (totals) {
    const store = totals.appStore;
    lines.push(
      store
        ? `App Store units: ${store.units} (${store.origin === "manual" ? "set by hand" : "from App Store Connect"} on ${new Date(store.updatedAt * 1000).toISOString().slice(0, 10)})`
        : "App Store units: not set (PUT /v1/admin/downloads/app-store)",
      `Website total: ${totals.total} (${totals.milestone ? `shows "${totals.milestone.toLocaleString("en-US")}+ downloads"` : "below 10,000, shows nothing"})`,
    );
  }
  if (!service) return [...lines, "", "Service counts skipped: set TABBI_ADMIN_TOKEN to include them."].join("\n");
  const week = service.signups.slice(-7).reduce((n, d) => n + d.users, 0);
  lines.push(
    "",
    `Party users: ${service.users.total} (${service.users.signedIn} signed in with Apple, ${service.users.banned} banned)`,
    `Active users: ${service.active.day} today, ${service.active.week} this week, ${service.active.month} this month`,
    `New sign-ups: ${service.signups.at(-1)?.users ?? 0} today, ${week} in the last 7 days`,
    `Open parties: ${service.parties.open} with ${service.parties.members} members`,
    `Suggestions waiting: ${service.suggestions}`,
  );
  return lines.join("\n");
}

declare const process: { env: Record<string, string | undefined>; argv: string[]; exitCode?: number };

async function main(): Promise<void> {
  const env = process.env;
  const downloads = countDownloads(await fetchReleases(env.GITHUB_REPO ?? DEFAULT_REPO, env.GITHUB_TOKEN));
  const backend = env.TABBI_BACKEND_URL ?? DEFAULT_BACKEND_URL;
  const service = env.TABBI_ADMIN_TOKEN ? (await fetchServiceStats(backend, env.TABBI_ADMIN_TOKEN)) as ServiceStats : null;
  const totals = env.TABBI_ADMIN_TOKEN ? await fetchDownloadTotals(backend, env.TABBI_ADMIN_TOKEN) : null;
  if (process.argv.includes("--json")) console.log(JSON.stringify({ downloads, totals, service }, null, 2));
  else console.log(formatReport(downloads, service, totals));
}

// Runs only as `node scripts/stats.ts`, not when a test imports it.
if ((import.meta as { main?: boolean }).main) {
  main().catch((e: unknown) => {
    console.error(e instanceof Error ? e.message : e);
    process.exitCode = 1;
  });
}
