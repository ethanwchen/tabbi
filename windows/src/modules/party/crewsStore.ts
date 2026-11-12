/*
 * Port of CrewsStore: the Party tab's Crew section: my crew, the weekly top
 * 3, Find and the New crew form, and the finished focus sessions it reports
 * to the board.
 *
 * It talks to the server through Party's identity (`PartyStore.crewAccount`)
 * and only while Party is connected, so Crews follows Party's age check, its
 * server setting and its invisible mode for free. Like Party it fetches only
 * while the Crew section is on screen, and never in a demo or snapshot run,
 * which show the demo crews.
 *
 * Sessions are the exception: they are queued as they finish (merged, so one
 * stretch is sent once) and sent in the background while I am in a crew,
 * since the board counts them whether or not the panel is open.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { findCrewInvite } from "../../core/crews/crewCatalog";
import { defaultCrest, randomCrest, resolvedCrest, type CrewCrest } from "../../core/crews/crewCrestArt";
import {
  blockCrewMember,
  createCrew,
  crewBoard,
  crewPage,
  joinCrewByID,
  joinCrewByInvite,
  leaveCrew,
  myCrew,
  removeCrewMember,
  reportCrew,
  reportCrewSessions,
  searchCrews,
  setShowsPet,
  updateCrew,
} from "../../core/crews/crewClient";
import { crewsDemo, demoCrewResults, demoNightOwls, DEMO_LOFI, DEMO_MED_SQUAD, type CrewDemoScenario } from "../../core/crews/crewDemo";
import { crewNextChange } from "../../core/crews/crewFormat";
import { CrewCode, crewCrest, type CrewDetail, type CrewDraft, type CrewMember, type CrewReportReason, type CrewSessionsReply, type CrewSummary, type CrewVisibility } from "../../core/crews/crewModels";
import { CrewSessionQueue, crewSessionFor, loadCrewSessionQueue, saveCrewSessionQueue } from "../../core/crews/crewSessionQueue";
import { cleanCrewText, crewDraftProblem, crewErrorMessage, crewsState, didLoadBoard, didLoadMine, inCrew, showSection, type CrewDraftProblem, type CrewSection, type CrewsState } from "../../core/crews/crewsState";
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
  | { readonly kind: "save" | "join" | "leave" | "showPet" | "report" }
  | { readonly kind: "open" | "remove" | "block"; readonly id: string };

/** What a crew report is about: a crew, or one member of it. */
export interface CrewReportTarget {
  readonly crew: CrewSummary;
  readonly member: CrewMember | undefined;
}

/** The New crew and Edit form. */
export interface CrewDraftForm {
  readonly name: string;
  readonly description: string;
  readonly crest: CrewCrest;
  readonly visibility: CrewVisibility;
}

export function emptyDraft(): CrewDraftForm {
  return { name: "", description: "", crest: defaultCrest(), visibility: "public" };
}

export function draftFrom(crew: CrewDetail): CrewDraftForm {
  return { name: crew.summary.name, description: crew.summary.description, crest: resolvedCrest(crewCrest(crew.summary)), visibility: crew.summary.visibility };
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
  /** The Party or Crew switch at the top left of the Party tab. */
  readonly showsCrews: boolean;
  readonly pending: CrewAction | undefined;
  readonly draft: CrewDraftForm;
  readonly reporting: CrewReportTarget | undefined;
  /** The moment the week's countdown measures against. */
  readonly now: Instant;
}

