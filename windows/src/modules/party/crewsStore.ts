/*
 * Port of CrewsStore: the Party tab's Crews mode: My crew, This week, the
 * Hall of Fame, Find, the crew pages and the crest editor (the Crews UI
 * spec), and the finished focus sessions it reports to the board.
 *
 * It talks to the server through Party's identity (`PartyStore.crewAccount`)
 * and only while Party is connected, so Crews follows Party's age check, its
 * server setting and its invisible mode for free. Like Party it fetches only
 * while Crews mode is on screen, and never in a demo or snapshot run, which
 * show the demo crews.
 *
 * Sessions are the exception: they are queued as they finish (merged, so one
 * stretch is sent once) and sent in the background while I am in a crew,
 * since the board counts them whether or not the panel is open. The Party
 * heartbeat's crews pulse badges the tab when people ask to join my crew and
 * tells the store when the owner I asked lets me in.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { crewColors, crewEmblems, crewFrames, findCrewInvite } from "../../core/crews/crewCatalog";
import { defaultCrest, randomCrest, resolvedCrest, type CrewCrest } from "../../core/crews/crewCrestArt";
import {
  approveJoinRequest,
  blockCrewMember,
  cancelJoinRequest,
  createCrew,
  crewBoard,
  crewHall,
  crewPage,
  declineJoinRequest,
  joinCrewByInvite,
  leaveCrew,
  myCrew,
  removeCrewMember,
  reportCrew,
  reportCrewSessions,
  requestToJoin,
  searchCrews,
  setShowsPet,
  updateCrew,
} from "../../core/crews/crewClient";
import { crewsDemo, CrewDemoData, CREW_DEMO_SCENARIOS, type CrewDemoScenario } from "../../core/crews/crewDemo";
import { crewNextChange } from "../../core/crews/crewFormat";
import {
  CrewCode,
  crewCrest,
  type CrewDetail,
  type CrewDraft,
  type CrewJoinRequest,
  type CrewMember,
  type CrewReportReason,
  type CrewSessionsReply,
  type CrewSummary,
  type CrewVisibility,
} from "../../core/crews/crewModels";
import { CrewSessionQueue, crewSessionFor, loadCrewSessionQueue, saveCrewSessionQueue } from "../../core/crews/crewSessionQueue";
import {
  cleanCrewText,
  crewDraftProblem,
  crewErrorMessage,
  crewsState,
  didLoadBoard,
  didLoadHall,
  didLoadMine,
  inCrew,
  popCrewScreen,
  showSection,
  type CrewDraftProblem,
  type CrewSection,
  type CrewsState,
} from "../../core/crews/crewsState";
import type { PartyCrewsPulse } from "../../core/party/partyModels";
import { tr } from "../../core/localization/tr";
import type { PartyAccount } from "../../core/party/partyAccount";
import { PartyError } from "../../core/party/partyError";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { Instant } from "../../core/time";
import { PARTY_FOLDER, type PartyStore } from "./partyStore";

/** How often the Crew section refreshes while it shows, in seconds. */
export const CREWS_REFRESH_INTERVAL = 60;
/** How long Find waits after a keystroke before it asks the server. */
export const CREWS_SEARCH_DELAY = 0.35;
/** How long a failed session report waits before trying again. */
export const CREWS_RETRY_INTERVAL = 600;

/** The action in flight. */
export type CrewAction =
  | {
      readonly kind: "save" | "join" | "leave" | "showPet" | "report" | "cancelRequest";
    }
  | {
      readonly kind: "open" | "remove" | "block" | "approve" | "decline";
      readonly id: string;
    };

/** What a crew report is about: a crew, or one member of it. */
export interface CrewReportTarget {
  readonly crew: CrewSummary;
  readonly member: CrewMember | undefined;
}

/** The crest editor, with the crest builder's choice. */
export interface CrewDraftForm {
  readonly name: string;
  readonly description: string;
  readonly crest: CrewCrest;
  readonly visibility: CrewVisibility;
}

export function emptyDraft(): CrewDraftForm {
  return {
    name: "",
    description: "",
    crest: defaultCrest(),
    visibility: "public",
  };
}

