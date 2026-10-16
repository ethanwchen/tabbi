import { partyIdentityKey } from "./partyServer";
import type { PartyRegistration } from "./partyModels";

/*
 * Port of PartyCredentials and PartyCredentialStore: what `POST
 * /v1/register` hands back that the app must keep (the secret bearer token
 * and the public friend code), one identity per friends server, so
 * switching servers never overwrites the identity on the other one.
 *
 * The store is injected. The app keeps it in Windows Credential Manager as
 * the generic credential `Tabbi/party` (`hostPartyCredentialStore`), never
 * in a file or a log; tests, demo and snapshot runs keep it in memory.
 */

export interface PartyCredentials {
  readonly token: string;
  readonly code: string;
}

export function credentialsOf(registration: PartyRegistration): PartyCredentials {
  return { token: registration.token, code: registration.code };
}

export function sameCredentials(a: PartyCredentials | undefined, b: PartyCredentials | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  return a.token === b.token && a.code === b.code;
}

export interface PartyCredentialStore {
  load(server: string): Promise<PartyCredentials | undefined>;
  save(credentials: PartyCredentials, server: string): Promise<void>;
  delete(server: string): Promise<void>;
}

/** Port of InMemoryPartyCredentialStore: for tests, demo mode and snapshots, which never touch Credential Manager. */
export class InMemoryPartyCredentialStore implements PartyCredentialStore {
  private readonly items = new Map<string, PartyCredentials>();

  constructor(items: Readonly<Record<string, PartyCredentials>> = {}) {
    for (const [server, credentials] of Object.entries(items)) this.items.set(partyIdentityKey(server), credentials);
  }

  async load(server: string): Promise<PartyCredentials | undefined> {
    return this.items.get(partyIdentityKey(server));
  }

  async save(credentials: PartyCredentials, server: string): Promise<void> {
    this.items.set(partyIdentityKey(server), credentials);
  }

  async delete(server: string): Promise<void> {
    this.items.delete(partyIdentityKey(server));
  }
}

/** The host's credential calls (src/host/host.ts), structurally. */
export interface HostCredentials {
  credentialGet(name: "party"): Promise<string | null>;
  credentialSet(name: "party", secret: string): Promise<void>;
  credentialDelete(name: "party"): Promise<boolean>;
}

/*
 * Credential Manager keeps a generic credential's secret to 2560 bytes; an
 * identity takes about 150, so this many fit with room to spare.
 */
const MAX_STORED_IDENTITIES = 8;

const TOKEN_PATTERN = /^[0-9a-f]{64}$/;

/** Reads the stored secret leniently: anything unreadable counts as no identities. */
export function parseStoredIdentities(secret: string | null): Map<string, PartyCredentials> {
  const identities = new Map<string, PartyCredentials>();
  if (secret === null) return identities;
  let parsed: unknown;
  try {
    parsed = JSON.parse(secret);
  } catch {
    return identities;
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return identities;
  for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof value !== "object" || value === null) continue;
    const { token, code } = value as Record<string, unknown>;
    if (typeof token === "string" && TOKEN_PATTERN.test(token) && typeof code === "string") identities.set(key, { token, code });
  }
  return identities;
}

/** The secret for a set of identities: JSON by identity key, newest last, capped. */
export function storedIdentitiesSecret(identities: ReadonlyMap<string, PartyCredentials>): string {
  const entries = [...identities.entries()].slice(-MAX_STORED_IDENTITIES);
  return JSON.stringify(Object.fromEntries(entries.map(([key, { token, code }]) => [key, { token, code }])));
}

/**
 * The real store: Credential Manager under `Tabbi/party`, holding each
 * server's identity by `partyIdentityKey`, so the production server and a
 * user's own server keep separate friend codes as on the Mac.
 */
export function hostPartyCredentialStore(host: HostCredentials): PartyCredentialStore {
  const readAll = async () => parseStoredIdentities(await host.credentialGet("party"));
  const writeAll = async (identities: Map<string, PartyCredentials>) => {
    if (identities.size === 0) await host.credentialDelete("party");
    else await host.credentialSet("party", storedIdentitiesSecret(identities));
  };
  return {
    async load(server) {
      return (await readAll()).get(partyIdentityKey(server));
    },
    async save(credentials, server) {
      const identities = await readAll();
      const key = partyIdentityKey(server);
      identities.delete(key);
      identities.set(key, { token: credentials.token, code: credentials.code });
      await writeAll(identities);
    },
    async delete(server) {
      const identities = await readAll();
      if (!identities.delete(partyIdentityKey(server))) return;
      await writeAll(identities);
    },
  };
}