/** Snapshot states the Party module lists for the Crew section. */
export const CREW_SNAPSHOT_STATES = ["crew-mine", "crew-noCrew", "crew-create", "crew-edit", "crew-find", "crew-lastWeek", "crew-viewing", "crew-invite", "crew-report"] as const;

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
  private readonly stops: (() => void)[] = [];

  constructor(
    private readonly context: ModuleContext,
    readonly party: PartyStore,
  ) {
    const now = context.now();
    const ephemeral = context.isDemo || context.isSnapshot;
    super({
      crews: context.isDemo ? crewsDemo("mine", now) : crewsState(now),
      showsCrews: false,
      pending: undefined,
      draft: emptyDraft(),
      reporting: undefined,
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
    );
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
    this.scheduleClock();
  }

  /** Flips the Party or Crew switch. */
  setShowsCrews(shows: boolean): void {
    if (shows === this.state.showsCrews) return;
    this.setState({ showsCrews: shows });
    if (shows && this.visible) this.refreshNow();
    else globalThis.clearTimeout(this.refreshTimer);
    this.scheduleClock();
  }

  /* MARK: Navigation */

  show(section: CrewSection): void {
    this.setCrews((crews) => showSection(crews, section));
    if (section === "create") this.setState({ draft: emptyDraft() });
    if (section === "find" && this.state.crews.results === undefined) this.search(this.state.crews.query);
  }

  showLastWeek(shows: boolean): void {
    this.setCrews((crews) => ({ ...crews, showsLastWeek: shows && crews.board?.featured !== undefined }));
  }

  /** Opens a crew's page from the top 3 or Find. */
  openCrew(id: string): void {
    const mine = this.state.crews.mine;
    if (mine !== undefined && mine.summary.id === id) {
      this.setCrews((crews) => ({ ...crews, viewing: undefined, section: "mine" }));
      return;
    }
    if (this.isDemo || this.isSnapshot) {
      const known = [DEMO_MED_SQUAD, DEMO_LOFI];
      this.setCrews((crews) => ({ ...crews, viewing: known.find((crew) => crew.summary.id === id) ?? DEMO_MED_SQUAD }));
      return;
    }
    this.run({ kind: "open", id }, async (account) => {
      const crew = await account.perform((client) => crewPage(client, id));
      this.setCrews((crews) => ({ ...crews, viewing: crew }));
    });
  }

  closeCrewPage(): void {
    this.setCrews((crews) => ({ ...crews, viewing: undefined }));
  }

  beginEdit(): void {
    const mine = this.state.crews.mine;
    if (mine === undefined || !mine.owner) return;
    this.setState({ draft: draftFrom(mine) });
    this.setCrews((crews) => ({ ...crews, editing: true, viewing: undefined, section: "mine" }));
  }

  cancelEdit(): void {
    this.setCrews((crews) => ({ ...crews, editing: false, section: crews.section === "create" ? "mine" : crews.section }));
  }

  updateDraft(change: Partial<CrewDraftForm>): void {
    this.setState({ draft: { ...this.state.draft, ...change } });
  }

  /** Changes part of the draft's crest: its frame, emblem or color. */
  updateCrest(change: Partial<CrewCrest>): void {
    this.updateDraft({ crest: { ...this.state.draft.crest, ...change } });
  }

  /** The builder's Shuffle: a random frame, emblem and color. */
  shuffleCrest(random: () => number = Math.random): void {
    this.updateDraft({ crest: randomCrest(random) });
  }

  /* MARK: Actions */

  /** Creates my crew from the New crew form, or saves the owner's edit. */
  saveDraft(): void {
    const draft = this.state.draft;
    if (draftProblem(draft) !== undefined) return;
    if (this.isDemo || this.isSnapshot) {
      this.party.showNotice(tr("This is a demo. Run without TABBI_DEMO to make a crew."), false);
      return;
    }
    const mine = this.state.crews.mine;
    if (this.state.crews.editing && mine !== undefined) {
      const change = draftChanges(draft, mine);
      this.run({ kind: "save" }, async (account) => {
        const crew = await account.perform((client) => updateCrew(client, change));
        this.setCrews((crews) => ({ ...didLoadMine(crews, crew, crews.week), editing: false }));
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

  /** Joins with a typed or pasted invite code (or a whole invite message). */
  joinInvite(text: string): void {
    const code = findCrewInvite(text);
    if (code === undefined) {
      this.party.showNotice(tr("Crew invite codes have %lld characters.", CrewCode.inviteLength), false);
      return;
    }
    this.join({ invite: code });
  }

  /** Joins a public crew from Find or its page. */
  joinCrew(id: string): void {
    this.join({ crew: id });
  }

  private join(target: { invite: string } | { crew: string }): void {
    if (this.isDemo || this.isSnapshot) {
      this.party.showNotice(tr("This is a demo. Run without TABBI_DEMO to join a crew."), false);
      return;
    }
    this.run({ kind: "join" }, async (account) => {
      const crew = await account.perform((client) => ("invite" in target ? joinCrewByInvite(client, target.invite) : joinCrewByID(client, target.crew)));
      this.setCrews((crews) => showSection({ ...didLoadMine(crews, crew, crews.week), invite: undefined }, "mine"));
      this.party.showNotice(tr("You joined %@.", crew.summary.name), true);
      this.sendSessions();
    });
  }

  leave(): void {
    if (this.isDemo || this.isSnapshot) {
      this.party.showNotice(tr("This is a demo. Run without TABBI_DEMO to leave a crew."), false);
      return;
    }
    const name = this.state.crews.mine?.summary.name ?? "";
    this.run({ kind: "leave" }, async (account) => {
      await account.perform((client) => leaveCrew(client));
      this.setCrews((crews) => didLoadMine(crews, undefined, crews.week));
      this.party.showNotice(tr("You left %@.", name), true);
    });
  }

  /** The owner takes a member out; they cannot join this crew again. */
  remove(member: CrewMember): void {
    if (this.isDemo || this.isSnapshot) return;
    this.run({ kind: "remove", id: member.ref }, async (account) => {
      const crew = await account.perform((client) => removeCrewMember(client, member.ref));
      this.setCrews((crews) => didLoadMine(crews, crew, crews.week));
      this.party.showNotice(tr("Removed %@ from the crew.", member.name), true);
    });
  }

  /** Shows or hides my pet on crew pages. */
  setShowsPet(shows: boolean): void {
    if (this.isDemo || this.isSnapshot) {
      const mine = this.state.crews.mine;
      if (mine === undefined) return;
      const demo = demoNightOwls(this.context.now()).members;
      const members = mine.members.map((member, index) => (member.me ? { ...member, pet: shows ? demo[index]?.pet : undefined } : member));
      this.setCrews((crews) => ({ ...crews, mine: { ...mine, members } }));
      return;
    }
    this.run({ kind: "showPet" }, async (account) => {
      const crew = await account.perform((client) => setShowsPet(client, shows));
      this.setCrews((crews) => didLoadMine(crews, crew, crews.week));
    });
  }

  block(member: CrewMember, crew: CrewDetail): void {
    if (this.isDemo || this.isSnapshot) return;
    this.run({ kind: "block", id: member.ref }, async (account) => {
      await account.perform((client) => blockCrewMember(client, crew.summary.id, member.ref));
      this.party.showNotice(tr("Blocked %@. Unblock them in Party options.", member.name), true);
      this.refreshNow();
    });
  }

  beginReport(target: CrewReportTarget): void {
    this.setState({ reporting: target });
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

  /** A crew invite link was opened: the Crew section asks before joining. */
  openInvite(code: string): void {
    this.setCrews((crews) => ({ ...crews, invite: code, viewing: undefined, editing: false, section: "mine" }));
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
      const all = demoCrewResults();
      this.setCrews((crews) => ({ ...crews, results: needle === "" ? all : all.filter((crew) => crew.name.toLowerCase().includes(needle)) }));
      return;
    }
    globalThis.clearTimeout(this.searchTimer);
    const account = this.party.crewAccount;
    if (account === undefined) return;
    const generation = ++this.searchGeneration;
    this.searchTimer = globalThis.setTimeout(() => {
      account.perform((client) => searchCrews(client, query)).then(
        (results) => {
          if (generation === this.searchGeneration && this.state.crews.query === query) this.setCrews((crews) => ({ ...crews, results }));
        },
        (error: unknown) => {
          if (generation === this.searchGeneration) this.setCrews((crews) => ({ ...crews, loadError: CrewsStore.partyError(error) }));
        },
      );
    }, CREWS_SEARCH_DELAY * 1000);
  }

  /* MARK: Loading */

  private refreshNow(): void {
    if (this.isDemo || this.isSnapshot) return;
    this.loadMine(false);
    this.loadBoard();
    if (this.state.crews.section === "find") this.search(this.state.crews.query);
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
    account.perform((client) => myCrew(client)).then(
      ({ crew, week }) => {
        this.setCrews((crews) => didLoadMine(crews, crew, week));
        if (crew === undefined) {
          /* Nothing to count: forget sessions kept for a crew I left. */
          this.queue = new CrewSessionQueue();
          this.saveQueue();
        } else if (thenSend) {
          this.sendSessions();
        }
      },
      (error: unknown) => this.setCrews((crews) => ({ ...crews, loadError: CrewsStore.partyError(error) })),
    );
  }

  private loadBoard(): void {
    const account = this.party.crewAccount;
    if (this.isDemo || this.isSnapshot || account === undefined) return;
    account.perform((client) => crewBoard(client)).then(
      (board) => this.setCrews((crews) => didLoadBoard(crews, board)),
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
      return { ...crews, week: reply.week, mine: { ...mine, summary, members } };
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

  /** Snapshot runs only: shows a Crew screen (`crew-<scenario>` or `crew-report`), or the Party side for anything else. */
  showSnapshotState(name: string): void {
    if (!this.isSnapshot) return;
    if (!name.startsWith("crew-")) {
      this.setState({ showsCrews: false, reporting: undefined });
      return;
    }
    const now = this.context.now();
    if (name === "crew-report") {
      const crews = crewsDemo("viewing", now);
      const viewing = crews.viewing;
      this.setState({ crews, showsCrews: true, now, reporting: viewing === undefined ? undefined : { crew: viewing.summary, member: viewing.members[0] } });
      return;
    }
    const scenario = name.slice("crew-".length) as CrewDemoScenario;
    const crews = crewsDemo(scenario, now);
    this.setState({ crews, showsCrews: true, now, reporting: undefined, draft: scenario === "edit" && crews.mine !== undefined ? draftFrom(crews.mine) : emptyDraft() });
  }
}
