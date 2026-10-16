import { PartyError } from "../party/partyError";
import { VersionedJSON } from "../persistence/versionedJson";
import type { PetSave } from "../pets/petSave";
import type { Instant } from "../time";
import type { SyncClient } from "./syncClient";
import { SyncDocument, iso8601, parseISO8601 } from "./syncDocument";

/*
 * Port of SyncState, SyncSession, SyncLocalProgress, SyncOutcome and
 * SyncRound: one sync is pull, fold this device's progress in, merge, and
 * push when the merge added anything, pulling and merging again when
 * another device pushed in between (a `409` on `If-Match`). The merge never
 * loses progress, so retrying is always safe.
 */

/** Who is signed in on this device. The name is only what Apple shared once; it never leaves the device. */
export interface SyncSession {
  readonly name: string | undefined;
  readonly signedInAt: Instant;
}

export function syncSession(name: string | undefined, signedInAt: Instant): SyncSession {
  const trimmed = name?.trim() ?? "";
  return { name: trimmed === "" ? undefined : trimmed, signedInAt };
}

/** A new device id in the Mac's UUID form, made once per install. */
export function newSyncDeviceID(): string {
  return globalThis.crypto.randomUUID().toUpperCase();
}

/**
 * Port of SyncState: what one device remembers about syncing, saved beside
 * its pet: its device id (the key of its points tally), the account it last
 * synced with, and the document its pet save last adopted with its revision.
 */
export class SyncState {
  /** The stored format. Bump with a migration step when it changes. */
  static readonly schema = new VersionedJSON(1);

  readonly device: string;
  /** The friend code the adopted document belongs to; undefined before the first sync. */
  readonly account: string | undefined;
  readonly adopted: SyncDocument;
  readonly revision: number;
  readonly lastSyncedAt: Instant | undefined;
  /** Set while signed in; undefined when signed out, which keeps the rest. */
  readonly session: SyncSession | undefined;

  constructor(init: { device: string; account?: string; adopted?: SyncDocument; revision?: number; lastSyncedAt?: Instant; session?: SyncSession }) {
    this.device = init.device;
    this.account = init.account;
    this.adopted = init.adopted ?? SyncDocument.empty;
    this.revision = init.revision ?? 0;
    this.lastSyncedAt = init.lastSyncedAt;
    this.session = init.session;
  }

  with(changes: { adopted?: SyncDocument; revision?: number; lastSyncedAt?: Instant; session?: SyncSession | undefined }): SyncState {
    const session = "session" in changes ? changes.session : this.session;
    const lastSyncedAt = changes.lastSyncedAt ?? this.lastSyncedAt;
    return new SyncState({
      device: this.device,
      ...(this.account === undefined ? {} : { account: this.account }),
      adopted: changes.adopted ?? this.adopted,
      revision: changes.revision ?? this.revision,
      ...(lastSyncedAt === undefined ? {} : { lastSyncedAt }),
      ...(session === undefined ? {} : { session }),
    });
  }

  get isSignedIn(): boolean {
    return this.session !== undefined;
  }

  /** This state for syncing with `account`: unchanged for the account last synced, otherwise a fresh start keeping the device. */
  signedIn(account: string, session?: SyncSession): SyncState {
    const base = account === this.account ? this : new SyncState({ device: this.device, account });
    return session === undefined ? base : base.with({ session });
  }

  /** Signed out: the adopted document stays, so signing back in never counts this device's points twice. */
  signedOut(): SyncState {
    return this.with({ session: undefined });
  }

  /** After the account was deleted: nothing of it is kept but the device id. */
  forgettingAccount(): SyncState {
    return new SyncState({ device: this.device });
  }

  equals(other: SyncState): boolean {
    const sameSession =
      this.session === undefined || other.session === undefined
        ? this.session === other.session
        : this.session.name === other.session.name && this.session.signedInAt === other.session.signedInAt;
    return (
      this.device === other.device &&
      this.account === other.account &&
      this.adopted.equals(other.adopted) &&
      this.revision === other.revision &&
      this.lastSyncedAt === other.lastSyncedAt &&
      sameSession
    );
  }

  encoded(): string {
    return SyncState.schema.encode({
      device: this.device,
      ...(this.account === undefined ? {} : { account: this.account }),
      adopted: this.adopted.toJSON(),
      revision: this.revision,
      ...(this.lastSyncedAt === undefined ? {} : { lastSyncedAt: iso8601(this.lastSyncedAt) }),
      ...(this.session === undefined
        ? {}
        : { session: { ...(this.session.name === undefined ? {} : { name: this.session.name }), signedInAt: iso8601(this.session.signedInAt) } }),
    });
  }

