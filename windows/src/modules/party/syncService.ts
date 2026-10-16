/*
 * Port of SyncStore: the optional Sign in with Apple account. It signs in
 * through the friends server's web flow (`core/sync/appleWebSignIn`), keeps
 * the pet in sync across the user's devices with `runSyncRound`, and signs
 * out or deletes the account.
 *
 * The account is the Party identity: signing in swaps the stored Party
 * credentials for the account's (so the same friend code and friends
 * follow the user to every device) and `identityChanged` tells Party to
 * reconnect. Rounds run on launch, about 30 s after progress changes (the
 * core's SyncSchedule), and once more when the module stops for quitting.
 * Everything works signed out exactly as without an account.
 *
 * Signing in opens Apple's page in the default browser; the friends server
 * sends the browser back to `tabbi://auth/apple?code=...`, which the host
 * hands to `receiveCallback`. Until it arrives the row says "Signing in"
 * with a way to cancel, since Windows cannot tell when the page closed.
 *
 * The progress synced comes from `SyncProgressSource`; until the Closet
 * port hands in its save, the pet's look is synced with an empty ledger,
 * which the merge treats as "nothing earned on this device" and never
 * loses anything from other devices.
 *
 * Demo and snapshot runs show a signed-in sample and never touch the
 * network, Credential Manager or the disk.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { Emitter, Store } from "../../app/store";
import { tr } from "../../core/localization/tr";
import { isEphemeral } from "../../core/modules/runMode";
import { ageStatus, type PartyAgeStatus } from "../../core/party/partyAgeCheck";
import { PartyClient } from "../../core/party/partyClient";
import { hostPartyCredentialStore, InMemoryPartyCredentialStore, type PartyCredentialStore } from "../../core/party/partyCredentialStore";
import { PartyError, partyErrorMessage } from "../../core/party/partyError";
import { hostPartyTransport, type PartyTransport } from "../../core/party/partyTransport";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { PetSave } from "../../core/pets/petSave";
import { PetSave as PetSaveClass } from "../../core/pets/petSave";
import { AppleWebSignIn, parseAppleCallback, webSignInFailureMessage } from "../../core/sync/appleWebSignIn";
import { SyncClient, type AppleSignInReply } from "../../core/sync/syncClient";
import { newSyncDeviceID, runSyncRound, SyncState, syncSession, type SyncLocalProgress } from "../../core/sync/syncRound";
import { SyncSchedule } from "../../core/sync/syncSchedule";
import type { Instant } from "../../core/time";
import { studyPet } from "../closet/closetServices";

/** What the Account row shows. */
export type SyncPhase = "signedOut" | "signingIn" | "signedIn" | "deleting";

export interface SyncServiceState {
  readonly phase: SyncPhase;
  /** The name Apple shared on the first sign-in on this PC, if any. */
  readonly name: string | undefined;
  readonly lastSyncedAt: Instant | undefined;
  readonly isSyncing: boolean;
  /** The last failure, in a sentence for the account row; undefined when fine. */
  readonly notice: string | undefined;
  /** Accounts are for people 13 and older, so signing in waits until the age check passed. */
  readonly ageStatus: PartyAgeStatus;
}

/** Where this device's progress comes from and where a merged save goes. */
export interface SyncProgressSource {
  progress(): SyncLocalProgress;
  adopt(save: PetSave): void;
  /** Calls `listener` after every local change worth a round. */
  subscribe(listener: () => void): () => void;
}

export interface SyncServiceDependencies {
  /** The friends server Party uses now. */
  readonly server: () => string | undefined;
  /** Where Party keeps its identity; the account replaces it. */
  readonly credentials: PartyCredentialStore;
  /** Where the age check's answer is kept, shared with Party. */
  readonly ageAnswer: { load(): Instant | undefined; save(eligible: Instant): void };
  readonly progress?: SyncProgressSource;
  /** Replaces the host's HTTP (tests). */
  readonly transport?: (server: string) => PartyTransport;
}

