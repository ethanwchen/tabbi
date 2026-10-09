// The sync document: one per signed-in user, so a pet and its progress follow the user across Macs.
//
// The server stores the document as the app sends it and never merges: the app owns the format (a
// versioned `SyncDocument` with a `schemaVersion`) and the no-loss merge, so a new app version can add
// fields without a server deploy. The server only guards size, shape and the revision, which turns
// concurrent writes from two Macs into a 409 that the losing Mac resolves by pulling and merging.
import { HttpError, Obj, readBody } from "./lib";

/** A sync document is small (a pet, tallies per Mac, unlock ids, up to 400 study days). */
export const MAX_SYNC_BYTES = 64 * 1024;
/** Document writes per minute per user. The app debounces pushes, so this only stops a runaway client. */
export const SYNC_PUT_PER_MIN = 20;
export const SYNC_FIELDS = ["document"] as const;

/** Reads a PUT /v1/sync body: `{ document }`, a JSON object with a positive integer `schemaVersion`. */
export async function readSyncDocument(req: Request): Promise<Obj> {
  const body = await readBody(req, SYNC_FIELDS, MAX_SYNC_BYTES);
  const doc = body.document;
  if (typeof doc !== "object" || doc === null || Array.isArray(doc)) {
    throw new HttpError(400, "invalid_field", "invalid document");
  }
  const version = (doc as Obj).schemaVersion;
  if (typeof version !== "number" || !Number.isInteger(version) || version < 1) {
    throw new HttpError(400, "invalid_field", "invalid document schemaVersion");
  }
  return doc as Obj;
}

/**
 * The revision in an `If-Match` header: a non-negative integer, bare or as a quoted ETag (`"3"`).
 * Revision 0 means "there is no document yet". A missing header is 428, since a blind write could
 * drop another Mac's progress.
 */
export function parseIfMatch(header: string | null): number {
  if (header === null || header.trim() === "") {
    throw new HttpError(428, "revision_required", "send the revision you merged into as If-Match");
  }
  const m = /^(?:W\/)?"?(\d{1,15})"?$/.exec(header.trim());
  if (!m) throw new HttpError(400, "invalid_revision", "If-Match must be a revision number");
  return Number(m[1]);
}

export const etag = (revision: number) => `"${revision}"`;