export function draftFrom(crew: CrewDetail): CrewDraftForm {
  return {
    name: crew.summary.name,
    description: crew.summary.description,
    crest: resolvedCrest(crewCrest(crew.summary)),
    visibility: crew.summary.visibility,
  };
}

/** A new random crest, never the one showing; the name stays. */
export function shuffledDraft(draft: CrewDraftForm, random: () => number = Math.random): CrewDraftForm {
  const current = draft.crest;
  let next = randomCrest(random);
  for (let tries = 0; tries < 32 && next.frame === current.frame && next.emblem === current.emblem && next.color === current.color; tries++) next = randomCrest(random);
  return { ...draft, crest: next };
}

export function draftProblem(draft: CrewDraftForm): CrewDraftProblem | undefined {
  return crewDraftProblem(draft.name, draft.description);
}

/** Only what changed, for `PATCH /v1/crews/mine`. */
function draftChanges(draft: CrewDraftForm, crew: CrewDetail): CrewDraft {
  const name = cleanCrewText(draft.name);
  const description = cleanCrewText(draft.description);
  const summary = crew.summary;
  return {
    ...(name === summary.name ? {} : { name }),
    ...(description === summary.description ? {} : { description }),
    ...(draft.crest.frame === summary.frame ? {} : { frame: draft.crest.frame }),
    ...(draft.crest.emblem === summary.emblem ? {} : { emblem: draft.crest.emblem }),
    ...(draft.crest.color === summary.color ? {} : { color: draft.crest.color }),
    ...(draft.visibility === summary.visibility ? {} : { visibility: draft.visibility }),
  };
}

export interface CrewsStoreState {
  readonly crews: CrewsState;
  /** The Party or Crews mode switch at the top left of the Party tab. */
  readonly showsCrews: boolean;
  readonly pending: CrewAction | undefined;
  /** What the crest editor holds while it is open. */
  readonly draft: CrewDraftForm;
  readonly reporting: CrewReportTarget | undefined;
  /** The More menu of My crew, while it is open. */
  readonly showsMoreMenu: boolean;
  /** Join requests waiting for the crew I own, from the heartbeat. */
  readonly waitingRequests: number;
  /** The moment the week's countdown measures against. */
  readonly now: Instant;
}

/** Snapshot states the Party module lists for Crews mode: every demo scenario, My crew's More menu, and the report card. */
export const CREW_SNAPSHOT_STATES: readonly string[] = [...CREW_DEMO_SCENARIOS.map((scenario) => `crew-${scenario}`), "crew-menu", "crew-report"];

/** The editor's draft a demo screen shows. */
function demoDraft(scenario: CrewDemoScenario, crews: CrewsState): CrewDraftForm {
  if (scenario === "edit" && crews.mine !== undefined) return draftFrom(crews.mine);
  if (scenario === "create") {
    const frames = crewFrames();
    const emblems = crewEmblems();
    const colors = crewColors();
    return {
      ...emptyDraft(),
      name: "Bibliotheksratten",
      crest: {
        frame: frames[1 % frames.length] as string,
        emblem: emblems[3 % emblems.length] as string,
        color: (colors[5 % colors.length] as { id: string }).id,
      },
    };
  }
  return emptyDraft();
}

type Timer = ReturnType<typeof setTimeout> | undefined;

export class CrewsStore extends Store<CrewsStoreState> {
  private readonly isDemo: boolean;
  private readonly isSnapshot: boolean;
  private readonly documents: DocumentStore | undefined;
  private queue = new CrewSessionQueue();
  private visible = false;
  private sending = false;
  private refreshTimer: Timer;
  private searchTimer: Timer;
  private retryTimer: Timer;
  private clockTimer: Timer;
  private searchGeneration = 0;
  /** The crew id the last heartbeat named, to notice an approval; undefined before the first pulse. */
  private pulseCrew: { readonly crew: string | undefined } | undefined;
  private readonly stops: (() => void)[] = [];