export const SYNC_FOLDER = "Sync";
export const SYNC_STATE_FILE = "state.json";

type Timer = ReturnType<typeof setTimeout> | undefined;

/** The pet's look with an empty ledger: what this device syncs until the Closet port hands in its save. */
function profileOnlyProgress(context: ModuleContext): SyncProgressSource {
  const pet = studyPet(context);
  return {
    progress: () => ({ save: new PetSaveClass(pet.state.profile), lookChangedAt: context.now() }),
    adopt: (save) => pet.setProfile(save.profile),
    subscribe: (listener) => pet.subscribe(listener),
  };
}

export class SyncService extends Store<SyncServiceState> {
  readonly isDemo: boolean;
  /** Sent after the stored Party credentials changed (sign in, sign out, delete), so Party reconnects with the new identity. */
  readonly identityChanged = new Emitter<void>();
  /** Sent with the eligible-from instant when the age question was answered before signing in, so Party adopts the same answer. */
  readonly ageAnswered = new Emitter<Instant>();
  private readonly documents: DocumentStore | undefined;
  private readonly progressSource: SyncProgressSource;
  private readonly schedule = new SyncSchedule();
  private state_: SyncState;
  /** Set when the state on disk could not be read: sync stays off and the file is never overwritten, so no points are counted twice. */
  private stateIsUnreadable = false;
  private loaded = false;
  private started = false;
  private syncedSave: PetSave | undefined;
  private syncAgain = false;
  private syncing = false;
  private generation = 0;
  private timer: Timer;
  private attempt: AppleWebSignIn | undefined;
  private stopFollowing: (() => void) | undefined;

  constructor(
    private readonly context: ModuleContext,
    private readonly deps: SyncServiceDependencies,
  ) {
    const ephemeral = isEphemeral(context.runMode);
    super({
      phase: ephemeral ? "signedIn" : "signedOut",
      name: ephemeral ? "Sam Rivera" : undefined,
      lastSyncedAt: ephemeral ? context.now() - 4 * 60 : undefined,
      isSyncing: false,
      notice: undefined,
      ageStatus: ephemeral ? { kind: "passed" } : ageStatus(deps.ageAnswer.load(), context.now()),
    });
    this.isDemo = ephemeral;
    this.progressSource = deps.progress ?? profileOnlyProgress(context);
    this.documents = ephemeral ? undefined : context.storage.folder(SYNC_FOLDER);
    this.state_ = ephemeral
      ? new SyncState({ device: "demo", account: "K7QW2MZD", session: syncSession("Sam Rivera", context.now()) })
      : new SyncState({ device: newSyncDeviceID() });
    if (!ephemeral) void this.load();
  }

  get isSignedIn(): boolean {
    return this.state_.isSignedIn;
  }

  private async load(): Promise<void> {
    const documents = this.documents;
    if (documents === undefined) return;
    try {
      const text = await documents.read(SYNC_STATE_FILE);
      if (text !== undefined) this.state_ = SyncState.decode(text);
    } catch (error) {
      this.context.logger.error("The sync state could not be read; sync stays off", error);
      this.stateIsUnreadable = true;
    }
    this.loaded = true;
    this.setState({ phase: this.state_.isSignedIn ? "signedIn" : "signedOut", name: this.state_.session?.name, lastSyncedAt: this.state_.lastSyncedAt });
    if (this.started) this.beginFollowing();
  }

  /* MARK: Lifecycle */

  /** Syncs now and from then on after pet changes. */
  start(): void {
    if (this.started) return;
    this.started = true;
    if (this.isDemo || !this.loaded) return;
    this.beginFollowing();
  }

  private beginFollowing(): void {
    this.stopFollowing?.();
    this.stopFollowing = this.progressSource.subscribe(() => this.progressDidChange());
    this.refreshAgeStatus();
    if (this.state_.isSignedIn) {
      this.schedule.launched(this.context.now());
      this.arm();
    }
  }

