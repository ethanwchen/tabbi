/**
 * The total download count the website shows (`GET /v1/public/downloads`), counted without tracking
 * anyone: the app sends nothing for it. Two sources are added up:
 *
 * - GitHub's public `download_count` of every DMG attached to a published release. A DMG download is a
 *   new install (the website's `Tabbi.dmg`, the versioned `Tabbi-<version>.dmg` that Homebrew fetches).
 *   The update zip (`Tabbi-<version>.zip`) and `appcast.xml` are what Sparkle fetches on Macs that
 *   already have Tabbi, so they are left out and nobody is counted twice.
 * - The Mac App Store edition's units, which only App Store Connect knows. The maintainer sets the
 *   figure with `PUT /v1/admin/downloads/app-store`; it is stored per source, so an App Store Connect
 *   API pull can later write the same row (as source `app-store-connect`) without changing the reply.
 *
 * The website gets only a rounded milestone (`downloadMilestone`). The README's badge
 * (`GET /v1/public/downloads/badge`, `downloadsBadge`) shows the exact sum, which the maintainer chose
 * to make public from the first download.
 *
 * This module imports nothing, so `scripts/stats.ts` can run it with plain Node.
 */

export const DOWNLOADS_REPO = "ethanwchen/tabbi";

/** How long a GitHub count is reused; the public reply carries the rest of it as its max-age. */
export const DOWNLOADS_TTL_S = 6 * 3600;
/** After a failed GitHub fetch, the last good count is kept and GitHub is asked again this much later. */
export const DOWNLOADS_RETRY_S = 15 * 60;
/** Public download count requests per minute per client IP. */
export const DOWNLOADS_PER_MIN = 30;
/** Below this total the public reply's milestone is 0 and the website shows nothing. */
export const DOWNLOAD_MILESTONE_MIN = 10_000;
/** Release pages of 100 read at most, which bounds a refresh's subrequests. */
export const RELEASE_PAGES_MAX = 10;
/** The most App Store units the admin endpoint accepts. */
export const APP_STORE_UNITS_MAX = 1_000_000_000;

/** The parts of a GitHub release this module reads. */
export interface Release {
  tag_name: string;
  draft?: boolean;
  assets: { name: string; download_count: number }[];
}

export interface Downloads {
  /** DMG downloads over all published releases: new installs. */
  installs: number;
  /** Update zip downloads over all published releases: Sparkle updating an existing install. */
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

/** Every release of `repo`, following GitHub's pages of 100 (at most `maxPages` of them). */
export async function fetchReleases(
  repo: string, token?: string, fetcher: typeof fetch = fetch, maxPages = Infinity, timeoutMs?: number,
): Promise<Release[]> {
  const headers: Record<string, string> = { Accept: "application/vnd.github+json", "User-Agent": "tabbi-stats" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const releases: Release[] = [];
  for (let page = 1; page <= maxPages; page++) {
    const signal = timeoutMs === undefined ? undefined : AbortSignal.timeout(timeoutMs);
    const res = await fetcher(`https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}`, { headers, signal });
    if (!res.ok) throw new Error(`GitHub answered ${res.status} for ${repo}'s releases`);
    const batch = (await res.json()) as Release[];
    if (!Array.isArray(batch)) throw new Error(`GitHub sent no release list for ${repo}`);
    releases.push(...batch);
    if (batch.length < 100) break;
  }
  return releases;
}

/**
 * The public figure for a total: the largest step of 10,000, 25,000, 50,000, 100,000, 250,000 and so
 * on (1, 2.5 and 5 times a power of ten) that the total reaches, or 0 below DOWNLOAD_MILESTONE_MIN.
 */
export function downloadMilestone(total: number): number {
  if (!Number.isFinite(total) || total < DOWNLOAD_MILESTONE_MIN) return 0;
  let best = DOWNLOAD_MILESTONE_MIN;
  for (let power = DOWNLOAD_MILESTONE_MIN; power <= total; power *= 10) {
    for (const step of [1, 2.5, 5]) if (power * step <= total) best = power * step;
  }
  return best;
}

/** Where a stored count came from: set by hand, or (later) pulled from App Store Connect. */
export type CountOrigin = "manual" | "app-store-connect";

/** A count kept outside GitHub, as the `download_counts` table holds it. */
export interface StoredCount {
  units: number;
  origin: CountOrigin;
  updatedAt: number;
}

/** An optional Worker secret: any GitHub token (no scopes) lifts GitHub's 60 requests an hour per IP. */
export interface DownloadsSecrets {
  GITHUB_TOKEN?: string;
}

/** The README badge's shields.io endpoint JSON: the exact total, grouped like "1,234". */
export function downloadsBadge(total: number): { schemaVersion: 1; label: string; message: string; color: string; cacheSeconds: number } {
  const n = Number.isFinite(total) && total > 0 ? Math.floor(total) : 0;
  return { schemaVersion: 1, label: "downloads", message: n.toLocaleString("en-US"), color: "E8A15F", cacheSeconds: 3600 };
}

/** The public reply: the milestone only, and when the GitHub part was counted. */
export interface PublicDownloads {
  ok: true;
  milestone: number;
  at: number;
}
