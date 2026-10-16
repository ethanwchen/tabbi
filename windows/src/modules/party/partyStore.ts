/*
 * Port of PartyStore: the Party tab's connection to the friends server. It
 * keeps my profile and presence in sync, refreshes friends and the party
 * while the panel is open, and runs the panel's actions.
 *
 * All timing follows the backend's polling guidance through the core
 * types: `PartyPresenceTracker` decides when the shared focus clock is
 * worth a heartbeat, `PartyHeartbeatSchedule` when the next one is due or
 * how long to back off, and `PartyRefreshPlan` when friends and the party
 * are fetched (never while the panel is hidden). Heartbeats stop after an
 * `offline` one, which is sent when going invisible and when the module
 * stops or the app quits.
 *
 * The party state itself is the one the Timer tab and the closed island
 * read too (`partyState` in partyServices.ts); every change replaces it
 * with a changed clone, the Swift struct's value semantics.
 *
 * Demo and snapshot runs show the demo party (or the scenario a snapshot
 * names) and never touch the network or Credential Manager; a live
 * snapshot run would otherwise register a throwaway user on the
 * production server.
 */

import type { ModuleContext } from "../../app/context";
import { Store, type Observable } from "../../app/store";
import type { ActivityRecord } from "../../core/activity/activityRecord";
import { tr } from "../../core/localization/tr";
import { isEphemeral } from "../../core/modules/runMode";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { PetProfile } from "../../core/pets/petProfile";
import { PetPointsRules } from "../../core/pets/petPointsRules";
import type { ProvidedFocus } from "../../core/providers/providedFocus";
import { ProvidedParty, ProvidedPartySession } from "../../core/providers/providedParty";
import type { Instant, Seconds } from "../../core/time";
import { PartyAccount } from "../../core/party/partyAccount";
import { eligibleFrom } from "../../core/party/partyAgeCheck";
import { hostPartyCredentialStore, InMemoryPartyCredentialStore, type PartyCredentialStore } from "../../core/party/partyCredentialStore";
import { partyDemoBlocked, partyDemoCelebration, partyDemoInvitee, partyDemoScenario, demoAgeEligibleFrom, PARTY_DEMO_SCENARIOS, type PartyDemoScenario } from "../../core/party/partyDemo";
import { PartyError, partyErrorMessage } from "../../core/party/partyError";
import { PartyHeartbeatSchedule } from "../../core/party/partyHeartbeatSchedule";
import type { PartyInvite } from "../../core/party/partyInvite";
import { PartyInviteFlow } from "../../core/party/partyInviteFlow";
import { PartyCode, type Party, type PartyFriendRequest, type PartyProfile } from "../../core/party/partyModels";
import { NO_REFUSAL, refusalUnion, type PartyBlockedUser, type PartyNameRefusal, type PartyReport, type PartyReportReason } from "../../core/party/partyModeration";
import { PartyPresenceTracker } from "../../core/party/partyPresenceTracker";
import { PartyRefreshPlan, type PartyFeed } from "../../core/party/partyRefreshPlan";
import { PartySessionTracker, type PartySessionCompletion } from "../../core/party/partySessionTracker";
import {
  cleanedPartyName,
  decodePartySettings,
  encodePartySettings,
  partyAgeStatus,
  partyProfileUpdate,
  partyServerIssue,
  partyServerURL,
  partySettings as makePartySettings,
  refusedNames as filterRefusedNames,
  type PartySettings,
} from "../../core/party/partySettings";
import { PartyState } from "../../core/party/partyState";
import { PartyTeamCelebration } from "../../core/party/partyTeamCelebration";
import { hostPartyTransport, type PartyTransport } from "../../core/party/partyTransport";
import { studyPet } from "../closet/closetServices";
import { copyText } from "./PartyComponents";
import { partyState as sharedPartyState } from "./partyServices";

/** A panel action in flight. Port of PartyAction. */
export type PartyAction =
  | { readonly kind: "addFriend" }
  | { readonly kind: "acceptFriend"; readonly code: string }
  | { readonly kind: "removeFriend"; readonly code: string }
  | { readonly kind: "createParty" }
  | { readonly kind: "joinParty" }
  | { readonly kind: "joinFriend"; readonly code: string }
  | { readonly kind: "leaveParty" }
  | { readonly kind: "session" }
  | { readonly kind: "deleteData" }
  | { readonly kind: "block"; readonly code: string }
  | { readonly kind: "unblock"; readonly code: string }
  | { readonly kind: "report" };

export function samePartyAction(a: PartyAction | undefined, b: PartyAction): boolean {
  if (a === undefined || a.kind !== b.kind) return false;
  return ("code" in a ? a.code : undefined) === ("code" in b ? b.code : undefined);
}

export interface PartyStoreState {
  readonly party: PartyState;
  readonly settings: PartySettings;
  /** The moment countdowns measure against; moves on while the panel shows, whenever one of its countdowns changes. */
  readonly now: Instant;
  readonly pending: PartyAction | undefined;
  /** The last action's failure, shown once under the control that caused it. */
  readonly notice: string | undefined;
  /** The notice confirms an action (a report sent, someone blocked) rather than saying what went wrong. */
  readonly noticeConfirms: boolean;
  /** The friend or party member the report card is about, while it shows. */
  readonly reporting: PartyProfile | undefined;
  /** The people I blocked, for the Blocked list in Party options; undefined until `loadBlocked()` has an answer. */
  readonly blocked: readonly PartyBlockedUser[] | undefined;
  /** The confirmation an invite link opened, while it fills the island. A new box after every step, so React redraws. */
  readonly invite: { readonly flow: PartyInviteFlow } | undefined;
  /** The "Great job, team!" moment after a shared session ran to its end, while it is up. */
  readonly celebration: PartyTeamCelebration | undefined;
  /** How the last "Delete my Party data" went, for Party options. */
  readonly deletionNotice: string | undefined;
  /** My pet as friends should see it. */
  readonly pet: PetProfile;
  /** The names the server refused on the last connect. */
  readonly serverRefusedNames: PartyNameRefusal;
  /** Whether the stored settings have been read; nothing connects before. */
  readonly settingsLoaded: boolean;
}