  /** The module stops (the app may be quitting): one last round for unsynced progress, best effort. */
  stop(): void {
    if (!this.started) return;
    this.started = false;
    this.stopFollowing?.();
    this.stopFollowing = undefined;
    globalThis.clearTimeout(this.timer);
    if (this.isDemo || !this.state_.isSignedIn || this.isTooYoung || this.stateIsUnreadable) return;
    if (!this.schedule.quitting()) return;
    const progress = this.progressSource.progress();
    const state = this.state_;
    const now = this.context.now();
    void this.client().then((client) => (client === undefined ? undefined : runSyncRound(progress, state, client, now))).catch(() => undefined);
  }

  /* MARK: Age check */

  /** Reads the answer again, since Party may have taken it meanwhile or the day the user turns 13 may have come. */
  refreshAgeStatus(): void {
    if (this.isDemo) return;
    this.setState({ ageStatus: ageStatus(this.deps.ageAnswer.load(), this.context.now()) });
    if (!this.isTooYoung || !this.state_.isSignedIn || this.state.phase !== "signedIn") return;
    /* Signed in and under 13: the server keeps nothing about an under-13 user. */
    this.cancelSync();
    void this.deleteAccount();
  }

  private get isTooYoung(): boolean {
    return this.state.ageStatus.kind === "tooYoung";
  }

  /** The age question asked before Sign in with Apple, once, as Party asks it. */
  answerAge(eligible: Instant): void {
    this.refreshAgeStatus();
    if (this.isDemo || this.state.ageStatus.kind !== "unanswered") return;
    this.deps.ageAnswer.save(eligible);
    this.setState({ ageStatus: ageStatus(eligible, this.context.now()) });
    this.ageAnswered.emit(eligible);
  }

  /* MARK: Account */

  /** Opens Apple's sign-in page in the browser and waits for the `tabbi://auth/apple` link. */
  async signInOnWeb(): Promise<void> {
    this.refreshAgeStatus();
    const server = this.deps.server();
    if (this.isDemo || this.state.phase !== "signedOut" || this.state.ageStatus.kind !== "passed" || server === undefined) return;
    this.setState({ notice: undefined, phase: "signingIn" });
    const attempt = await AppleWebSignIn.start();
    this.attempt = attempt;
    try {
      await this.context.host.openUrl(attempt.authorizeURL(server));
    } catch (error) {
      this.context.logger.error("Could not open Apple's sign-in page", error);
      this.attempt = undefined;
      this.setState({ phase: "signedOut", notice: tr("Couldn't sign in with Apple. Try again.") });
    }
  }

  /** The user gave up waiting for the browser. */
  cancelSignIn(): void {
    if (this.state.phase !== "signingIn") return;
    this.attempt = undefined;
    this.setState({ phase: "signedOut" });
  }

  /** A `tabbi://auth/apple` link the host received. Returns whether it belonged to this sign-in. */
  receiveCallback(url: string): boolean {
    const callback = parseAppleCallback(url);
    if (callback === undefined) return false;
    const attempt = this.attempt;
    if (attempt === undefined || this.state.phase !== "signingIn") return true;
    this.attempt = undefined;
    if (callback.kind === "failure") {
      this.setState({ phase: "signedOut", notice: webSignInFailureMessage(callback.failure) });
      return true;
    }
    this.setState({ phase: "signedOut" });
    void this.signIn((client) => client.exchangeWebSignIn(callback.code, attempt.state));
    return true;
  }

  /** Trades what Apple returned for the account through `exchange`, then stores its Party identity and syncs. */
  private async signIn(exchange: (client: SyncClient) => Promise<AppleSignInReply>): Promise<void> {
    const server = this.deps.server();
    if (this.isDemo || this.state.phase !== "signedOut" || this.state.ageStatus.kind !== "passed" || server === undefined) return;
    this.setState({ notice: undefined, phase: "signingIn" });
    try {
      const token = (await this.deps.credentials.load(server))?.token;
      const reply = await exchange(new SyncClient(this.transport(server), token));
      await this.deps.credentials.save(reply.credentials, server);
      this.state_ = this.state_.signedIn(reply.credentials.code, syncSession(this.state.name, this.context.now()));
      this.persist();
      this.setState({ name: this.state_.session?.name, lastSyncedAt: this.state_.lastSyncedAt, phase: "signedIn" });
      this.identityChanged.emit();
      this.schedule.launched(this.context.now());
      this.arm();
    } catch (error) {
      this.setState({ phase: "signedOut", notice: SyncService.message(error, true) });
    }
  }