  /** Throws when the text is not a state (no device), so the caller keeps the file instead of overwriting it. */
  static decode(text: string): SyncState {
    return SyncState.schema.decode(text, (object) => {
      if (typeof object.device !== "string") throw new SyntaxError("A sync state needs a device");
      const adopted = typeof object.adopted === "object" && object.adopted !== null && !Array.isArray(object.adopted)
        ? SyncDocument.fromJSON(object.adopted as Record<string, unknown>)
        : SyncDocument.empty;
      const lastSyncedAt = typeof object.lastSyncedAt === "string" ? parseISO8601(object.lastSyncedAt) : undefined;
      const rawSession = object.session;
      let session: SyncSession | undefined;
      if (typeof rawSession === "object" && rawSession !== null && !Array.isArray(rawSession)) {
        const fields = rawSession as Record<string, unknown>;
        const signedInAt = typeof fields.signedInAt === "string" ? parseISO8601(fields.signedInAt) : undefined;
        if (signedInAt !== undefined) session = syncSession(typeof fields.name === "string" ? fields.name : undefined, signedInAt);
      }
      return new SyncState({
        device: object.device,
        ...(typeof object.account === "string" ? { account: object.account } : {}),
        adopted,
        revision: typeof object.revision === "number" && Number.isInteger(object.revision) ? object.revision : 0,
        ...(lastSyncedAt === undefined ? {} : { lastSyncedAt }),
        ...(session === undefined ? {} : { session }),
      });
    });
  }
}

/** This device's progress at the start of a sync. */
export interface SyncLocalProgress {
  readonly save: PetSave;
  /** When the user last changed the pet's look here; undefined loses to any look another device chose. */
  readonly lookChangedAt?: Instant;
  /** Local days (`YYYY-MM-DD`) with focus time on this device. */
  readonly studyDays?: Iterable<string>;
}

/** When the local look counts as chosen: undefined while it is still the adopted one. */
export function lookChange(local: SyncLocalProgress, state: SyncState): Instant | undefined {
  const adopted = state.adopted.pet?.profile;
  if (adopted !== undefined && local.save.profile.equals(adopted)) return undefined;
  return local.lookChangedAt ?? 0;
}

/** The result of a sync: the merged document, the pet save to adopt, and the state to save for next time. */
export class SyncOutcome {
  constructor(
    readonly document: SyncDocument,
    readonly save: PetSave,
    readonly state: SyncState,
    /** False when the server already had everything this device had. */
    readonly pushed: boolean,
  ) {}

  /**
   * This outcome for a pet that changed while the round ran (`local`, with
   * `base` the state the round started from): the change goes on top of the
   * merged document. The server does not have it yet, so `pushed` is false.
   */
  folding(local: SyncLocalProgress, base: SyncState): SyncOutcome {
    const document = base.adopted
      .recording(local.save, lookChange(local, base), base.device)
      .merged(this.document)
      .addingStudyDays(local.studyDays ?? []);
    return new SyncOutcome(document, document.applied(local.save), this.state.with({ adopted: document }), false);
  }
}

/** Conflicts tolerated before giving up until the next sync. */
export const SYNC_MAX_ATTEMPTS = 3;

/** One sync round. Port of SyncRound.run. */
export async function runSyncRound(local: SyncLocalProgress, state: SyncState, client: SyncClient, now: Instant): Promise<SyncOutcome> {
  let mine = state.adopted.recording(local.save, lookChange(local, state), state.device).addingStudyDays(local.studyDays ?? []);
  for (let attempt = 1; ; attempt += 1) {
    const remote = await client.pull();
    const merged = mine.merged(remote.document ?? SyncDocument.empty);
    let revision = remote.revision;
    const changed = !merged.equals(remote.document);
    if (changed) {
      try {
        revision = await client.push(merged, remote.revision);
      } catch (error) {
        if (error instanceof PartyError && error.isRevisionConflict && attempt < SYNC_MAX_ATTEMPTS) {
          mine = merged;
          continue;
        }
        throw error;
      }
    }
    const next = state.with({ adopted: merged, revision, lastSyncedAt: now });
    return new SyncOutcome(merged, merged.applied(local.save), next, changed);
  }
}