  constructor(
    private readonly context: ModuleContext,
    readonly party: PartyStore,
  ) {
    const now = context.now();
    const ephemeral = context.isDemo || context.isSnapshot;
    const crews = context.isDemo ? crewsDemo("week", now) : crewsState(now);
    super({
      crews,
      showsCrews: false,
      pending: undefined,
      draft: emptyDraft(),
      reporting: undefined,
      showsMoreMenu: false,
      waitingRequests: crews.mine?.requests.length ?? 0,
      now,
    });
    this.isDemo = context.isDemo;
    this.isSnapshot = context.isSnapshot;
    this.documents = ephemeral ? undefined : context.storage.folder(PARTY_FOLDER);
    if (ephemeral) return;
    void loadCrewSessionQueue(this.documents as DocumentStore).then((queue) => {
      for (const session of queue.pending) this.queue.add(session);
    });
    let connected = party.state.party.connection.kind === "connected";
    this.stops.push(
      party.subscribe(() => {
        const now = party.state.party.connection.kind === "connected";
        if (now === connected) return;
        connected = now;
        this.connectionDidChange(now);
      }),
      context.activityLog.recorded((record) => {
        const session = crewSessionFor(record);
        if (session !== undefined) this.queueSession(session);
      }),
      party.crewsPulse((pulse) => this.didReceive(pulse)),
    );
  }

  /** Follows the heartbeat's crews pulse: waiting requests badge the tab, and a crew appearing means my request was approved. */
  private didReceive(pulse: PartyCrewsPulse): void {
    this.setState({ waitingRequests: pulse.requests });
    const previous = this.pulseCrew;
    this.pulseCrew = { crew: pulse.crew };
    /* A different crew than last seen (approved, removed): fetch mine. */
    if (previous !== undefined && previous.crew !== pulse.crew) this.loadMine(true);
    else if (pulse.crew !== undefined && this.state.crews.mine?.summary.id !== pulse.crew && this.state.crews.mineLoaded) this.loadMine(true);
  }

  dispose(): void {
    for (const stop of this.stops.splice(0)) stop();
    for (const timer of [this.refreshTimer, this.searchTimer, this.retryTimer, this.clockTimer]) globalThis.clearTimeout(timer);
  }

  private setCrews(change: (crews: CrewsState) => CrewsState): void {
    this.setState({ crews: change(this.state.crews) });
  }

  /* MARK: Following the app */

  private queueSession(session: Parameters<CrewSessionQueue["add"]>[0]): void {
    /* Not in a crew (as last seen): nothing to count, so nothing is kept. */
    const crews = this.state.crews;
    if (!inCrew(crews) && crews.mineLoaded) return;
    this.queue.add(session);
    this.saveQueue();
    this.sendSessions();
  }

  private connectionDidChange(connected: boolean): void {
    if (!connected) {
      globalThis.clearTimeout(this.refreshTimer);
      return;
    }
    this.loadMine(true);
    if (this.visible && this.state.showsCrews) this.scheduleRefresh();
  }

  /** The Party panel appeared or went away. */
  setVisible(visible: boolean): void {
    this.visible = visible;
    if (visible && this.state.showsCrews) this.refreshNow();
    else globalThis.clearTimeout(this.refreshTimer);
    if (!visible) this.setState({ showsMoreMenu: false });
    this.scheduleClock();
  }

  /** Flips the Party or Crews mode switch. */
  setShowsCrews(shows: boolean): void {
    if (shows === this.state.showsCrews) return;
    this.setState({ showsCrews: shows, showsMoreMenu: false });
    if (shows && this.visible) this.refreshNow();
    else globalThis.clearTimeout(this.refreshTimer);
    this.scheduleClock();
  }

  /* MARK: Navigation */

  /** Goes to a section, closing any pushed screen. */
  show(section: CrewSection): void {
    this.setCrews((crews) => showSection(crews, section));
    this.setState({ showsMoreMenu: false });
    this.load(section);
  }

  /** Back from a crew page or the editor. */
  pop(): void {
    this.setCrews(popCrewScreen);
    this.setState({ showsMoreMenu: false });
  }

