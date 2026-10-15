import type { PetProfile } from "../pets/petProfile";
import { VersionedJSON } from "../persistence/versionedJson";
import { DISPLAY_NAME_MAX_LENGTH, cleanedDisplayName } from "../settings/displayName";
import type { Instant } from "../time";
import { tr } from "../localization/tr";
import { ageStatus, type PartyAgeStatus } from "./partyAgeCheck";
import type { PartyProfileUpdate } from "./partyModels";
import { updateRemovingRefused, type PartyNameRefusal } from "./partyModeration";
import { isNameAllowed } from "./partyNameFilter";
import { partyPetUpdate } from "./partyPetAppearance";
import { PARTY_PRODUCTION_URL, parsePartyServer, partyDevServer } from "./partyServer";

/*
 * Port of PartySettings: the user's Party preferences: which friends server
 * to use (the user-set custom server, blank for the default), the name
 * friends see, whether to go invisible, and the age check's answer.
 *
 * The secret token lives in the credential store, never here. The age
 * check's `ageEligibleFrom` stays on this PC and is never sent.
 */
export interface PartySettings {
  /** The server field as typed, so it round-trips. Blank means the default server. */
  readonly serverText: string;
  /** The name friends see. Blank keeps the server's current name. */
  readonly name: string;
  /** When on, heartbeats report `offline` while the user's own minutes keep counting locally. */
  readonly invisible: boolean;
  /** The moment the age check says this user is surely 13; undefined until it was answered. */
  readonly ageEligibleFrom: Instant | undefined;
}

/** The server name and pet name limit from the API contract. */
export const PARTY_MAX_NAME_LENGTH = DISPLAY_NAME_MAX_LENGTH;

export const DEFAULT_PARTY_SETTINGS: PartySettings = { serverText: "", name: "", invisible: false, ageEligibleFrom: undefined };

export function partySettings(fields: Partial<PartySettings> = {}): PartySettings {
  return { ...DEFAULT_PARTY_SETTINGS, ...fields };
}

/** Whether Party may connect at `now`. */
export function partyAgeStatus(settings: PartySettings, now: Instant): PartyAgeStatus {
  return ageStatus(settings.ageEligibleFrom, now);
}

/** True when the server field is blank, so the default server is used. */
export function usesDefaultServer(settings: PartySettings): boolean {
  return settings.serverText.trim() === "";
}

/**
 * The server to talk to, or undefined when the field holds something that
 * isn't usable. A development `TABBI_PARTY_SERVER` (plain-http loopback
 * only, `partyDevServer`) overrides the setting when given.
 */
export function partyServerURL(settings: PartySettings, devServer?: string): string | undefined {
  const dev = partyDevServer(devServer);
  if (dev !== undefined) return dev;
  return usesDefaultServer(settings) ? PARTY_PRODUCTION_URL : parsePartyServer(settings.serverText);
}

/** A one-line problem with the server field for Settings, or undefined when it is blank or valid. */
export function partyServerIssue(settings: PartySettings): string | undefined {
  if (usesDefaultServer(settings) || parsePartyServer(settings.serverText) !== undefined) return undefined;
  if (settings.serverText.trim().toLowerCase().startsWith("http://")) return tr("Use https:// (plain http:// only works for localhost).");
  return tr("Not a server address. Try https://your-server.example.");
}

/** The name as the server will store it, or undefined when nothing is left (the server keeps its name). */
export function cleanedPartyName(settings: PartySettings): string | undefined {
  return cleanedDisplayName(settings.name);
}

/** The names the server would refuse, known before any request. */
export function refusedNames(settings: PartySettings, pet: PetProfile): PartyNameRefusal {
  const name = cleanedPartyName(settings);
  return {
    name: name !== undefined && !isNameAllowed(name),
    petName: !isNameAllowed(pet.name),
  };
}

/**
 * The profile to sync: the cleaned name plus the pet's appearance, nothing
 * about cards, decks or study content. A name the filter rejects is left
 * out, since the server would refuse it.
 */
export function partyProfileUpdate(settings: PartySettings, pet: PetProfile): PartyProfileUpdate {
  const name = cleanedPartyName(settings);
  const update: PartyProfileUpdate = { ...partyPetUpdate(pet), ...(name === undefined ? {} : { name }) };
  return updateRemovingRefused(update, refusedNames(settings, pet));
}

/* MARK: Persistence */

/** The stored format: a versioned JSON document in the durable storage area. */
export const PARTY_SETTINGS_SCHEMA = new VersionedJSON(1);
/** The storage document name. */
export const PARTY_SETTINGS_DOCUMENT = "party/settings";

export function encodePartySettings(settings: PartySettings): string {
  return PARTY_SETTINGS_SCHEMA.encode({
    serverText: settings.serverText,
    name: settings.name,
    invisible: settings.invisible,
    ...(settings.ageEligibleFrom === undefined ? {} : { ageEligibleFrom: settings.ageEligibleFrom }),
  });
}

/** Missing or unreadable keys fall back to defaults, so adding a setting later never throws away the saved ones. */
export function decodePartySettings(text: string | undefined): PartySettings {
  if (text === undefined) return DEFAULT_PARTY_SETTINGS;
  try {
    return PARTY_SETTINGS_SCHEMA.decode(text, (object) => ({
      serverText: typeof object.serverText === "string" ? object.serverText : "",
      name: typeof object.name === "string" ? object.name : "",
      invisible: object.invisible === true,
      ageEligibleFrom: typeof object.ageEligibleFrom === "number" && Number.isFinite(object.ageEligibleFrom) ? object.ageEligibleFrom : undefined,
    }));
  } catch {
    return DEFAULT_PARTY_SETTINGS;
  }
}
