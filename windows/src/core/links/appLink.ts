/**
 * A narrow stand-in for the Party area's PartyInvite, which the party port
 * owns: an invite link's action and its normalized code.
 */
export type PartyInvite =
  | { readonly kind: "addFriend"; readonly code: string }
  | { readonly kind: "joinParty"; readonly code: string };

/** Reads an invite from a link, or undefined; the party port provides the real parser. */
export type PartyInviteParser = (url: string) => PartyInvite | undefined;

/** The app's URL scheme. */
export const APP_LINK_SCHEME = "tabbi";

/** The host of the plain open link, `tabbi://open`. */
export const OPEN_LINK_HOST = "open";

/**
 * Port of AppLink: a link the app handles from its `tabbi://` scheme. Links
 * arrive from anywhere (a web page, a chat, a widget), so anything that
 * isn't exactly one of these is ignored.
 */
export type AppLink =
  /** `tabbi://open`: shows the panel. */
  | { readonly kind: "open" }
  /** A Party invite (`tabbi://add/<code>`, `tabbi://join/<code>` or their web links). */
  | { readonly kind: "invite"; readonly invite: PartyInvite };

/** The link in `url`, or undefined if Tabbi doesn't handle it. */
export function parseAppLink(url: string, parseInvite: PartyInviteParser = () => undefined): AppLink | undefined {
  const invite = parseInvite(url);
  if (invite) return { kind: "invite", invite };
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return undefined;
  }
  if (parsed.protocol.toLowerCase() !== `${APP_LINK_SCHEME}:`) return undefined;
  /* Only `scheme://host`: `tabbi:open` has no authority, so it is no link. */
  if (!/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(url)) return undefined;
  if (parsed.hostname.toLowerCase() !== OPEN_LINK_HOST) return undefined;
  if (![...parsed.pathname].every((char) => char === "/")) return undefined;
  return { kind: "open" };
}