  setShowsMoreMenu(shows: boolean): void {
    this.setState({ showsMoreMenu: shows });
  }

  /** Opens a crew's page from a board, Find or a member. */
  openCrew(id: string): void {
    this.setState({ showsMoreMenu: false });
    const from = this.state.crews.section;
    const mine = this.state.crews.mine;
    if (mine !== undefined && mine.summary.id === id) {
      this.setCrews((crews) => showSection(crews, "mine"));
      return;
    }
    if (this.isDemo || this.isSnapshot) {
      const crew = new CrewDemoData(this.state.now, this.state.crews.week).detailFor(id);
      this.setCrews((crews) => ({
        ...crews,
        pushed: { kind: "crew", crew, from },
      }));
      return;
    }
    this.run({ kind: "open", id }, async (account) => {
      const crew = await account.perform((client) => crewPage(client, id));
      this.setCrews((crews) => ({
        ...crews,
        pushed: { kind: "crew", crew, from },
      }));
    });
  }

  /** Opens the crest editor for a new crew (with a random crest) or, for the owner, to edit mine. */
  openEditor(editing: boolean, random: () => number = Math.random): void {
    const mine = this.state.crews.mine;
    const owns = editing && mine !== undefined && mine.owner;
    this.setState({
      showsMoreMenu: false,
      draft: owns ? draftFrom(mine) : { ...emptyDraft(), crest: randomCrest(random) },
    });
    this.setCrews((crews) => ({
      ...crews,
      pushed: { kind: "editor", editing: owns, from: crews.section },
    }));
  }

  updateDraft(change: Partial<CrewDraftForm>): void {
    this.setState({ draft: { ...this.state.draft, ...change } });
  }

  /** Changes part of the draft's crest: its frame, emblem or color. */
  updateCrest(change: Partial<CrewCrest>): void {
    this.updateDraft({ crest: { ...this.state.draft.crest, ...change } });
  }

  /** The editor's Shuffle: a random frame, emblem and color, never the one showing. */
  shuffleCrest(random: () => number = Math.random): void {
    this.setState({ draft: shuffledDraft(this.state.draft, random) });
  }

  /* MARK: Actions */

  /** Creates my crew from the editor, or saves the owner's edit. */
  saveDraft(): void {
    const draft = this.state.draft;
    if (draftProblem(draft) !== undefined) return;
    if (this.isDemo || this.isSnapshot) {
      this.party.showNotice(tr("This is a demo. Run without TABBI_DEMO to make a crew."), false);
      return;
    }
    const mine = this.state.crews.mine;
    const pushed = this.state.crews.pushed;
    if (pushed?.kind === "editor" && pushed.editing && mine !== undefined) {
      const change = draftChanges(draft, mine);
      this.run({ kind: "save" }, async (account) => {
        const crew = await account.perform((client) => updateCrew(client, change));
        this.setCrews((crews) => showSection(didLoadMine(crews, crew, crews.week), "mine"));
        this.party.showNotice(tr("Saved."), true);
      });
      return;
    }
    this.run({ kind: "save" }, async (account) => {
      const crew = await account.perform((client) => createCrew(client, cleanCrewText(draft.name), cleanCrewText(draft.description), draft.crest, draft.visibility));
      this.setCrews((crews) => showSection(didLoadMine(crews, crew, crews.week), "mine"));
      this.loadBoard();
    });
  }

  /** Joins with a typed or pasted invite code (or a whole invite message): the invite is the owner's yes, so it joins at once. */
  joinInvite(text: string): void {
    const code = findCrewInvite(text);
    if (code === undefined) {
      this.party.showNotice(tr("Crew invite codes have %lld characters.", CrewCode.inviteLength), false);
      return;
    }
    if (this.isDemo || this.isSnapshot) return this.demoOnly();
    this.run({ kind: "join" }, async (account) => {
      const crew = await account.perform((client) => joinCrewByInvite(client, code));
      this.setCrews((crews) => showSection({ ...didLoadMine(crews, crew, crews.week), invite: undefined }, "mine"));
      this.party.showNotice(tr("You joined %@.", crew.summary.name), true);
      this.sendSessions();
    });
  }

