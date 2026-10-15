import type { Seconds } from "../time";
import { PartyClient } from "./partyClient";
import { credentialsOf, sameCredentials, type PartyCredentials, type PartyCredentialStore } from "./partyCredentialStore";
import { PartyError } from "./partyError";
import { sameProfileUpdate, type PartyProfile, type PartyProfileUpdate, type PartyRegistration } from "./partyModels";
import {
  NO_REFUSAL,
  refusalContains,
  refusalOf,
  refusalUnion,
  updateRemovingRefused,
  type PartyNameRefusal,
} from "./partyModeration";
import { forCatalogVersion1 } from "./partyPetAppearance";
import type { PartyTransport } from "./partyTransport";

/*
 * Port of PartyAccount: the user's identity on one friends server. It loads
 * the stored token or registers on first use, keeps the profile in sync,
 * and runs every other call with that token.
 *
 * The server only stores a token's hash, so an `unauthorized` reply means
 * the identity is gone for good. The account then drops the stored token,
 * registers again with the last profile it synced and retries the call
 * once, so the Party tab heals itself with a new friend code.
 *
 * Calls may overlap (a heartbeat while the panel refreshes), so a
 * registration in flight is shared: the account never registers twice.
 */
export class PartyAccount {
  readonly server: string;
  private readonly transport: PartyTransport;
  private readonly store: PartyCredentialStore;
  private readonly timeout: Seconds;

  /* Undefined until the store was read; then the identity, or null for none. */
  private loaded: PartyCredentials | null | undefined;
  private profileValue: PartyProfile | undefined;
  private refused: PartyNameRefusal = NO_REFUSAL;
  /* The profile last sent, reused when the identity must be recreated. */
  private desiredProfile: PartyProfileUpdate = {};
  private registering: Promise<PartyRegistration> | undefined;

  constructor(options: { server: string; transport: PartyTransport; credentials: PartyCredentialStore; timeout?: Seconds }) {
    this.server = options.server;
    this.transport = options.transport;
    this.store = options.credentials;
    this.timeout = options.timeout ?? 10;
  }

  /** The stored or newly registered identity; undefined before the first `connect` or after `deleteAccount`. */
  async credentials(): Promise<PartyCredentials | undefined> {
    if (this.loaded === undefined) {
      const stored = await this.store.load(this.server);
      /* A registration may have finished while the store was read; it wins. */
      if (this.loaded === undefined) this.loaded = stored ?? null;
    }
    return this.loaded ?? undefined;
  }

  /** The public friend code, once known. */
  async friendCode(): Promise<string | undefined> {
    return (await this.credentials())?.code;
  }

  /** The profile the server last returned. */
  get profile(): PartyProfile | undefined {
    return this.profileValue;
  }

  /** The names the server refused on the last successful `connect`. */
  get refusedNames(): PartyNameRefusal {
    return this.refused;
  }

  /**
   * Makes sure there is an identity and the server has `update`: registers
   * with it on first use, otherwise sends it with `PATCH /v1/me`.
   *
   * A refused name (`name_not_allowed`, `pet_name_not_allowed`) is left out
   * and the rest sent again, so a refused name never takes Party offline.
   * A self-hosted server still on catalog version 1 refuses newer ids as an
   * invalid field; the profile is then sent as that catalog takes it.
   */
  async connect(profile: PartyProfileUpdate): Promise<PartyProfile> {
    let update = profile;
    let refused: PartyNameRefusal = NO_REFUSAL;
    for (;;) {
      try {
        const synced = await this.sync(update);
        this.refused = refused;
        return synced;
      } catch (error) {
        if (!(error instanceof PartyError)) throw error;
        if (error.kind === "invalidRequest" && !sameProfileUpdate(forCatalogVersion1(update), update)) {
          update = forCatalogVersion1(update);
          continue;
        }
        const refusal = refusalOf(error);
        if (refusal === undefined || refusalContains(refused, refusal)) throw error;
        refused = refusalUnion(refused, refusal);
        update = updateRemovingRefused(update, refusal);
      }
    }
  }

  private async sync(update: PartyProfileUpdate): Promise<PartyProfile> {
    this.desiredProfile = update;
    if ((await this.credentials()) === undefined) {
      await this.register();
      if (this.profileValue !== undefined) return this.profileValue;
    }
    const standing = await this.perform((client) => client.updateStanding(update));
    this.profileValue = standing.profile;
    /* A banned user's calls still work, but Party has nothing left to offer them. */
    if (standing.banned) throw PartyError.of("banned");
    return standing.profile;
  }

  /**
   * Runs `call` with the current token, registering first when there is
   * none, and recovering once from `unauthorized` by registering again.
   */
  async perform<T>(call: (client: PartyClient) => Promise<T>): Promise<T> {
    const current = await this.identity();
    try {
      return await call(this.client(current.token));
    } catch (error) {
      if (!(error instanceof PartyError) || error.kind !== "unauthorized") throw error;
      if (sameCredentials(await this.credentials(), current)) {
        this.loaded = null;
        try {
          await this.store.delete(this.server);
        } catch {
          /* A stale stored token only costs a retry next launch. */
        }
      }
      const fresh = await this.identity();
      return call(this.client(fresh.token));
    }
  }

  /** `DELETE /v1/me`, then forgets the token, so the next `connect` starts over with a new friend code. */
  async deleteAccount(): Promise<void> {
    const credentials = await this.credentials();
    if (credentials !== undefined) {
      try {
        await this.client(credentials.token).deleteMe();
      } catch (error) {
        /* Already gone on the server; just forget it here. */
        if (!(error instanceof PartyError) || error.kind !== "unauthorized") throw error;
      }
    }
    this.loaded = null;
    this.profileValue = undefined;
    await this.store.delete(this.server);
  }

  /** `GET /v1/me`. */
  async refreshProfile(): Promise<PartyProfile> {
    const fresh = await this.perform((client) => client.me());
    this.profileValue = fresh;
    return fresh;
  }

  /** Replaces the identity, e.g. with the one Sign in with Apple returned, and stores it. */
  async adopt(credentials: PartyCredentials, profile?: PartyProfile): Promise<void> {
    this.loaded = credentials;
    if (profile !== undefined) this.profileValue = profile;
    await this.store.save(credentials, this.server);
  }

  private async identity(): Promise<PartyCredentials> {
    return (await this.credentials()) ?? this.register();
  }

  private async register(): Promise<PartyCredentials> {
    let task = this.registering;
    if (task === undefined) {
      task = this.client(undefined).register(this.desiredProfile);
      this.registering = task;
      const own = task;
      try {
        const registration = await own;
        const credentials = credentialsOf(registration);
        this.loaded = credentials;
        this.profileValue = registration.profile;
        try {
          await this.store.save(credentials, this.server);
        } catch {
          /* A lost credential write only costs a new code on the next launch. */
        }
        return credentials;
      } finally {
        if (this.registering === own) this.registering = undefined;
      }
    }
    return credentialsOf(await task);
  }

  private client(token: string | undefined): PartyClient {
    return new PartyClient(this.transport, token, this.timeout);
  }
}
