/**
 * Operator endpoints under `/v1/admin/`: a full export for offsite backups and a point-in-time restore.
 *
 * They answer only to `Authorization: Bearer <ADMIN_TOKEN>`, a Worker secret of at least
 * MIN_ADMIN_TOKEN_LENGTH characters. Without such a secret they do not exist, and every refusal looks
 * like any unknown path (404), so a scan learns nothing about them. Failed attempts count toward the
 * caller's per-IP authentication failures like a bad user token.
 */
import { HttpError, int, readBody } from "./lib";

export interface AdminSecrets {
  ADMIN_TOKEN?: string;
}

/** Shorter secrets disable the admin endpoints: `openssl rand -hex 32` makes a 64-character one. */
export const MIN_ADMIN_TOKEN_LENGTH = 32;

/** Durable Object point-in-time recovery reaches back this far. */
export const RESTORE_WINDOW_S = 30 * 86_400;

export const RESTORE_FIELDS = ["at", "bookmark"] as const;

/** Bookmarks are opaque, but Cloudflare's are short strings of hex digits and dashes. */
const BOOKMARK_RE = /^[0-9a-f-]{1,256}$/i;

/** What to restore to: a unix time, or a bookmark such as the `undoBookmark` of an earlier restore. */
export type RestoreTarget = { at: number } | { bookmark: string };

/**
 * Whether `presented` is the configured admin token. Both sides are hashed first, so the comparison is
 * constant time over equal-length digests and leaks neither the token's length nor a matching prefix.
 */
export async function isAdminToken(presented: string | null, configured: string | undefined): Promise<boolean> {
  if (!configured || configured.length < MIN_ADMIN_TOKEN_LENGTH || !presented) return false;
  const digest = (s: string) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  const [a, b] = await Promise.all([digest(presented), digest(configured)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

/** Exactly one of `at` (within the recovery window, not in the future) or `bookmark`. */
export async function parseRestore(req: Request, now: number): Promise<RestoreTarget> {
  const body = await readBody(req, RESTORE_FIELDS);
  if ((body.at === undefined) === (body.bookmark === undefined)) {
    throw new HttpError(400, "invalid_field", "send exactly one of at or bookmark");
  }
  if (body.at !== undefined) return { at: int(body.at, "at", now - RESTORE_WINDOW_S, now) };
  if (typeof body.bookmark !== "string" || !BOOKMARK_RE.test(body.bookmark)) {
    throw new HttpError(400, "invalid_field", "invalid bookmark");
  }
  return { bookmark: body.bookmark };
}

/** Every application table, in a stable order; SQLite's and Cloudflare's internal tables are skipped. */
export function exportTables(sql: SqlStorage): Record<string, Record<string, SqlStorageValue>[]> {
  const names = sql.exec<{ name: string }>(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\' AND name NOT LIKE '\\_cf\\_%' ESCAPE '\\' ORDER BY name",
  ).toArray().map((r) => r.name);
  const tables: Record<string, Record<string, SqlStorageValue>[]> = {};
  for (const name of names) tables[name] = sql.exec(`SELECT * FROM "${name.replaceAll('"', '""')}"`).toArray();
  return tables;
}

export const notFound = () => new HttpError(404, "not_found", "not found");