  /** Asks to join a public crew; its owner lets me in. */
  requestToJoin(crew: CrewSummary): void {
    if (this.isDemo || this.isSnapshot) {
      const now = this.state.now;
      this.setCrews((crews) => ({
        ...crews,
        myRequest: { crew, requestedAt: now, expiresAt: now + 7 * 86_400 },
      }));
      return;
    }
    this.run({ kind: "join" }, async (account) => {
      const outcome = await account.perform((client) => requestToJoin(client, crew.id, this.context.now()));
      if (outcome.kind === "joined") {
        this.setCrews((crews) => showSection(didLoadMine(crews, outcome.crew, crews.week), "mine"));
        this.party.showNotice(tr("You joined %@.", outcome.crew.summary.name), true);
        this.sendSessions();
      } else {
        this.setCrews((crews) => ({ ...crews, myRequest: outcome.request }));
        this.party.showNotice(tr("Asked to join %@. Its owner lets you in.", crew.name), true);
      }
    });
  }

  /** Withdraws my pending request. */
  cancelRequest(): void {
    if (this.isDemo || this.isSnapshot) {
      this.setCrews((crews) => ({ ...crews, myRequest: undefined }));
      return;
    }
    this.run({ kind: "cancelRequest" }, async (account) => {
      await account.perform((client) => cancelJoinRequest(client));
      this.setCrews((crews) => ({ ...crews, myRequest: undefined }));
    });
  }

  /** The owner lets someone in. */
  approve(request: CrewJoinRequest): void {
    if (this.isDemo || this.isSnapshot) return this.dropRequest(request);
    this.run({ kind: "approve", id: request.ref }, async (account) => {
      const crew = await account.perform((client) => approveJoinRequest(client, request.ref));
      this.setCrews((crews) => didLoadMine(crews, crew, crews.week));
      this.setState({ waitingRequests: crew.requests.length });
      this.party.showNotice(tr("%@ joined the crew.", request.name), true);
    });
  }

  /** The owner says no, quietly: the request just goes away. */
  decline(request: CrewJoinRequest): void {
    if (this.isDemo || this.isSnapshot) return this.dropRequest(request);
    this.run({ kind: "decline", id: request.ref }, async (account) => {
      await account.perform((client) => declineJoinRequest(client, request.ref));
      this.dropRequest(request);
    });
  }

  private dropRequest(request: CrewJoinRequest): void {
    const mine = this.state.crews.mine;
    if (mine === undefined) return;
    const requests = mine.requests.filter((other) => other.ref !== request.ref);
    this.setCrews((crews) => didLoadMine(crews, { ...mine, requests }, crews.week));
    this.setState({ waitingRequests: requests.length });
  }

  leave(): void {
    this.setState({ showsMoreMenu: false });
    if (this.isDemo || this.isSnapshot) return this.demoOnly();
    const name = this.state.crews.mine?.summary.name ?? "";
    this.run({ kind: "leave" }, async (account) => {
      await account.perform((client) => leaveCrew(client));
      this.setCrews((crews) => didLoadMine(crews, undefined, crews.week));
      this.party.showNotice(tr("You left %@.", name), true);
    });
  }

  /** The owner takes a member out; they cannot join this crew again. */
  remove(member: CrewMember): void {
    if (this.isDemo || this.isSnapshot) return this.demoOnly();
    this.run({ kind: "remove", id: member.ref }, async (account) => {
      const crew = await account.perform((client) => removeCrewMember(client, member.ref));
      this.setCrews((crews) => didLoadMine(crews, crew, crews.week));
      this.party.showNotice(tr("Removed %@ from the crew.", member.name), true);
    });
  }

  /** Shows or hides my pet on crew pages. */
  setShowsPet(shows: boolean): void {
    this.setState({ showsMoreMenu: false });
    if (this.isDemo || this.isSnapshot) return this.demoOnly();
    this.run({ kind: "showPet" }, async (account) => {
      const crew = await account.perform((client) => setShowsPet(client, shows));
      this.setCrews((crews) => didLoadMine(crews, crew, crews.week));
    });
  }

