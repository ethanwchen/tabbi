import { tr } from "../localization/tr";
import type { Instant } from "../time";
import type { PartyError } from "./partyError";
import type { PartyProfileUpdate } from "./partyModels";
import { MAX_REPORT_NOTE, type WireReportReason } from "./partyWire";

/*
 * Port of PartyModeration: blocks, reports, my standing and the support
 * contact, and which of my names the server refused.
 */

/** Port of PartyBlockedUser: someone I blocked, as `GET /v1/blocks` lists them. */
export interface PartyBlockedUser {
  readonly code: string;
  readonly name: string;
  readonly petName: string;
  /** When I blocked them; undefined in the reply to `POST /v1/blocks`. */
  readonly since: Instant | undefined;
}

/** Port of PartyReportReason; the values are the server's `reason` codes. */
export type PartyReportReason = WireReportReason;

export const PARTY_REPORT_REASONS: readonly PartyReportReason[] = ["inappropriate_name", "harassment", "spam", "other"];

/** The label in the reason picker. */
export function reportReasonTitle(reason: PartyReportReason): string {
  switch (reason) {
    case "inappropriate_name":
      return tr("Inappropriate name");
    case "harassment":
      return tr("Harassment");
    case "spam":
      return tr("Spam");
    case "other":
      return tr("Other");
  }
}

/** Port of PartyReport: a report about another user for `POST /v1/reports`. */
export interface PartyReport {
  readonly code: string;
  readonly reason: PartyReportReason;
  /** Optional; trimmed, and left out of the request when empty. */
  readonly note?: string;
}

/** The longest note the server keeps. */
export const REPORT_NOTE_LIMIT = MAX_REPORT_NOTE;

/**
 * The note as it is sent: trimmed, cut to the limit in characters, or
 * undefined when nothing is left, so a typed-in note never fails validation.
 */
export function reportSentNote(report: PartyReport): string | undefined {
  const trimmed = (report.note ?? "").trim();
  if (trimmed === "") return undefined;
  return [...trimmed].slice(0, REPORT_NOTE_LIMIT).join("");
}

/** Port of SupportContact: where people report a problem, abuse in Party included. */
export const SupportContact = {
  email: "support@tabbinotch.com",
  mailURL: "mailto:support@tabbinotch.com",
  termsURL: "https://tabbinotch.com/terms",
  privacyURL: "https://tabbinotch.com/privacy",
  /** The line Party options and Settings > About both show. */
  reportLine(): string {
    return tr("Report a problem: %@", SupportContact.email);
  },
} as const;

/**
 * Port of PartyNameRefusal: which of my names the friends server refused
 * (`name_not_allowed`, `pet_name_not_allowed`).
 */
export interface PartyNameRefusal {
  readonly name: boolean;
  readonly petName: boolean;
}

export const NO_REFUSAL: PartyNameRefusal = { name: false, petName: false };

/** The refusal an error stands for, or undefined for any other error. */
export function refusalOf(error: PartyError): PartyNameRefusal | undefined {
  if (error.kind === "nameNotAllowed") return { name: true, petName: false };
  if (error.kind === "petNameNotAllowed") return { name: false, petName: true };
  return undefined;
}

export function refusalUnion(a: PartyNameRefusal, b: PartyNameRefusal): PartyNameRefusal {
  return { name: a.name || b.name, petName: a.petName || b.petName };
}

/** Whether `a` already holds everything in `b`. */
export function refusalContains(a: PartyNameRefusal, b: PartyNameRefusal): boolean {
  return (a.name || !b.name) && (a.petName || !b.petName);
}

export function isEmptyRefusal(refusal: PartyNameRefusal): boolean {
  return !refusal.name && !refusal.petName;
}

/** The friendly line under the name, or undefined when nothing was refused. */
export function refusalMessage(refusal: PartyNameRefusal): string | undefined {
  if (refusal.name && refusal.petName) return tr("That name and your pet's name aren't allowed. Please pick others.");
  if (refusal.name) return tr("That name isn't allowed. Please pick another.");
  if (refusal.petName) return tr("Your pet's name isn't allowed. Rename your pet in the Closet.");
  return undefined;
}

/** The same update without the refused names, so the server keeps the ones it has. */
export function updateRemovingRefused(update: PartyProfileUpdate, refused: PartyNameRefusal): PartyProfileUpdate {
  const { name, petName, ...rest } = update;
  return {
    ...rest,
    ...(refused.name || name === undefined ? {} : { name }),
    ...(refused.petName || petName === undefined ? {} : { petName }),
  };
}