export interface PartyStoreOptions {
  /** Replaces the host's HTTP (tests). */
  readonly transport?: PartyTransport;
  /** Replaces Credential Manager (tests). */
  readonly credentials?: PartyCredentialStore;
}

/** Where Party keeps its documents: the settings and the presence tracker. */
export const PARTY_FOLDER = "Party";
export const PARTY_SETTINGS_FILE = "settings.json";
export const PARTY_PRESENCE_FILE = "presence.json";

/** The snapshot states beyond the demo scenarios. */
export const PARTY_SNAPSHOT_STATES = [...PARTY_DEMO_SCENARIOS, "inviteFriend", "inviteParty", "inviteOff"] as const;

/** Syncs a new name once typing pauses, since Settings saves the name on every keystroke and each sync is a request. */
const NAME_SYNC_DELAY: Seconds = 1;
/** The longest wait a timer can take. */
const MAX_TIMER_MS = 2 ** 31 - 1;

type Timer = ReturnType<typeof setTimeout> | undefined;

function isScenario(name: string): name is PartyDemoScenario {
  return (PARTY_DEMO_SCENARIOS as readonly string[]).includes(name);
}

export class PartyStore extends Store<PartyStoreState> {
  readonly isDemo: boolean;
  private readonly isSnapshot: boolean;
  private readonly shared: Observable<PartyState>;
  private readonly documents: DocumentStore | undefined;
  private readonly credentials: PartyCredentialStore;
  private readonly transport: PartyTransport | undefined;
  private account: PartyAccount | undefined;
  private tracker = new PartyPresenceTracker();
  private readonly sessions = new PartySessionTracker();
  private heartbeats = new PartyHeartbeatSchedule();
  private connectBackoff = new PartyHeartbeatSchedule();
  private readonly plan = new PartyRefreshPlan();
  private focus: ProvidedFocus | undefined;
  private isRunning = false;
  private panelVisible = false;
  private connectGeneration = 0;
  private heartbeatGeneration = 0;
  private refreshGeneration = 0;
  private connectTimer: Timer;
  private heartbeatTimer: Timer;
  private refreshTimer: Timer;
  private clockTimer: Timer;
  private nameSyncTimer: Timer;
  private sessionEndTimer: Timer;
  private celebrationTimer: Timer;
  private noticeTimer: Timer;
  private blockedLoading = false;
  /** The account whose grants were fetched, so reconnects don't ask again until the identity changes. */
  private grantsFetchedFor: PartyAccount | undefined;
  private readonly stops: (() => void)[] = [];
  /** Listeners for each stay in a shared session as it ends, and for the grants the server hands out. */
  private readonly completionListeners = new Set<(completion: PartySessionCompletion) => void>();
  private readonly grantListeners = new Set<(items: readonly string[]) => void>();
  /** True while a demo scenario pins the name, so the app-wide name doesn't clear what the scenario shows. */
  private pinsName = false;
  /** Whether the user is signed in with Apple, so an under-13 answer leaves the account's data to the sync service. */
  isSignedIn: () => boolean = () => false;
  /** Called after the user answers the age question here, so the Apple account follows the answer. */
  ageAnswered: () => void = () => {};

  constructor(
    private readonly context: ModuleContext,
    options: PartyStoreOptions = {},
  ) {
    const now = context.now();
    const shared = sharedPartyState(context);
    const ephemeral = isEphemeral(context.runMode);
    const pet = studyPet(context).state.profile;
    super({
      party: shared.get(),
      settings: ephemeral ? makePartySettings({ name: "Sam", ageEligibleFrom: Number.NEGATIVE_INFINITY }) : makePartySettings(),
      now,
      pending: undefined,
      notice: undefined,
      noticeConfirms: false,
      reporting: undefined,
      blocked: undefined,
      invite: undefined,
      celebration: undefined,
      deletionNotice: undefined,
      pet,
      serverRefusedNames: NO_REFUSAL,
      settingsLoaded: ephemeral,
    });
    this.shared = shared;
    this.isDemo = context.isDemo;
    this.isSnapshot = context.isSnapshot;
    this.transport = options.transport;
    this.credentials = options.credentials ?? (ephemeral ? new InMemoryPartyCredentialStore() : hostPartyCredentialStore(context.host));
    this.documents = ephemeral ? undefined : context.storage.folder(PARTY_FOLDER);
    this.stops.push(shared.subscribe(() => this.sharedDidChange()));
    if (!ephemeral) void this.load();
  }

  /* MARK: Following the app */

  /** Follows the shared focus clock, the pet and the app-wide name; called once by the module. */
  follow(): void {
    const context = this.context;
    this.stops.push(
      context.snapshot.subscribe(() => this.focusDidChange(context.snapshot.get().focus)),
      studyPet(context).subscribe(() => this.updatePet(studyPet(context).state.profile)),
      context.settings.settings.subscribe(() => this.nameDidChange(context.settings.current.displayName)),
    );
    this.focusDidChange(context.snapshot.get().focus);
    this.nameDidChange(context.settings.current.displayName);
  }

  /** Each stay in a shared session as it ends, whether it ran to its end or was cut short. */
  onCompletion(listener: (completion: PartySessionCompletion) => void): () => void {
    this.completionListeners.add(listener);
    return () => this.completionListeners.delete(listener);
  }

  /** The limited edition item ids the friends server granted this identity, each time they are fetched. */
  onGrants(listener: (items: readonly string[]) => void): () => void {
    this.grantListeners.add(listener);
    return () => this.grantListeners.delete(listener);
  }

  /* MARK: Derived */

  /** The clock, for countdowns and dates. */
  now(): Instant {
    return this.context.now();
  }

  timeZone(): string {
    return this.context.timeZone();
  }

  /** Whether the panel (or the onboarding step) is on screen. */
  get isVisible(): boolean {
    return this.panelVisible;
  }

  /**
   * Opens a web page in the default browser, best effort. The host opens
   * https links only, so a mail link puts the address on the clipboard
   * instead and says so.
   */
  openURL(url: string): void {
    if (url.startsWith("mailto:")) {
      void copyText(url.slice("mailto:".length)).then((copied) => {
        if (copied) this.confirm(tr("Copied"));
      });
      return;
    }
    void this.context.host.openUrl(url).catch((error: unknown) => this.context.logger.error("Could not open a link", error));
  }