  block(member: CrewMember, crew: CrewDetail): void {
    if (this.isDemo || this.isSnapshot) return this.demoOnly();
    this.run({ kind: "block", id: member.ref }, async (account) => {
      await account.perform((client) => blockCrewMember(client, crew.summary.id, member.ref));
      this.party.showNotice(tr("Blocked %@. Unblock them in Party options.", member.name), true);
      this.refreshNow();
    });
  }

  beginReport(target: CrewReportTarget): void {
    this.setState({ reporting: target, showsMoreMenu: false });
  }

  private demoOnly(): void {
    this.party.showNotice(tr("This is a demo. Run without TABBI_DEMO to study with a crew."), false);
  }

  cancelReport(): void {
    if (this.state.pending?.kind === "report") return;
    this.setState({ reporting: undefined });
  }

  sendReport(reason: CrewReportReason, note: string, alsoBlock: boolean): void {
    const target = this.state.reporting;
    if (target === undefined) return;
    if (this.isDemo || this.isSnapshot) {
      this.setState({ reporting: undefined });
      this.party.showNotice(tr("This is a demo. No report was sent."), true);
      return;
    }
    this.run({ kind: "report" }, async (account) => {
      await account.perform((client) => reportCrew(client, target.crew.id, target.member?.ref, reason, note));
      this.setState({ reporting: undefined });
      const member = target.member;
      if (alsoBlock && member !== undefined) {
        await account.perform((client) => blockCrewMember(client, target.crew.id, member.ref));
        this.party.showNotice(tr("Thanks. Your report was sent and %@ is blocked.", member.name), true);
        this.refreshNow();
      } else {
        this.party.showNotice(tr("Thanks. Your report was sent."), true);
      }
    });
  }

  /* MARK: Invites */

  /** A crew invite link was opened: My crew asks before joining. */
  openInvite(code: string): void {
    this.setCrews((crews) => ({ ...showSection(crews, "mine"), invite: code }));
    this.setShowsCrews(true);
  }

  dismissInvite(): void {
    this.setCrews((crews) => ({ ...crews, invite: undefined }));
  }

  /* MARK: Find */

  search(query: string): void {
    this.setCrews((crews) => ({ ...crews, query }));
    if (this.isDemo || this.isSnapshot) {
      const needle = query.trim().toLowerCase();
      const all = new CrewDemoData(this.state.now, this.state.crews.week).publicCrews;
      this.setCrews((crews) => ({
        ...crews,
        results: needle === "" ? all : all.filter((crew) => crew.name.toLowerCase().includes(needle)),
      }));
      return;
    }
    globalThis.clearTimeout(this.searchTimer);
    const account = this.party.crewAccount;
    if (account === undefined) return;
    const generation = ++this.searchGeneration;
    this.searchTimer = globalThis.setTimeout(() => {
      account
        .perform((client) => searchCrews(client, query))
        .then(
          (results) => {
            if (generation === this.searchGeneration && this.state.crews.query === query) this.setCrews((crews) => ({ ...crews, results }));
          },
          (error: unknown) => {
            if (generation === this.searchGeneration)
              this.setCrews((crews) => ({
                ...crews,
                loadError: CrewsStore.partyError(error),
              }));
          },
        );
    }, CREWS_SEARCH_DELAY * 1000);
  }

  /* MARK: Loading */

  /** Loads what a section shows. */
  private load(section: CrewSection): void {
    if (this.isDemo || this.isSnapshot) return;
    switch (section) {
      case "mine":
        this.loadMine(false);
        break;
      case "week":
        this.loadBoard();
        break;
      case "hall":
        this.loadHall();
        break;
      case "find":
        if (this.state.crews.results === undefined) this.search(this.state.crews.query);
        break;
    }
  }

  /** Retries after a failure ("Try again" in the offline state). */
  retry(): void {
    this.setCrews((crews) => ({ ...crews, loadError: undefined }));
    this.party.retry();
    this.refreshNow();
  }

