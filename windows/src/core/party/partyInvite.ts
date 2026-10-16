import { PartyCode } from "./partyModels";

/*
 * Port of PartyInvite: a Party invite link, a friend code to add or a party
 * code to join. People share the web form
 * (`https://tabbinotch.com/add/K7QW2MZD`), whose page hands off to the app
 * form (`tabbi://add/K7QW2MZD`) when Tabbi is installed. Both come from
 * outside the app, so parsing is strict: only these two hosts, these two
 * actions and a code that passes `PartyCode`.
 */

export type PartyInvite =
  | { readonly kind: "addFriend"; readonly code: string }
  | { readonly kind: "joinParty"; readonly code: string };

/** The app's URL scheme, registered per user by the installer. */
export const INVITE_SCHEME = "tabbi";
/** The website that serves the invite pages. */
export const INVITE_WEB_HOST = "tabbinotch.com";

const ACTIONS = { addFriend: "add", joinParty: "join" } as const;

/*
 * Splits a URL into scheme, host, port and percent-encoded path segments
 * without normalizing anything (WHATWG `URL` would decode or resolve parts
 * the Mac's `URLComponents` keeps as typed).
 */
function components(url: string): { scheme: string; host: string; port: string | undefined; path: string[] } | undefined {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)/.exec(url.trim());
  if (match === null) return undefined;
  const authority = match[2] ?? "";
  if (authority.includes("@")) return undefined;
  const portMatch = /^(.*?)(?::(\d*))?$/.exec(authority);
  return {
    scheme: (match[1] ?? "").toLowerCase(),
    host: (portMatch?.[1] ?? authority).toLowerCase(),
    port: portMatch?.[2],
    path: (match[3] ?? "").split("/").filter((segment) => segment.length > 0),
  };
}

/**
 * The invite in `url`, or undefined unless it is a well-formed invite with a
 * valid code. Codes are normalized (upper-cased, dashes dropped), so a
 * hand-typed `tabbi://add/k7qw-2mzd` works. Query and fragment are ignored.
 */
export function parseInvite(url: string): PartyInvite | undefined {
  const parts = components(url);
  if (parts === undefined) return undefined;
  let action: string;
  let rawCode: string;
  if (parts.scheme === INVITE_SCHEME) {
    /* tabbi://add/CODE: the action is the host. */
    if (parts.path.length !== 1) return undefined;
    action = parts.host;
    rawCode = parts.path[0] ?? "";
  } else if (parts.scheme === "https") {
    if (parts.host !== INVITE_WEB_HOST && parts.host !== `www.${INVITE_WEB_HOST}`) return undefined;
    if (parts.port !== undefined || parts.path.length !== 2) return undefined;
    action = (parts.path[0] ?? "").toLowerCase();
    rawCode = parts.path[1] ?? "";
  } else {
    return undefined;
  }
  /* A percent-encoded code is not one we hand out; reject rather than decode. */
  if (rawCode.includes("%")) return undefined;
  if (action === ACTIONS.addFriend) {
    const code = PartyCode.friendCode(rawCode);
    return code === undefined ? undefined : { kind: "addFriend", code };
  }
  if (action === ACTIONS.joinParty) {
    const code = PartyCode.partyCode(rawCode);
    return code === undefined ? undefined : { kind: "joinParty", code };
  }
  return undefined;
}

/** The link to share, which works whether or not the friend has Tabbi. */
export function inviteWebURL(invite: PartyInvite): string {
  return `https://${INVITE_WEB_HOST}/${ACTIONS[invite.kind]}/${invite.code}`;
}

/** The link that opens Tabbi directly. */
export function inviteAppURL(invite: PartyInvite): string {
  return `${INVITE_SCHEME}://${ACTIONS[invite.kind]}/${invite.code}`;
}

export function sameInvite(a: PartyInvite, b: PartyInvite): boolean {
  return a.kind === b.kind && a.code === b.code;
}
