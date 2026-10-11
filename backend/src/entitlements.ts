// Entitlements: what a Sign in with Apple account is entitled to, recorded once on the server so every
// Mac and both editions (App Store and direct download) honor it.
//
// Today the only entitlement is Founding Member, which the server records by itself for every account
// that signed in during the first 100 days after launch. It is free and permanent. The table is shaped
// for what may come later, an optional supporter tier bought through StoreKit (App Store edition) or a
// merchant of record (direct edition): such a purchase would be one more row with its store as `source`
// and the store's transaction id as `reference`. There are no purchase routes, prices or payment code
// here, and nothing is for sale.
//
// An entitlement can bring limited edition items (GET /v1/grants lists them with the maintainer's
// grants) and a badge that friends and party members see next to the user's name.
import catalog from "../shared/entitlements.json";
import { GRANTABLE_ITEMS } from "./grants";

/** One entitlement in `backend/shared/entitlements.json`. */
export interface EntitlementDefinition {
  id: string;
  /** Shown to others as a badge next to the user's name (friends list, party roster). */
  badge: boolean;
  /** Limited edition item ids the entitlement brings, which must be grantable items. */
  items: string[];
}

export const ENTITLEMENTS: readonly EntitlementDefinition[] = catalog.entitlements;

for (const e of ENTITLEMENTS) {
  for (const item of e.items) {
    if (!GRANTABLE_ITEMS.includes(item)) throw new Error(`entitlement ${e.id} brings unknown item ${item}`);
  }
}

/** The Founding Member entitlement: signed in with Apple within the founding window. */
export const FOUNDING = "founding";

/**
 * How an entitlement row came to be. `founding` is the server's own rule. A store purchase would add
 * its store here (for example `app-store` or `paddle`) together with the code that verifies it.
 */
export const ENTITLEMENT_SOURCES = ["founding"] as const;
export type EntitlementSource = (typeof ENTITLEMENT_SOURCES)[number];

/** The founding window lasts this long from the launch. */
export const FOUNDING_DAYS = 100;

export interface FoundingVars {
  /**
   * When Tabbi launched, as unix seconds or an ISO 8601 date ("2026-11-03" is midnight UTC). Unset, the
   * founding window has not started closing: every account counts as founding, beta accounts included.
   */
  FOUNDING_LAUNCH?: string;
}

/**
 * The end of the founding window in unix seconds: `null` while there is no end yet (FOUNDING_LAUNCH
 * unset), `-Infinity` for a value that cannot be read. An unreadable value grants nothing new, since a
 * founding grant is permanent and a typo must not hand it to everyone who signs in from then on.
 */
export function foundingEnd(vars: FoundingVars): number | null {
  const raw = vars.FOUNDING_LAUNCH?.trim();
  if (!raw) return null;
  let launch = NaN;
  if (/^\d{9,11}$/.test(raw)) launch = Number(raw);
  else if (/^\d{4}-\d{2}-\d{2}([T ][0-9:.]+(Z|[+-]\d{2}:?\d{2})?)?$/.test(raw)) launch = Date.parse(raw) / 1000;
  if (!Number.isFinite(launch)) return -Infinity;
  return Math.floor(launch) + FOUNDING_DAYS * 86_400;
}

/**
 * Whether an account that first signed in with Apple at `signedInAt` is a Founding Member: before the
 * end of the window, which also covers every account from before the launch.
 */
export function isFounding(signedInAt: number, end: number | null): boolean {
  return end === null || signedInAt < end;
}

/** The items the given entitlements bring, without duplicates, in catalog order. */
export function itemsOf(entitlements: readonly string[]): string[] {
  return ENTITLEMENTS.filter((e) => entitlements.includes(e.id)).flatMap((e) => e.items)
    .filter((item, i, all) => all.indexOf(item) === i);
}

/** The badges the given entitlements show to others, in catalog order. */
export function badgesOf(entitlements: readonly string[]): string[] {
  return ENTITLEMENTS.filter((e) => e.badge && entitlements.includes(e.id)).map((e) => e.id);
}
