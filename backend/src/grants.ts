// Limited edition items the maintainer grants per account, such as the backwards cap for launch-week
// users. Grants are free: there is no purchase, payment or donation path anywhere in this service.
//
// The server stores only which user holds which item id. The app owns what an item looks like and
// fetches its grants with GET /v1/grants, which works for any friends token, so a signed-out Party
// identity gets its items as well as a signed-in account. Milestone items unlock in the app from the
// activity log; they are listed here too so a maintainer can grant one by hand to fix a lost unlock.
import limited from "../shared/limited-items.json";
import { HttpError, Obj, int, readBody } from "./lib";

/** The item ids a grant can name (`backend/shared/limited-items.json`, which the app's tests check). */
export const GRANTABLE_ITEMS: readonly string[] = limited.items.map((i) => i.id);

export const GRANT_FIELDS = ["item"] as const;
export const COHORT_FIELDS = ["item", "registeredFrom", "registeredUntil"] as const;

/** A limited edition item id, as in `accessory.backwardsCap`. */
export function parseGrantItem(v: unknown): string {
  if (typeof v !== "string" || !GRANTABLE_ITEMS.includes(v)) throw new HttpError(400, "invalid_field", "invalid item");
  return v;
}

/** POST /v1/admin/users/{code}/grants body: `{ item }`. */
export async function readGrant(req: Request): Promise<string> {
  return parseGrantItem((await readBody(req, GRANT_FIELDS)).item);
}

/** Everyone whose friend code was created in `[registeredFrom, registeredUntil)`, in unix seconds. */
export interface Cohort {
  item: string;
  registeredFrom: number;
  registeredUntil: number;
}

/** POST /v1/admin/grants body: an item and a registration window that has already started. */
export async function readCohort(req: Request, now: number): Promise<Cohort> {
  const body: Obj = await readBody(req, COHORT_FIELDS);
  const item = parseGrantItem(body.item);
  const registeredFrom = int(body.registeredFrom, "registeredFrom", 0, now);
  const registeredUntil = int(body.registeredUntil, "registeredUntil", 0, Number.MAX_SAFE_INTEGER);
  if (registeredUntil <= registeredFrom) throw new HttpError(400, "invalid_field", "registeredUntil must be after registeredFrom");
  return { item, registeredFrom, registeredUntil };
}