  /** The account's Sign In before the age check: the question belongs to Party, so its tab asks it. */
  askAgeFirst(): void {
    this.setNotice(tr("Open the Party tab to answer when you were born, then sign in here."), false);
  }

  get party(): PartyState {
    return this.state.party;
  }

  /** My name or pet name that friends can't see, so Settings and onboarding say so under the name. */
  get refusedNames(): PartyNameRefusal {
    return refusalUnion(filterRefusedNames(this.state.settings, this.state.pet), this.state.serverRefusedNames);
  }

  /** The server Party talks to now, with the development override. */
  get serverURL(): string | undefined {
    return partyServerURL(this.state.settings, this.context.startup.partyServer ?? undefined);
  }

  /** The party and its shared session for other modules, at the moment the panel counts from. */
  provided(): ProvidedParty | undefined {
    const party = this.state.party;
    const pets = party.partyPets;
    if (pets === undefined) return undefined;
    const session = party.session(this.state.now);
    return new ProvidedParty(
      pets,
      session === undefined ? undefined : new ProvidedPartySession({ ...session, ...(session.hostName === undefined ? {} : { hostName: session.hostName }) }),
    );
  }

  isPending(action: PartyAction): boolean {
    return samePartyAction(this.state.pending, action);
  }

  /* MARK: Lifecycle */