  /** Signs out: this PC keeps its pet and progress, and Party goes back to an identity of its own. */
  signOut(): void {
    if (this.isDemo || !this.state_.isSignedIn) return;
    this.cancelSync();
    const server = this.deps.server();
    if (server !== undefined) {
      void this.deps.credentials
        .load(server)
        .then((credentials) => {
          if (credentials !== undefined) new SyncClient(this.transport(server), credentials.token).signOut().catch(() => undefined);
          return this.deps.credentials.delete(server);
        })
        .catch(() => undefined)
        .then(() => this.identityChanged.emit());
    }
    this.state_ = this.state_.signedOut();
    this.persist();
    this.settleSignedOut(server === undefined);
  }

  /** Deletes the account on the server and the Party identity here. The pet stays on this PC. */
  async deleteAccount(): Promise<void> {
    if (this.isDemo || !this.state_.isSignedIn || this.state.phase !== "signedIn") return;
    const server = this.deps.server();
    const token = server === undefined ? undefined : (await this.deps.credentials.load(server))?.token;
    if (server === undefined || token === undefined) {
      this.cancelSync();
      this.setState({ notice: tr("Couldn't reach your account from this PC. Email support@tabbinotch.com to delete it.") });
      return;
    }
    this.setState({ notice: undefined, phase: "deleting" });
    this.cancelSync();
    try {
      try {
        await new PartyClient(this.transport(server), token).deleteMe();
      } catch (error) {
        /* Already gone on the server. */
        if (!(error instanceof PartyError) || error.kind !== "unauthorized") throw error;
      }
      await this.deps.credentials.delete(server).catch(() => undefined);
      this.state_ = this.state_.forgettingAccount();
      this.persist();
      this.settleSignedOut(true);
    } catch (error) {
      this.setState({ phase: "signedIn", notice: SyncService.message(error, false) });
    }
  }

  /* MARK: Syncing */

  /** Syncs now, or right after the round already running. */
  syncNow(): void {
    if (this.isDemo || !this.state_.isSignedIn || this.isTooYoung || this.stateIsUnreadable) return;
    this.schedule.launched(this.context.now());
    this.arm();
  }

  private progressDidChange(): void {
    if (!this.state_.isSignedIn) return;
    const save = this.progressSource.progress().save;
    if (this.syncedSave !== undefined && SyncService.sameSave(save, this.syncedSave)) return;
    this.schedule.progressChanged(this.context.now());
    this.arm();
  }

  /** Wakes at the moment the schedule says a round is due. */
  private arm(): void {
    globalThis.clearTimeout(this.timer);
    const due = this.schedule.nextDue();
    if (due === undefined || !this.started) return;
    this.timer = globalThis.setTimeout(() => this.runIfDue(), Math.max(0, (due - this.context.now()) * 1000));
  }

  private runIfDue(): void {
    if (!this.schedule.isDue(this.context.now())) {
      this.arm();
      return;
    }
    if (this.syncing) {
      this.syncAgain = true;
      return;
    }
    void this.runRounds();
  }

  private async runRounds(): Promise<void> {
    const generation = (this.generation += 1);
    this.syncing = true;
    this.setState({ isSyncing: true });
    do {
      this.syncAgain = false;
      await this.runRound(generation);
    } while (this.syncAgain && generation === this.generation && this.state_.isSignedIn);
    if (generation !== this.generation) return;
    this.syncing = false;
    this.setState({ isSyncing: false });
    this.arm();
  }

