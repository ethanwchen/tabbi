import { tr } from "../localization/tr";
import { PartyCode } from "../party/partyModels";
import { colorFromHex, colorHex, type PetColor } from "../pets/petPalette";
import { crestEmblem, crestFrame, crewCrestArt } from "./crewCrestArt";
import { CrewCode } from "./crewModels";

/*
 * Port of CrewCatalog and CrewInvite: the crest frame, emblem and color ids
 * and the limits. The ids and colors come from the crest art (the Mac's
 * crew.json, crewCrestArt.ts), and a test keeps them equal to the server's
 * backend/shared/crews.json. Ids are only ever added once shipped; an id
 * the app has no art for draws as the first one.
 */

export const CREW_CATALOG_VERSION = 1;

/** The frames, in picker order. */
export function crewFrames(): string[] {
  return crewCrestArt().frames.map((frame) => frame.id);
}

/** The emblems, in picker order. */
export function crewEmblems(): string[] {
  return crewCrestArt().emblems.map((emblem) => emblem.id);
}

export interface CrewColor {
  readonly id: string;
  /** The base tone the crest's frame takes. */
  readonly hex: string;
}

/** The crew colors, in picker order. */
export function crewColors(): CrewColor[] {
  const art = crewCrestArt();
  return art.colorIDs.flatMap((id) => {
    const tones = art.colors.get(id);
    return tones === undefined ? [] : [{ id, hex: colorHex(tones.base) }];
  });
}

/** A frame's name, for the builder's tooltips. */
export function crewFrameTitle(id: string): string {
  return tr(crestFrame(id).name);
}

/**
 * An emblem's name, for the builder's tooltips. Like a frame's, it is the
 * English name in crew.json translated through the string catalog, where
 * every name is a key, so a new emblem set is a data change; a name with no
 * entry reads in English.
 */
export function crewEmblemTitle(id: string): string {
  return tr(crestEmblem(id).name);
}

export const CREW_LIMITS = {
  nameMaxLength: 20,
  descriptionMaxLength: 120,
  maxMembers: 20,
  searchPageSize: 20,
  maxSessionsPerReport: 20,
  maxSessionMinutes: 720,
  dailyCapMinutes: 960,
  weeklyCapMinutes: 4800,
} as const;

export function crewPetColor(color: CrewColor): PetColor {
  const parsed = colorFromHex(color.hex);
  if (parsed === undefined) throw new Error(`bad crew color ${color.hex}`);
  return parsed;
}

/** The name the color picker's tooltip shows. */
export function crewColorTitle(color: CrewColor): string {
  switch (color.id) {
    case "coral":
      return tr("Coral");
    case "amber":
      return tr("Amber");
    case "mint":
      return tr("Mint");
    case "teal":
      return tr("Teal");
    case "sky":
      return tr("Sky");
    case "indigo":
      return tr("Indigo");
    case "violet":
      return tr("Violet");
    case "rose":
      return tr("Rose");
    case "slate":
      return tr("Slate");
    case "charcoal":
      return tr("Charcoal");
    default:
      return color.id;
  }
}

/** `id` if the app has art for it, else the first frame. */
export function resolvedCrewFrame(id: string): string {
  return crestFrame(id).id;
}

/** `id` if the app has art for it, else the first emblem. */
export function resolvedCrewEmblem(id: string): string {
  return crestEmblem(id).id;
}

/** The color for `id`, or the first color. */
export function resolvedCrewColor(id: string): CrewColor {
  const colors = crewColors();
  return colors.find((color) => color.id === id) ?? (colors[0] as CrewColor);
}

/* MARK: Invites */

export const CREW_INVITE_ACTION = "crew";
const SCHEME = "tabbi";
const WEB_HOST = "tabbinotch.com";

/**
 * The crew invite code in `url` (`tabbi://crew/<code>` or
 * `https://tabbinotch.com/crew/<code>`), parsed as strictly as Party links,
 * since links come from outside the app; undefined otherwise.
 */
export function parseCrewInvite(url: string): string | undefined {
  let parsed: URL;
  try {
    parsed = new URL(url.trim());
  } catch {
    return undefined;
  }
  const scheme = parsed.protocol.replace(/:$/, "").toLowerCase();
  const host = parsed.hostname.toLowerCase();
  let raw: string;
  if (scheme === SCHEME) {
    const path = parsed.pathname.split("/").filter((part) => part !== "");
    if (host !== CREW_INVITE_ACTION || path.length !== 1) return undefined;
    raw = path[0] ?? "";
  } else if (scheme === "https") {
    const path = parsed.pathname.split("/").filter((part) => part !== "");
    if ((host !== WEB_HOST && host !== `www.${WEB_HOST}`) || parsed.port !== "" || path.length !== 2 || path[0]?.toLowerCase() !== CREW_INVITE_ACTION) return undefined;
    raw = path[1] ?? "";
  } else {
    return undefined;
  }
  if (raw.includes("%")) return undefined;
  return CrewCode.invite(raw);
}

/** The link to share; the web page hands off to the app when it is installed. */
export function crewInviteWebURL(code: string): string {
  return `https://${WEB_HOST}/${CREW_INVITE_ACTION}/${code}`;
}

/** The link that opens Tabbi directly. */
export function crewInviteAppURL(code: string): string {
  return `${SCHEME}://${CREW_INVITE_ACTION}/${code}`;
}

/** The invite code in pasted text: a link, a link among words, or the code itself. Port of CrewCode.findInvite. */
export function findCrewInvite(text: string): string | undefined {
  const fromLink = parseCrewInvite(text.trim());
  if (fromLink !== undefined) return fromLink;
  for (const word of text.split(/\s+/)) {
    if (word === "") continue;
    const code = parseCrewInvite(word);
    if (code !== undefined) return code;
  }
  return PartyCode.find(text, CrewCode.inviteLength);
}