  private refreshNow(): void {
    if (this.isDemo || this.isSnapshot) return;
    this.loadMine(false);
    this.load(this.state.crews.section);
    this.scheduleRefresh();
  }

  private scheduleRefresh(): void {
    globalThis.clearTimeout(this.refreshTimer);
    if (!this.visible || !this.state.showsCrews || this.isDemo || this.isSnapshot) return;
    this.refreshTimer = globalThis.setTimeout(() => this.refreshNow(), CREWS_REFRESH_INTERVAL * 1000);
  }

  private loadMine(thenSend: boolean): void {
    const account = this.party.crewAccount;
    if (this.isDemo || this.isSnapshot || account === undefined) return;
    account
      .perform((client) => myCrew(client))
      .then(
        ({ crew, week, request }) => {
          this.setCrews((crews) => didLoadMine(crews, crew, week, request));
          this.setState({ waitingRequests: crew?.requests.length ?? 0 });
          if (crew === undefined) {
            /* Nothing to count: forget sessions kept for a crew I left. */
            this.queue = new CrewSessionQueue();
            this.saveQueue();
          } else if (thenSend) {
            this.sendSessions();
          }
        },
        (error: unknown) =>
          this.setCrews((crews) => ({
            ...crews,
            loadError: CrewsStore.partyError(error),
          })),
      );
  }

  private loadBoard(): void {
    const account = this.party.crewAccount;
    if (this.isDemo || this.isSnapshot || account === undefined) return;
    account
      .perform((client) => crewBoard(client))
      .then(
        (board) => this.setCrews((crews) => didLoadBoard(crews, board)),
        (error: unknown) =>
          this.setCrews((crews) => ({
            ...crews,
            loadError: CrewsStore.partyError(error),
          })),
      );
  }

  /** The next page of the weekly board's rows, when the list scrolls near its end. */
  loadMoreBoard(): void {
    const account = this.party.crewAccount;
    const cursor = this.state.crews.board?.next;
    if (this.isDemo || this.isSnapshot || account === undefined || cursor === undefined) return;
    account
      .perform((client) => crewBoard(client, cursor))
      .then(
        (page) => this.setCrews((crews) => didLoadBoard(crews, page, true)),
        () => undefined,
      );
  }

  private loadHall(): void {
    const account = this.party.crewAccount;
    if (this.isDemo || this.isSnapshot || account === undefined) return;
    account
      .perform((client) => crewHall(client))
      .then(
        (page) => this.setCrews((crews) => didLoadHall(crews, page)),
        (error: unknown) =>
          this.setCrews((crews) => ({
            ...crews,
            loadError: CrewsStore.partyError(error),
          })),
      );
  }

  loadMoreHall(): void {
    const account = this.party.crewAccount;
    const cursor = this.state.crews.hallNext;
    if (this.isDemo || this.isSnapshot || account === undefined || cursor === undefined) return;
    account
      .perform((client) => crewHall(client, cursor))
      .then(
        (page) => this.setCrews((crews) => didLoadHall(crews, page, true)),
        () => undefined,
      );
  }

  /* MARK: Sessions */

  /** Sends the queued sessions in batches while I am in a crew; a transient failure keeps them and tries again later. */
  private sendSessions(): void {
    const account = this.party.crewAccount;
    if (this.sending || this.isDemo || this.isSnapshot || !inCrew(this.state.crews) || account === undefined) return;
    this.queue.prune(this.context.now());
    if (this.queue.pending.length === 0) return;
    this.sending = true;
    void this.sendBatches(account);
  }

  private async sendBatches(account: PartyAccount): Promise<void> {
    for (;;) {
      const batch = this.queue.nextBatch;
      if (batch.length === 0) break;
      try {
        const reply = await account.perform((client) => reportCrewSessions(client, batch));
        this.queue.didSend(batch);
        this.saveQueue();
        this.didReport(reply);
      } catch (error) {
        const failure = CrewsStore.partyError(error);
        if (!failure.isTransient) {
          /* The server refused the batch itself; it would refuse it again. */
          this.queue.didSend(batch);
          this.saveQueue();
          continue;
        }
        this.sending = false;
        globalThis.clearTimeout(this.retryTimer);
        this.retryTimer = globalThis.setTimeout(() => this.sendSessions(), CREWS_RETRY_INTERVAL * 1000);
        return;
      }
    }
    this.sending = false;
  }