  private async runRound(generation: number): Promise<void> {
    const client = await this.client();
    if (client === undefined || generation !== this.generation) return;
    const local = this.progressSource.progress();
    const base = this.state_;
    this.schedule.willSync();
    try {
      let outcome = await runSyncRound(local, base, client, this.context.now());
      if (generation !== this.generation || this.state_ !== base) return;
      const current = this.progressSource.progress();
      if (!SyncService.sameSave(current.save, local.save)) {
        /* The pet changed while the round ran: keep both, push again. */
        outcome = outcome.folding(current, base);
        this.syncAgain = true;
      }
      this.syncedSave = outcome.save;
      this.progressSource.adopt(outcome.save);
      this.state_ = outcome.state;
      this.persist();
      this.schedule.didSync();
      this.setState({ lastSyncedAt: this.state_.lastSyncedAt, notice: undefined });
    } catch (error) {
      if (generation !== this.generation) return;
      if (error instanceof PartyError && (error.isNoSyncAccount || error.kind === "unauthorized")) {
        /* The account was deleted on another device. */
        if (this.state_ !== base) return;
        const server = this.deps.server();
        if (server !== undefined) await this.deps.credentials.delete(server).catch(() => undefined);
        this.state_ = this.state_.forgettingAccount();
        this.persist();
        this.settleSignedOut(true);
        return;
      }
      const failure = error instanceof PartyError ? error : PartyError.transport("failed");
      this.schedule.didFail(failure, this.context.now());
      this.setState({ notice: SyncService.message(error, false) });
    }
  }

  /** A client with this device's token, or undefined without a server or token. */
  private async client(): Promise<SyncClient | undefined> {
    const server = this.deps.server();
    if (server === undefined) return undefined;
    const token = (await this.deps.credentials.load(server).catch(() => undefined))?.token;
    return token === undefined ? undefined : new SyncClient(this.transport(server), token);
  }

  private static sameSave(a: PetSave, b: PetSave): boolean {
    return a.encoded() === b.encoded();
  }

  private transport(server: string): PartyTransport {
    return this.deps.transport?.(server) ?? hostPartyTransport(server, (request) => this.context.host.httpRequest(request));
  }

  private cancelSync(): void {
    globalThis.clearTimeout(this.timer);
    this.generation += 1;
    this.syncAgain = false;
    this.syncing = false;
    this.setState({ isSyncing: false });
  }

  private settleSignedOut(announce: boolean): void {
    this.syncedSave = undefined;
    this.setState({ name: undefined, lastSyncedAt: undefined, phase: "signedOut" });
    if (announce) this.identityChanged.emit();
  }

  private persist(): void {
    if (this.documents === undefined || this.stateIsUnreadable) return;
    this.documents.write(SYNC_STATE_FILE, this.state_.encoded()).catch((error: unknown) => this.context.logger.error("Could not save the sync state", error));
  }

  private static message(error: unknown, signingIn: boolean): string {
    if (error instanceof PartyError) {
      if (error.isRejectedAppleSignIn) return tr("Apple didn't accept the sign-in. Try again.");
      if (error.isExpiredWebSignIn) return tr("The sign-in took too long. Try again.");
      return partyErrorMessage(error);
    }
    return signingIn ? tr("Couldn't sign in. Try again.") : tr("Couldn't reach the server. Try again.");
  }
}

const ACCOUNT_SYNC = serviceKey<SyncService>("sync.account");

/** The one Sign in with Apple account, made by the Party module with its server and credential store. */
export function accountSync(context: ModuleContext, make: () => SyncServiceDependencies): SyncService {
  return context.shared.resolve(ACCOUNT_SYNC, () => new SyncService(context, make()));
}

/** The credential store the account and Party share: Credential Manager, or memory in demo and snapshot runs. */
export function partyCredentialStore(context: ModuleContext): PartyCredentialStore {
  return context.shared.resolve(PARTY_CREDENTIALS, () => (isEphemeral(context.runMode) ? new InMemoryPartyCredentialStore() : hostPartyCredentialStore(context.host)));
}

const PARTY_CREDENTIALS = serviceKey<PartyCredentialStore>("party.credentials");