  /** The module was enabled: connect and start heartbeats. */
  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;
    this.scheduleSessionEnd();
    if (isEphemeral(this.context.runMode)) return;
    if (this.state.settingsLoaded) this.rebuildAccount();
  }

  /** The module was disabled or the app is quitting: tell friends I'm offline (best effort) and stop every timer. */
  stop(): void {
    if (!this.isRunning) return;
    this.isRunning = false;
    this.cancelConnect();
    this.cancelRefresh();
    globalThis.clearTimeout(this.nameSyncTimer);
    this.sendOfflineOnce();
  }

  /** Stops following the app, e.g. when the window closes. */
  dispose(): void {
    this.stop();
    for (const stop of this.stops) stop();
    globalThis.clearTimeout(this.clockTimer);
    globalThis.clearTimeout(this.sessionEndTimer);
    globalThis.clearTimeout(this.celebrationTimer);
    globalThis.clearTimeout(this.noticeTimer);
  }

  /** The panel appeared or disappeared; refreshes only run while it shows. */
  setVisible(visible: boolean): void {
    this.panelVisible = visible;
    this.setState({ now: this.context.now() });
    this.plan.setVisible(visible || this.state.invite !== undefined);
    this.scheduleClock();
    if (visible) {
      if (this.state.party.connection.kind === "unreachable") this.retry();
      this.reopenIfOldEnough();
    }
    this.scheduleRefresh();
  }

  /** The leaderboard view opened or closed; it fetches once per opening. */
  setLeaderboardVisible(visible: boolean): void {
    this.plan.setLeaderboardVisible(visible);
    this.scheduleRefresh();
  }

  private async load(): Promise<void> {
    const documents = this.documents;
    if (documents === undefined) return;
    let settings = makePartySettings();
    try {
      settings = decodePartySettings(await documents.read(PARTY_SETTINGS_FILE));
    } catch (error) {
      this.context.logger.error("Could not read the Party settings", error);
    }
    try {
      const presence = await documents.read(PARTY_PRESENCE_FILE);
      if (presence !== undefined) this.tracker = PartyPresenceTracker.decode(presence);
    } catch (error) {
      this.context.logger.error("Could not read the Party presence", error);
    }
    /* The app-wide name is the name friends see; Party's own copy follows it. */
    const name = this.context.settings.current.displayName;
    settings = { ...settings, name };
    this.tracker.setInvisible(settings.invisible);
    this.setState({ settings, settingsLoaded: true });
    this.replaceParty((party) => party.reset(settings, this.context.now()));
    if (this.isRunning) this.rebuildAccount();
  }

  /** Replaces the shared party state with a changed clone. */
  private replaceParty(change: (party: PartyState) => void): void {
    const next = this.shared.get().clone();
    change(next);
    this.shared.set(next);
  }

  private sharedDidChange(): void {
    const party = this.shared.get();
    if (party === this.state.party) return;
    this.setState({ party, ...(this.panelVisible ? { now: this.context.now() } : {}) });
    this.scheduleSessionEnd();
    this.advanceInvite();
    this.scheduleClock();
    this.observeSession();
  }

  /** While the panel shows, moves `now` forward only when a countdown on it changes: every second during a shared session, otherwise once a minute at most. */
  private scheduleClock(): void {
    globalThis.clearTimeout(this.clockTimer);
    if (!this.panelVisible) return;
    const next = this.state.party.nextClockChange(this.state.now);
    if (next === undefined) return;
    this.clockTimer = globalThis.setTimeout(
      () => {
        this.setState({ now: Math.max(this.context.now(), next) });
        this.scheduleClock();
      },
      Math.max(0, (next - this.context.now()) * 1000),
    );
  }

  /* MARK: Age check */

  /**
   * The age check's answer (`PartyAgeCheck`). Only the day the user is
   * surely 13 is saved, on this PC. Old enough, Party connects; under 13,
   * it stays off until that day, and a Party identity this PC made before
   * the check existed is deleted from the server.
   */
  answerAge(month: number, year: number): void {
    const eligible = eligibleFrom({ month, year }, this.context.timeZone());
    if (eligible === undefined) return;
    this.adoptAgeAnswer(eligible);
    this.ageAnswered();
  }

  /** Takes an answer already given (also the one asked before Sign in with Apple), so the question is asked once. */
  adoptAgeAnswer(eligible: Instant): void {
    const now = this.context.now();
    if (partyAgeStatus(this.state.settings, now).kind !== "unanswered") return;
    const settings = { ...this.state.settings, ageEligibleFrom: eligible };
    if (this.isDemo || this.isSnapshot) {
      this.setState({ settings });
      if (partyAgeStatus(settings, now).kind === "passed") this.shared.set(partyDemoScenario("hosting", now, this.context.timeZone()));
      else this.replaceParty((party) => party.reset(settings, now));
      return;
    }
    const tooYoung = partyAgeStatus(settings, now).kind !== "passed";
    this.update(settings);
    if (tooYoung && !this.isSignedIn()) this.deleteIdentityMadeBeforeAgeCheck();
  }

  /** Someone told they were too young turned 13 while Tabbi kept running. */
  private reopenIfOldEnough(): void {
    if (this.isDemo) return;
    const connection = this.state.party.connection;
    if (connection.kind !== "ageCheck" || connection.tooYoungUntil === undefined || connection.tooYoungUntil > this.context.now()) return;
    this.replaceParty((party) => party.reset(this.state.settings, this.context.now()));
    this.rebuildAccount();
  }

  /** Deletes the anonymous Party identity stored for this server, if any, best effort. */
  private deleteIdentityMadeBeforeAgeCheck(): void {
    const account = this.storedAccount();
    if (account === undefined) return;
    account.deleteAccount().catch(() => undefined);
  }

  /** The identity stored for this server, even while the age check keeps Party from connecting. */
  private storedAccount(): PartyAccount | undefined {
    const server = this.serverURL;
    return server === undefined ? undefined : this.makeAccount(server);
  }

  private makeAccount(server: string): PartyAccount {
    const transport = this.transport ?? hostPartyTransport(server, (request) => this.context.host.httpRequest(request));
    return new PartyAccount({ server, transport, credentials: this.credentials });
  }

  /* MARK: Settings */

  /**
   * Applies edited settings: a new server starts over with that server's
   * identity, a new name becomes the app-wide name and syncs, and the
   * invisible toggle sends one heartbeat (`offline`, or the current status
   * when coming back).
   */
  update(next: PartySettings): void {
    const old = this.state.settings;
    if (next.serverText === old.serverText && next.name === old.name && next.invisible === old.invisible && next.ageEligibleFrom === old.ageEligibleFrom) return;
    this.setState({ settings: next });
    this.saveSettings(next);
    if (next.name !== old.name) this.context.settings.update((settings) => ({ ...settings, displayName: next.name }));
    if (this.isDemo || this.isSnapshot) return;
    const serverChanged = partyServerURL(next) !== partyServerURL(old) || partyServerIssue(next) !== partyServerIssue(old);
    if (serverChanged || next.ageEligibleFrom !== old.ageEligibleFrom) {
      this.replaceParty((party) => party.reset(next, this.context.now()));
      this.setState({ serverRefusedNames: NO_REFUSAL });
      this.rebuildAccount();
      return;
    }
    if (cleanedPartyName(next) !== cleanedPartyName(old)) {
      this.setState({ serverRefusedNames: { ...this.state.serverRefusedNames, name: false } });
      this.scheduleNameSync();
    }
    if (next.invisible !== old.invisible && this.tracker.setInvisible(next.invisible)) {
      this.saveTracker();
      this.sendHeartbeat();
    }
  }

  private saveSettings(settings: PartySettings): void {
    this.documents?.write(PARTY_SETTINGS_FILE, encodePartySettings(settings)).catch((error: unknown) => this.context.logger.error("Could not save the Party settings", error));
    /* The user's own server reaches the host's allow-list; blank or the default server needs none. */
    const server = partyServerURL(settings);
    const custom = server !== undefined && settings.serverText.trim() !== "" ? server : null;
    void this.context.host.setPartyServer(custom).catch((error: unknown) => this.context.logger.error("Could not set the Party server", error));
  }

  private nameDidChange(name: string): void {
    if (name === this.state.settings.name || this.pinsName) return;
    const old = this.state.settings;
    const next = { ...old, name };
    this.setState({ settings: next });
    if (!this.isSnapshot) this.documents?.write(PARTY_SETTINGS_FILE, encodePartySettings(next)).catch(() => undefined);
    if (cleanedPartyName(next) !== cleanedPartyName(old)) {
      this.setState({ serverRefusedNames: { ...this.state.serverRefusedNames, name: false } });
      this.scheduleNameSync();
    }
  }

  private scheduleNameSync(): void {
    globalThis.clearTimeout(this.nameSyncTimer);
    if (!this.isRunning || this.isDemo) return;
    this.nameSyncTimer = globalThis.setTimeout(() => this.connect(), NAME_SYNC_DELAY * 1000);
  }

  /** My pet changed (in the Closet): friends see it after the sync. */
  private updatePet(pet: PetProfile): void {
    if (pet.equals(this.state.pet)) return;
    if (pet.name !== this.state.pet.name) this.setState({ serverRefusedNames: { ...this.state.serverRefusedNames, petName: false } });
    this.setState({ pet });
    if (this.account !== undefined) this.connect();
  }

  /** The stored identity changed (signed in with Apple, signed out or deleted the account): reconnect as the new one. */
  identityDidChange(): void {
    if (this.isDemo || this.isSnapshot) return;
    this.replaceParty((party) => party.reset(this.state.settings, this.context.now()));
    this.setState({ serverRefusedNames: NO_REFUSAL });
    this.rebuildAccount();
  }

  /**
   * Party options' "Delete my Party data": `DELETE /v1/me` removes the
   * profile, presence, friendships and party memberships. While Party stays
   * on it then starts over with a new friend code.
   */
  deletePartyData(): void {
    if (this.state.pending !== undefined) return;
    this.setState({ deletionNotice: undefined });
    if (this.isDemo || this.isSnapshot) {
      this.setState({ deletionNotice: tr("This is a demo. Nothing was deleted.") });
      return;
    }
    const account = this.account ?? this.storedAccount();
    if (account === undefined) return;
    /* Nothing may use the old identity meanwhile: a heartbeat after the delete would register a new user before the user sees it went. */
    this.account = undefined;
    this.cancelConnect();
    this.cancelRefresh();
    this.setState({ pending: { kind: "deleteData" } });
    account.deleteAccount().then(
      () => {
        this.tracker = new PartyPresenceTracker();
        this.tracker.setInvisible(this.state.settings.invisible);
        this.saveTracker();
        this.setState({ deletionNotice: tr("Your Party data was deleted.") });
        this.finishDeletion();
      },
      (error: unknown) => {
        this.setState({ deletionNotice: partyErrorMessage(PartyStore.partyError(error)) });
        this.finishDeletion();
      },
    );
  }

  private finishDeletion(): void {
    this.setState({ pending: undefined });
    this.replaceParty((party) => party.reset(this.state.settings, this.context.now()));
    this.setState({ serverRefusedNames: NO_REFUSAL });
    this.rebuildAccount();
  }

  /* MARK: Actions */

  /** Tries the server again now, after `unreachable` or a stale refresh. */
  retry(): void {
    if (this.isDemo) return;
    if (this.state.party.awaitsAgeCheck) {
      this.reopenIfOldEnough();
      return;
    }
    this.connectBackoff.reset();
    this.heartbeats.reset();
    if (this.state.party.connection.kind === "connected") {
      this.plan.invalidate("friends");
      this.plan.invalidate("party");
      this.scheduleRefresh();
    } else {
      this.connect();
    }
  }

  /** Asks someone to be friends by their code. */
  addFriend(text: string): void {
    const code = PartyCode.normalize(text, PartyCode.friendCodeLength);
    if (code === undefined) {
      this.setNotice(tr("Friend codes are %lld letters and digits.", PartyCode.friendCodeLength), false);
      return;
    }
    this.run({ kind: "addFriend" }, async (account) => {
      const addition = await account.perform((client) => client.addFriend(code));
      this.replaceParty((party) => party.didAsk(addition, this.context.now()));
      this.plan.invalidate("friends");
      if (addition.kind === "requested") this.confirm(tr("Request sent to %@.", addition.profile.name));
    });
  }

  /** Accepts the friend request someone sent me. The demo makes them a friend on the spot. */
  acceptFriend(request: PartyFriendRequest): void {
    const code = request.profile.code;
    if (this.isDemo || this.isSnapshot) {
      this.replaceParty((party) => party.didAddFriend(request.profile, this.context.now()));
      return;
    }
    this.run({ kind: "acceptFriend", code }, async (account) => {
      const addition = await account.perform((client) => client.acceptFriend(code));
      this.replaceParty((party) => party.didAddFriend(addition.profile, this.context.now()));
      this.plan.invalidate("friends");
    });
  }

  /** Ends a friendship, cancels my request, or declines theirs. A decline is quiet: the sender is never told. */
  removeFriend(code: string): void {
    if ((this.isDemo || this.isSnapshot) && !this.state.party.friends.some((friend) => friend.profile.code === code)) {
      this.replaceParty((party) => party.didRemoveFriend(code));
      return;
    }
    this.run({ kind: "removeFriend", code }, async (account) => {
      await account.perform((client) => client.removeFriend(code));
      this.replaceParty((party) => party.didRemoveFriend(code));
    });
  }

  createParty(): void {
    this.run({ kind: "createParty" }, async (account) => {
      const party = await account.perform((client) => client.createParty());
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
    });
  }

  joinParty(text: string): void {
    const code = PartyCode.normalize(text, PartyCode.partyCodeLength);
    if (code === undefined) {
      this.setNotice(tr("Party codes are %lld letters and digits.", PartyCode.partyCodeLength), false);
      return;
    }
    this.run({ kind: "joinParty" }, async (account) => {
      const party = await account.perform((client) => client.joinParty(code));
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
    });
  }

  /** Joins the party a friend is in. */
  joinFriend(code: string): void {
    this.run({ kind: "joinFriend", code }, async (account) => {
      const party = await account.perform((client) => client.joinPartyOf(code));
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
      this.plan.invalidate("friends");
    });
  }

  leaveParty(): void {
    this.run({ kind: "leaveParty" }, async (account) => {
      await account.perform((client) => client.leaveParty());
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: undefined }));
      this.plan.invalidate("friends");
    });
  }

  /** Host only: starts a shared focus phase of `minutes` for everyone. */
  startSession(minutes: number): void {
    const method = this.tracker.method;
    const end = Math.round(this.context.now() + minutes * 60);
    this.run({ kind: "session" }, async (account) => {
      const party = await account.perform((client) => client.startSession(method, end));
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
    });
  }

  /** Host only: ends the shared session. */
  endSession(): void {
    this.run({ kind: "session" }, async (account) => {
      const party = await account.perform((client) => client.endSession());
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
    });
  }

  /** Steps out of the shared session while it goes on for the others. Only on this PC: the server keeps the session for the party. */
  leaveSession(): void {
    this.replaceParty((party) => party.leaveSession());
  }

  rejoinSession(): void {
    this.replaceParty((party) => party.rejoinSession());
  }

  /** Shows `celebration` at the top of the panel, then lets it go. */
  celebrate(celebration: PartyTeamCelebration): void {
    this.setState({ celebration });
    globalThis.clearTimeout(this.celebrationTimer);
    this.celebrationTimer = globalThis.setTimeout(
      () => {
        if (this.state.celebration === celebration) this.setState({ celebration: undefined });
      },
      Math.max(0, (celebration.endsAt - this.context.now()) * 1000),
    );
  }

  clearCelebration(): void {
    globalThis.clearTimeout(this.celebrationTimer);
    this.setState({ celebration: undefined });
  }

  clearNotice(): void {
    globalThis.clearTimeout(this.noticeTimer);
    this.setState({ notice: undefined, noticeConfirms: false });
  }

  /** A notice is about the last click; it goes after a moment (the panel's `.task(id: notice)`), unless a snapshot keeps it. */
  private setNotice(notice: string | undefined, confirms: boolean): void {
    globalThis.clearTimeout(this.noticeTimer);
    this.setState({ notice, noticeConfirms: confirms });
    if (notice === undefined || this.isSnapshot) return;
    this.noticeTimer = globalThis.setTimeout(() => {
      if (this.state.notice === notice) this.setState({ notice: undefined, noticeConfirms: false });
    }, 4000);
  }

  private confirm(message: string): void {
    this.setNotice(message, true);
  }

  /* MARK: Moderation */

  /** Blocks someone from a friend's or member's menu: they go from the panel at once. */
  block(profile: PartyProfile): void {
    const code = profile.code;
    this.run({ kind: "block", code }, async (account) => {
      const { user } = await account.perform((client) => client.block(code));
      this.didBlock(user);
    });
  }

  private didBlock(user: PartyBlockedUser): void {
    this.replaceParty((party) => party.didBlock(user.code));
    this.setState({ blocked: [user, ...(this.state.blocked ?? []).filter((other) => other.code !== user.code)] });
    this.plan.invalidate("friends");
    this.plan.invalidate("party");
    this.confirm(tr("Blocked %@. Unblock them in Party options.", user.name));
  }

  /** Lifts a block from the Blocked list. The friendship stays ended. */
  unblock(code: string): void {
    if (this.isDemo || this.isSnapshot) {
      this.setState({ blocked: (this.state.blocked ?? []).filter((user) => user.code !== code) });
      return;
    }
    this.run({ kind: "unblock", code }, async (account) => {
      await account.perform((client) => client.unblock(code));
      this.setState({ blocked: (this.state.blocked ?? []).filter((user) => user.code !== code) });
    });
  }

  /** Fetches the Blocked list for Party options; the demo shows a sample. */
  loadBlocked(): void {
    if (this.isDemo || this.isSnapshot) {
      if (this.state.blocked === undefined) this.setState({ blocked: partyDemoBlocked(this.context.now()) });
      return;
    }
    const account = this.account;
    if (account === undefined || this.blockedLoading) return;
    this.blockedLoading = true;
    account.perform((client) => client.blocks()).then(
      (list) => {
        this.blockedLoading = false;
        this.setState({ blocked: list });
        this.advanceInvite();
      },
      () => {
        this.blockedLoading = false;
      },
    );
  }

  /** Opens the report card for a friend or party member. */
  beginReport(profile: PartyProfile): void {
    this.clearNotice();
    this.setState({ reporting: profile });
  }

  cancelReport(): void {
    if (this.isPending({ kind: "report" })) return;
    this.setState({ reporting: undefined });
  }

  /** Sends the report card, then blocks them too when asked. The card stays open with the reason and note if sending fails. */
  sendReport(reason: PartyReportReason, note: string, alsoBlock: boolean): void {
    const profile = this.state.reporting;
    if (profile === undefined) return;
    if (this.isDemo || this.isSnapshot) {
      this.setState({ reporting: undefined });
      this.confirm(tr("This is a demo. No report was sent."));
      return;
    }
    const report: PartyReport = { code: profile.code, reason, ...(note.trim() === "" ? {} : { note }) };
    this.run({ kind: "report" }, async (account) => {
      await account.perform((client) => client.report(report));
      this.setState({ reporting: undefined });
      if (alsoBlock) {
        const { user } = await account.perform((client) => client.block(profile.code));
        this.didBlock(user);
        this.confirm(tr("Thanks. Your report was sent and %@ is blocked.", profile.name));
      } else {
        this.confirm(tr("Thanks. Your report was sent."));
      }
    });
  }

  /** Runs one panel action: one at a time, with its failure as the notice. */
  private run(action: PartyAction, body: (account: PartyAccount) => Promise<void>): void {
    if (this.state.pending !== undefined) return;
    this.clearNotice();
    if (this.isDemo || this.isSnapshot) {
      this.setNotice(tr("This is a demo. Run without TABBI_DEMO to study with friends."), false);
      return;
    }
    const account = this.account;
    if (account === undefined) return;
    this.setState({ pending: action });
    body(account)
      .catch((error: unknown) => {
        const failure = PartyStore.partyError(error);
        if (failure.kind === "notInParty" || failure.kind === "partyNotFound") this.replaceParty((party) => party.didFetchParty({ ok: false, error: failure }));
        this.setNotice(partyErrorMessage(failure), false);
      })
      .finally(() => {
        this.setState({ pending: undefined });
        this.plan.inParty = this.state.party.inParty;
        this.scheduleRefresh();
      });
  }

  /* MARK: Invites */

  /** An invite link was opened: asks about it in the island. Nothing is sent until the user confirms. A new link replaces one still showing. */
  open(invite: PartyInvite, partyIsOn: boolean): void {
    this.setInvite(new PartyInviteFlow(invite, partyIsOn));
    this.inviteWillConnect();
  }

  /** The invite's "Turn On Party" was clicked and the module turned on. */
  inviteTurnedPartyOn(): void {
    this.changeInvite((flow) => flow.partyTurnedOn());
    this.inviteWillConnect();
  }

  /** "Try Again" after Party couldn't connect for the invite. */
  retryInviteConnection(): void {
    this.changeInvite((flow) => flow.retryConnecting());
    this.retry();
    this.inviteWillConnect();
  }

  /** The invite's "Add Friend" or "Join Party" (or "Try Again" after a failure that may pass) was clicked: sends the one request it asks for. */
  confirmInvite(): void {
    const flow = this.state.invite?.flow;
    if (flow === undefined || !flow.begin()) return;
    this.setInvite(flow);
    if (this.isDemo || this.isSnapshot) {
      this.finishDemoInvite(flow.invite);
      return;
    }
    const account = this.account;
    if (account === undefined) {
      this.changeInvite((current) => current.didFail(PartyError.of("unreachable")));
      return;
    }
    const send = async () => {
      if (flow.invite.kind === "addFriend") {
        const addition = await account.perform((client) => client.addFriend(flow.invite.code));
        this.replaceParty((party) => party.didAsk(addition, this.context.now()));
        this.plan.invalidate("friends");
        this.changeInvite((current) => current.didAsk(addition));
      } else {
        const party = await account.perform((client) => client.joinParty(flow.invite.code));
        this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
        this.plan.invalidate("friends");
        this.changeInvite((current) => current.didJoin(party));
      }
    };
    send()
      .catch((error: unknown) => this.changeInvite((current) => current.didFail(PartyStore.partyError(error))))
      .finally(() => {
        this.plan.inParty = this.state.party.inParty;
        this.scheduleRefresh();
      });
  }

  /** "Not Now" or "Done": the invite goes away. */
  dismissInvite(): void {
    this.setState({ invite: undefined });
    this.plan.setVisible(this.panelVisible);
    this.scheduleRefresh();
  }

  private setInvite(flow: PartyInviteFlow | undefined): void {
    this.setState({ invite: flow === undefined ? undefined : { flow } });
  }

  private changeInvite(change: (flow: PartyInviteFlow) => void): void {
    const flow = this.state.invite?.flow;
    if (flow === undefined) return;
    change(flow);
    this.setInvite(flow);
  }

  /** While the invite waits for Party, friends load as if the panel were open, so "already friends" can be told apart. */
  private inviteWillConnect(): void {
    if (this.state.invite?.flow.stage.kind !== "connecting") return;
    this.plan.setVisible(true);
    this.scheduleRefresh();
    this.advanceInvite();
  }

  /** Hands the invite each new Party state while it waits to connect. */
  private advanceInvite(): void {
    const flow = this.state.invite?.flow;
    if (flow === undefined || flow.stage.kind !== "connecting") return;
    const party = this.state.party;
    if (flow.invite.kind === "addFriend" && this.state.blocked === undefined && party.connection.kind === "connected") this.loadBlocked();
    const before = flow.stage;
    flow.update(party, this.state.blocked);
    if (flow.stage !== before) this.setInvite(flow);
  }

  /** The demo answers an invite with sample people and parties and touches no network. */
  private finishDemoInvite(invite: PartyInvite): void {
    const now = this.context.now();
    if (invite.kind === "addFriend") {
      const friend: PartyProfile = { ...partyDemoInvitee(), code: invite.code };
      this.replaceParty((party) => party.didAsk({ kind: "requested", profile: friend }, now));
      this.changeInvite((flow) => flow.didAsk({ kind: "requested", profile: friend }));
    } else {
      const sample = partyDemoScenario("member", now, this.context.timeZone()).party;
      if (sample === undefined) return;
      const party: Party = { ...sample, code: invite.code };
      this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
      this.changeInvite((flow) => flow.didJoin(party));
    }
  }

  /* MARK: Connection */

  private rebuildAccount(): void {
    this.cancelConnect();
    this.cancelHeartbeat();
    this.cancelRefresh();
    this.heartbeats.reset();
    this.connectBackoff.reset();
    const server = this.serverURL;
    /* Nothing reaches the server before the age check says old enough. */
    if (server === undefined || partyAgeStatus(this.state.settings, this.context.now()).kind !== "passed") {
      this.account = undefined;
      return;
    }
    this.account = this.makeAccount(server);
    this.connect();
  }

  private cancelConnect(): void {
    this.connectGeneration += 1;
    globalThis.clearTimeout(this.connectTimer);
  }

  private cancelHeartbeat(): void {
    this.heartbeatGeneration += 1;
    globalThis.clearTimeout(this.heartbeatTimer);
  }

  private cancelRefresh(): void {
    this.refreshGeneration += 1;
    globalThis.clearTimeout(this.refreshTimer);
  }

  /** Registers or syncs the profile, then sends the launch heartbeat. */
  private connect(): void {
    const account = this.account;
    if (!this.isRunning || account === undefined) return;
    this.cancelConnect();
    const generation = this.connectGeneration;
    this.replaceParty((party) => party.willReconnect());
    const update = partyProfileUpdate(this.state.settings, this.state.pet);
    account.connect(update).then(
      (profile) => {
        if (generation !== this.connectGeneration || this.account !== account) return;
        this.setState({ serverRefusedNames: account.refusedNames });
        this.connectBackoff.reset();
        this.replaceParty((party) => party.didConnect(profile));
        this.sendHeartbeat();
        this.scheduleRefresh();
        this.fetchGrants();
      },
      (error: unknown) => {
        if (generation !== this.connectGeneration || this.account !== account) return;
        const failure = PartyStore.partyError(error);
        this.replaceParty((party) => party.didFailToConnect(failure));
        const delay = this.connectBackoff.delayAfterFailure(failure);
        if (delay === undefined) return;
        this.connectTimer = globalThis.setTimeout(() => this.connect(), delay * 1000);
      },
    );
  }

  /* MARK: Presence */

  private focusDidChange(timer: ProvidedFocus | undefined): void {
    this.focus = timer;
    if (this.isDemo || this.isSnapshot) return;
    const changed = this.tracker.observe(timer, this.context.now(), this.context.timeZone());
    this.saveTracker();
    if (changed) this.sendHeartbeat();
  }

  /** Sends a heartbeat now and schedules the next one from the reply. */
  private sendHeartbeat(): void {
    const account = this.account;
    if (!this.isRunning || account === undefined || this.state.party.connection.kind !== "connected") return;
    this.cancelHeartbeat();
    const generation = this.heartbeatGeneration;
    const now = this.context.now();
    this.tracker.observe(this.focus, now, this.context.timeZone());
    const body = this.tracker.heartbeat(now, this.context.timeZone());
    this.saveTracker();
    account.perform((client) => client.heartbeat(body)).then(
      (reply) => {
        if (generation !== this.heartbeatGeneration) return;
        if (reply.incomingRequests !== undefined) {
          const waiting = reply.incomingRequests;
          this.replaceParty((party) => party.didCountWaitingRequests(waiting));
        }
        this.scheduleHeartbeat(this.heartbeats.delayAfterSuccess(reply), generation);
      },
      (error: unknown) => {
        if (generation !== this.heartbeatGeneration) return;
        this.scheduleHeartbeat(this.heartbeats.delayAfterFailure(PartyStore.partyError(error)), generation);
      },
    );
  }

  private scheduleHeartbeat(delay: Seconds | undefined, generation: number): void {
    if (delay === undefined || generation !== this.heartbeatGeneration) return;
    this.heartbeatTimer = globalThis.setTimeout(() => this.sendHeartbeat(), Math.min(delay * 1000, MAX_TIMER_MS));
  }

  /** One `offline` heartbeat with no follow-up, unless already invisible (which sent it). Best effort: the app may be quitting. */
  private sendOfflineOnce(): void {
    this.cancelHeartbeat();
    const account = this.account;
    if (account === undefined || this.state.party.connection.kind !== "connected" || this.tracker.isInvisible) return;
    account.perform((client) => client.heartbeat({ status: "offline" })).catch(() => undefined);
  }

  private saveTracker(): void {
    this.documents?.write(PARTY_PRESENCE_FILE, this.tracker.encoded()).catch((error: unknown) => this.context.logger.error("Could not save the Party presence", error));
  }

  /* MARK: Grants */

  /** Asks the friends server once per identity which limited edition items it granted, and tells the listeners. Best effort. */
  private fetchGrants(): void {
    const account = this.account;
    if (!this.isRunning || account === undefined || this.grantsFetchedFor === account) return;
    account.perform((client) => client.grants()).then(
      (items) => {
        if (this.account !== account) return;
        this.grantsFetchedFor = account;
        for (const listener of [...this.grantListeners]) listener(items);
      },
      () => undefined,
    );
  }

  /* MARK: Refresh */

  /** Sleeps until the next feed is due, fetches it, and repeats while the panel is visible. */
  private scheduleRefresh(): void {
    this.cancelRefresh();
    this.plan.inParty = this.state.party.inParty;
    const account = this.account;
    if (this.isDemo || this.isSnapshot || !this.isRunning || this.state.party.connection.kind !== "connected" || account === undefined) return;
    const next = this.plan.nextDue();
    if (next === undefined) return;
    const generation = this.refreshGeneration;
    const wait = Math.max(0, next - this.context.now());
    this.refreshTimer = globalThis.setTimeout(() => {
      void this.runRefresh(account, generation);
    }, wait * 1000);
  }

  private async runRefresh(account: PartyAccount, generation: number): Promise<void> {
    for (const feed of this.plan.due(this.context.now())) {
      this.plan.didFetch(feed, this.context.now());
      await this.fetch(feed, account);
      if (generation !== this.refreshGeneration) return;
    }
    if (generation === this.refreshGeneration) this.scheduleRefresh();
  }

  private async fetch(feed: PartyFeed, account: PartyAccount): Promise<void> {
    try {
      switch (feed) {
        case "friends": {
          const list = await account.perform((client) => client.friendList());
          this.replaceParty((party) => party.didFetchFriendList({ ok: true, value: list }));
          break;
        }
        case "party": {
          const party = await account.perform((client) => client.party());
          this.replaceParty((state) => state.didFetchParty({ ok: true, value: party }));
          break;
        }
        case "leaderboard":
          /* The leaderboard view is not part of the Windows tab yet; its fetch is a request nobody reads. */
          break;
      }
    } catch (error) {
      const failure = PartyStore.partyError(error);
      if (feed === "friends") this.replaceParty((party) => party.didFetchFriendList({ ok: false, error: failure }));
      if (feed === "party") this.replaceParty((party) => party.didFetchParty({ ok: false, error: failure }));
    }
  }

  /** Moves `now` to the shared session's end, so the Timer tab and the closed island drop it on time even while the panel is hidden. */
  private scheduleSessionEnd(): void {
    globalThis.clearTimeout(this.sessionEndTimer);
    const end = this.state.party.session(this.context.now())?.endsAt;
    if (end === undefined) return;
    this.sessionEndTimer = globalThis.setTimeout(
      () => {
        this.setState({ now: this.context.now() });
        this.observeSession();
      },
      Math.min(Math.max(0, (end - this.context.now()) * 1000), MAX_TIMER_MS),
    );
  }

  /** Watches the session I'm in and reports each stay once it ends (PartySessionTracker). */
  private observeSession(): void {
    const completion = this.sessions.observe(this.state.party.session(this.context.now()), this.context.now());
    if (completion === undefined) return;
    for (const listener of [...this.completionListeners]) listener(completion);
  }

  /** The activity record for a finished stay, and the celebration a finished session earns. Port of PartyModule.finish. */
  finish(completion: PartySessionCompletion): { record: ActivityRecord | undefined; celebration: PartyTeamCelebration | undefined } {
    const record = completion.activityRecord(this.context.id);
    if (!completion.finished) return { record, celebration: undefined };
    const points = PetPointsRules.sharedPoints(completion.minutes, completion.friendCount, completion.finished);
    const celebration = new PartyTeamCelebration(completion, points, this.context.now(), this.state.pet.name);
    this.celebrate(celebration);
    return { record, celebration };
  }

  /* MARK: Snapshots */

  /** Puts the store into a demo scenario or an invite screen (snapshot runs only). */
  showSnapshotState(name: string): void {
    if (!this.isSnapshot) return;
    const now = this.context.now();
    const zone = this.context.timeZone();
    globalThis.clearTimeout(this.celebrationTimer);
    this.setState({ celebration: undefined, reporting: undefined, invite: undefined, notice: undefined, serverRefusedNames: NO_REFUSAL });
    this.pinsName = false;
    if (isScenario(name)) {
      const settings = makePartySettings({
        name: "Sam",
        ageEligibleFrom: demoAgeEligibleFrom(name, now),
        ...(name === "invalidServer" ? { serverText: "http://tabbi.example.com" } : {}),
      });
      this.setState({ settings });
      this.shared.set(partyDemoScenario(name, now, zone));
      if (name === "celebrating") this.setState({ celebration: partyDemoCelebration(now) });
      if (name === "reporting") this.setState({ reporting: this.state.party.friends[0]?.profile });
      if (name === "refusedName") {
        this.setState({ serverRefusedNames: { name: true, petName: false } });
        this.pinsName = true;
      }
      return;
    }
    this.shared.set(partyDemoScenario("lobby", now, zone));
    switch (name) {
      case "inviteFriend":
        this.setInvite(new PartyInviteFlow({ kind: "addFriend", code: partyDemoInvitee().code }, true));
        this.advanceInvite();
        return;
      case "inviteParty":
        this.setInvite(new PartyInviteFlow({ kind: "joinParty", code: "ZX7M2P" }, true));
        this.advanceInvite();
        return;
      case "inviteOff":
        this.setInvite(new PartyInviteFlow({ kind: "addFriend", code: partyDemoInvitee().code }, false));
        return;
      default:
        return;
    }
  }

  private static partyError(error: unknown): PartyError {
    return error instanceof PartyError ? error : PartyError.transport(error instanceof Error ? error.message : "failed");
  }
}