  private didReport(reply: CrewSessionsReply): void {
    this.setCrews((crews) => {
      const mine = crews.mine;
      if (mine === undefined) return { ...crews, week: reply.week };
      const summary = reply.crewMinutes === undefined ? mine.summary : { ...mine.summary, weekMinutes: reply.crewMinutes };
      const members = mine.members.map((member) => (member.me ? { ...member, weekMinutes: reply.myMinutes } : member));
      return {
        ...crews,
        week: reply.week,
        mine: { ...mine, summary, members },
      };
    });
  }

  private saveQueue(): void {
    if (this.documents === undefined) return;
    saveCrewSessionQueue(this.documents, this.queue).catch((error: unknown) => this.context.logger.error("Could not save the crew sessions", error));
  }

  /* MARK: Plumbing */

  /** Ticks `now` when the countdown's text changes, only while it shows. */
  private scheduleClock(): void {
    globalThis.clearTimeout(this.clockTimer);
    const now = this.context.now();
    this.setState({ now });
    if (!this.visible || !this.state.showsCrews || this.isSnapshot) return;
    const next = crewNextChange(this.state.crews.week, now);
    this.clockTimer = globalThis.setTimeout(() => this.scheduleClock(), Math.max(1, next - now) * 1000);
  }

  /** Runs one action: one at a time, with its failure as the panel's notice. */
  private run(action: CrewAction, body: (account: PartyAccount) => Promise<void>): void {
    if (this.state.pending !== undefined) return;
    const account = this.party.crewAccount;
    if (account === undefined) {
      this.party.showNotice(crewErrorMessage(PartyError.of("unreachable")), false);
      return;
    }
    this.setState({ pending: action });
    body(account)
      .catch((error: unknown) => {
        const failure = CrewsStore.partyError(error);
        if (failure.kind === "server" && failure.code === "not_in_crew") this.setCrews((crews) => didLoadMine(crews, undefined, crews.week));
        this.party.showNotice(crewErrorMessage(failure), false);
      })
      .finally(() => this.setState({ pending: undefined }));
  }

  isPending(kind: CrewAction["kind"], id?: string): boolean {
    const pending = this.state.pending;
    return pending !== undefined && pending.kind === kind && (id === undefined || ("id" in pending && pending.id === id));
  }

  private static partyError(error: unknown): PartyError {
    return error instanceof PartyError ? error : PartyError.transport(error instanceof Error ? error.message : "failed");
  }

  /* MARK: Snapshots */

  /** Snapshot runs only: shows a Crews screen (`crew-<scenario>`, `crew-menu` or `crew-report`), or the Party side for anything else. */
  showSnapshotState(name: string): void {
    if (!this.isSnapshot) return;
    if (!name.startsWith("crew-")) {
      this.setState({
        showsCrews: false,
        reporting: undefined,
        showsMoreMenu: false,
      });
      return;
    }
    const now = this.context.now();
    if (name === "crew-report") {
      const crews = crewsDemo("crew", now);
      const shown = crews.pushed?.kind === "crew" ? crews.pushed.crew : undefined;
      this.setState({
        crews,
        showsCrews: true,
        now,
        showsMoreMenu: false,
        reporting: shown === undefined ? undefined : { crew: shown.summary, member: shown.members[0] },
      });
      return;
    }
    const scenario: CrewDemoScenario = name === "crew-menu" ? "mine" : (name.slice("crew-".length) as CrewDemoScenario);
    const crews = crewsDemo(scenario, now);
    this.setState({
      crews,
      showsCrews: true,
      now,
      reporting: undefined,
      showsMoreMenu: name === "crew-menu",
      draft: demoDraft(scenario, crews),
      waitingRequests: crews.mine?.requests.length ?? 0,
    });
  }
}
