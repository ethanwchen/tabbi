/**
 * The maintainer's numbers in one place: the service's aggregate counts from GET /v1/admin/stats plus
 * the download counts GitHub keeps for each release asset (a DMG download is an install; the zip is
 * what Sparkle fetches for an update). Nothing here comes from the app.
 *
 *   TABBI_ADMIN_TOKEN=... node scripts/stats.ts            # a readable summary
 *   TABBI_ADMIN_TOKEN=... node scripts/stats.ts --json     # the same as JSON
 *
 * TABBI_BACKEND_URL overrides the production Worker, GITHUB_REPO the repository (owner/name), and an
 * optional GITHUB_TOKEN raises GitHub's limit of 60 unauthenticated requests per hour.
 * Without TABBI_ADMIN_TOKEN only the GitHub numbers are shown.
 */

export const DEFAULT_BACKEND_URL = "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev";
export const DEFAULT_REPO = "ethanwchen/tabbi";

/** The parts of a GitHub release this script reads. */
export interface Release {
  tag_name: string;
  draft?: boolean;
  assets: { name: string; download_count: number }[];
}

export interface Downloads {
  /** DMG downloads over all releases. */
  installs: number;
  /** Update zip downloads over all releases. */
  updates: number;
  /** Per release tag, newest first as GitHub lists them. */
  releases: { tag: string; installs: number; updates: number }[];
}

/** Sums DMG and zip downloads per release and overall; drafts and other assets are left out. */
export function countDownloads(releases: Release[]): Downloads {
  const sum = (r: Release, ext: string) =>
    r.assets.filter((a) => a.name.toLowerCase().endsWith(ext)).reduce((n, a) => n + a.download_count, 0);
  const rows = releases.filter((r) => !r.draft).map((r) => ({ tag: r.tag_name, installs: sum(r, ".dmg"), updates: sum(r, ".zip") }));
  return {
    installs: rows.reduce((n, r) => n + r.installs, 0),
    updates: rows.reduce((n, r) => n + r.updates, 0),
    releases: rows,
  };
}

/** Every release of `repo`, following GitHub's pages of 100. */
export async function fetchReleases(repo: string, token?: string, fetcher: typeof fetch = fetch): Promise<Release[]> {
  const headers: Record<string, string> = { Accept: "application/vnd.github+json", "User-Agent": "tabbi-stats" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const releases: Release[] = [];
  for (let page = 1; ; page++) {
    const res = await fetcher(`https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}`, { headers });
    if (!res.ok) throw new Error(`GitHub answered ${res.status} for ${repo}'s releases`);
    const batch = (await res.json()) as Release[];
    releases.push(...batch);
    if (batch.length < 100) return releases;
  }
}

/** GET /v1/admin/stats on `baseURL`. */
export async function fetchServiceStats(baseURL: string, adminToken: string, fetcher: typeof fetch = fetch): Promise<unknown> {
  const res = await fetcher(`${baseURL.replace(/\/+$/, "")}/v1/admin/stats`, { headers: { Authorization: `Bearer ${adminToken}` } });
  if (!res.ok) throw new Error(`the service answered ${res.status}; check TABBI_ADMIN_TOKEN and TABBI_BACKEND_URL`);
  return res.json();
}

interface ServiceStats {
  users: { total: number; signedIn: number; banned: number };
  active: { day: number; week: number; month: number };
  signups: { day: string; users: number }[];
  parties: { open: number; members: number };
  suggestions: number;
}

/** The plain-text report. */
export function formatReport(downloads: Downloads, service: ServiceStats | null): string {
  const lines = [`Installs (DMG downloads): ${downloads.installs}`, `Update downloads: ${downloads.updates}`];
  for (const r of downloads.releases.slice(0, 5)) lines.push(`  ${r.tag}: ${r.installs} installs, ${r.updates} updates`);
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
  const service = env.TABBI_ADMIN_TOKEN
    ? (await fetchServiceStats(env.TABBI_BACKEND_URL ?? DEFAULT_BACKEND_URL, env.TABBI_ADMIN_TOKEN)) as ServiceStats
    : null;
  if (process.argv.includes("--json")) console.log(JSON.stringify({ downloads, service }, null, 2));
  else console.log(formatReport(downloads, service));
}

// Runs only as `node scripts/stats.ts`, not when a test imports it.
if ((import.meta as { main?: boolean }).main) {
  main().catch((e: unknown) => {
    console.error(e instanceof Error ? e.message : e);
    process.exitCode = 1;
  });
}
