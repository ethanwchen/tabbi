/*
 * Port of PartyServer: the friends server Tabbi talks to, and how a server
 * address typed in Settings (or given in development) is read.
 */

/** The deployed `tabbi-friends` Worker, used until the user enters another. */
export const PARTY_PRODUCTION_URL = "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev";
/** `npx wrangler dev` in `backend/`. */
export const PARTY_LOCAL_DEV_URL = "http://localhost:8787";

const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

function parseURL(text: string): URL | undefined {
  try {
    return new URL(text);
  } catch {
    return undefined;
  }
}

/**
 * Parses a server address typed in Settings. Accepts `https://` anywhere and
 * plain `http://` only for this PC, so a token never crosses the network
 * unencrypted. A missing scheme means `https://`. Returns the address as
 * typed (trimmed, without trailing slashes), or undefined when it can't be
 * used. An address with a user name or password is refused too, since the
 * host's HTTP refuses it.
 */
export function parsePartyServer(text: string): string | undefined {
  let trimmed = text.trim();
  if (trimmed === "") return undefined;
  if (!trimmed.includes("://")) trimmed = `https://${trimmed}`;
  while (trimmed.endsWith("/")) trimmed = trimmed.slice(0, -1);
  if (trimmed.includes("?") || trimmed.includes("#")) return undefined;
  const url = parseURL(trimmed);
  if (url === undefined || url.hostname === "" || url.username !== "" || url.password !== "") return undefined;
  switch (url.protocol) {
    case "https:":
      return trimmed;
    case "http:":
      return LOOPBACK_HOSTS.has(url.hostname.toLowerCase()) ? trimmed : undefined;
    default:
      return undefined;
  }
}

/**
 * The development override `TABBI_PARTY_SERVER`: plain-http loopback only,
 * so a development run can never register throwaway users on a deployed
 * server (the Mac's rule, and the host's `dev_worker_origin`).
 */
export function partyDevServer(text: string | undefined): string | undefined {
  if (text === undefined) return undefined;
  const server = parsePartyServer(text);
  if (server === undefined) return undefined;
  return parseURL(server)?.protocol === "http:" ? server : undefined;
}

/**
 * Port of PartyServer.identityKey: a stable key for a server address
 * (lower-cased scheme and host, port, and path without trailing slashes),
 * so `HTTPS://Host/` and `https://host` share one identity.
 */
export function partyIdentityKey(server: string): string {
  const url = parseURL(server);
  if (url === undefined) return server.trim().toLowerCase();
  const scheme = url.protocol.slice(0, -1).toLowerCase();
  const host = url.hostname.toLowerCase();
  const port = url.port === "" ? "" : `:${url.port}`;
  let path = url.pathname;
  while (path.endsWith("/")) path = path.slice(0, -1);
  return `${scheme}://${host}${port}${path}`;
}
