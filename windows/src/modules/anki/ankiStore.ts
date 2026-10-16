/*
 * Port of AnkiStore: the Anki tab's connection to AnkiConnect and today's
 * summary. It refreshes when the module starts, when the panel opens, on a
 * timer only while the panel shows or the closed island's progress preview
 * can show Anki's numbers (fast during setup steps, every few minutes once
 * connected), and after Sync or a click on a deck. A problem (Anki syncing,
 * a dialog open) is retried every few seconds for its first minute even
 * with nothing on screen, then less often and only while someone looks
 * (`AnkiRecovery`). The rest of the time nothing polls.
 *
 * Windows has no way to see whether Anki is installed or running, so the
 * HTTP probe is the only truth: a refused connection reads as "Anki is
 * closed" (the Mac's `notRunning`), never as "not installed", and opening
 * a deck asks AnkiConnect rather than launching Anki.
 *
 * Demo and snapshot runs show the sample summary and never call the host.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { AnkiConnectClient } from "../../core/anki/ankiConnectClient";
import { AnkiConnectFailure, AnkiErrors, type AnkiConnectError } from "../../core/anki/ankiConnectError";
import type { AnkiDeckStats } from "../../core/anki/ankiConnectModels";
import {
  ankiConnectionStateFromPreviewName,
  keepsLastSummary,
  pollsWhileHidden,
  refreshInterval,
  resolveAnkiConnectionState,
  type AnkiConnectionState,
} from "../../core/anki/ankiConnectionState";
import { normalizedDeckName } from "../../core/anki/ankiDeckName";
import {
  decodeFavoriteDeck,
  encodedFavoriteDeck,
  favoriteFromDeck,
  favoriteMatches,
  resolveFavorite,
  updatedFavorite,
  type AnkiFavoriteDeck,
} from "../../core/anki/ankiFavoriteDeck";
import {
  ankiProgressItem,
  demoAnkiSummary,
  fetchAnkiSummary,
  fillingSummary,
  isSummaryCurrent,
  nextRollover,
  reviewActivity,
  studyDeck,
  topDecks,
  type AnkiSummary,
} from "../../core/anki/ankiSummary";
import { isEphemeral } from "../../core/modules/runMode";
import { addingDaysToKey, plannerDayKeyOf } from "../../core/planner/plannerDayKey";
import type { DocumentStore } from "../../core/persistence/documentStore";
import { moduleProvision, type ModuleProvision } from "../../core/providers/moduleProvision";
import { TICKER_KINDS } from "../../core/ticker/tickerKind";
import type { Instant, Seconds } from "../../core/time";
import { hostAnkiTransport } from "./ankiTransport";

/** A click opening a deck in Anki, while AnkiConnect answers. */
export interface AnkiOpening {
  /** The full deck name, or undefined when only Anki's deck list is asked for. */
  readonly deck: string | undefined;
}

/** How the last click on a deck went, when it did not simply open. Port of AnkiOpenOutcome's failures. */
export type AnkiOpenNotice =
  /** Nothing answered on the port: Anki is closed or the add-on is missing. */
  | { readonly kind: "ankiClosed" }
  /** Anki runs but has no deck of that name any more. */
  | { readonly kind: "deckNotFound"; readonly deck: string }
  | { readonly kind: "failed"; readonly error: AnkiConnectError };

export interface AnkiStoreState {
  readonly connection: AnkiConnectionState;
  /** The latest good summary; kept through transient problems. */
  readonly summary: AnkiSummary | undefined;
  readonly updatedAt: Instant | undefined;
  readonly isRefreshing: boolean;
  readonly isSyncing: boolean;
  /** The last Sync failure, shown briefly in the panel. */
  readonly actionError: AnkiConnectError | undefined;
  readonly opening: AnkiOpening | undefined;
  readonly openNotice: AnkiOpenNotice | undefined;
  /** The deck the user pinned for the one-click Study button. */
  readonly favorite: AnkiFavoriteDeck | undefined;
  /** The decks card expanded to every deck with cards due. */
  readonly showsAllDecks: boolean;
  /** Bumped at each Anki-day rollover so the provision re-checks whether the summary is still today's. */
  readonly rollover: number;
}

export interface AnkiStoreOptions {
  /** Replaces the host-backed client (tests). */
  readonly client?: AnkiConnectClient;
}

/** Where the favorite is kept: the Mac's `anki.favoriteDeck` preference, as a document in the Anki folder here. */
export const ANKI_FAVORITE_DOCUMENT = "favorite.json";

/** The demo student's pinned deck. */
const DEMO_FAVORITE = "Spanish verbs";
/** How long a failed Sync or a failed click stays up. */
const ACTION_ERROR_LIFETIME: Seconds = 8;
/** The longest wait a timer can take; a longer one is re-armed when it fires. */
const MAX_TIMER_MS = 2 ** 31 - 1;

/** The names `showSnapshotState` understands besides the connection states. */
export const ANKI_SNAPSHOT_STATES = [
  "allDecks",
  "allDone",
  "noDecks",
  "checking",
  "notInstalled",
  "notRunning",
  "starting",
  "addOnMissing",
  "apiKey",
  "permission",
  "addOnOutdated",
  "collection",
  "problem",
  "deckCountsUnavailable",
  "opening",
] as const;

export class AnkiStore extends Store<AnkiStoreState> {
  readonly isDemo: boolean;
  private readonly isStatic: boolean;
  private readonly client: AnkiConnectClient;
  private readonly documents: DocumentStore | undefined;
  private refreshController: AbortController | undefined;
  private pollTimer: ReturnType<typeof setTimeout> | undefined;
  private rolloverTimer: ReturnType<typeof setTimeout> | undefined;
  private actionErrorTimer: ReturnType<typeof setTimeout> | undefined;
  private openNoticeTimer: ReturnType<typeof setTimeout> | undefined;
  private openController: AbortController | undefined;
  private isStarted = false;
  private isPanelVisible = false;
  /** The closed island can show the progress preview, so Today and the ticker read fresh numbers. */
  private tickerWatches = false;
  private stopWatching: (() => void) | undefined;
  /** When the current run of `problem` refreshes began, for the retry pace. */
  private problemSince: Instant | undefined;

  constructor(
    private readonly context: ModuleContext,
    options: AnkiStoreOptions = {},
  ) {
    super({
      connection: { kind: "checking" },
      summary: undefined,
      updatedAt: undefined,
      isRefreshing: false,
      isSyncing: false,
      actionError: undefined,
      opening: undefined,
      openNotice: undefined,
      favorite: undefined,
      showsAllDecks: false,
      rollover: 0,
    });
    this.isDemo = context.isDemo;
    this.isStatic = isEphemeral(context.runMode);
    this.client =
      options.client ??
      new AnkiConnectClient({
        transport: hostAnkiTransport((request) => context.host.httpRequest(request)),
        onError: (action, error) => context.logger.error(`AnkiConnect ${action} failed: ${JSON.stringify(error)}`),
      });
    this.documents = this.isStatic ? undefined : context.storage.folder("Anki");
    if (this.isStatic) {
      this.showDemo();
    } else {
      void this.loadFavorite();
    }
  }

  /* MARK: Derived */

  /** The clock, for the stale notice's age. */
  now(): Instant {
    return this.context.now();
  }

  /** Why the shown numbers may be stale: a failed refresh, or else the last failed Sync. */
  get problem(): AnkiConnectError | undefined {
    const connection = this.state.connection;
    if (connection.kind === "problem") return connection.error;
    return this.state.actionError;
  }

  /** The favorite's current counts, when the summary has its deck. */
  get favoriteDeck(): AnkiDeckStats | undefined {
    const { favorite, summary } = this.state;
    if (favorite === undefined || summary === undefined) return undefined;
    return resolveFavorite(favorite, summary.decks);
  }

  isFavorite(deck: AnkiDeckStats): boolean {
    const favorite = this.state.favorite;
    return favorite !== undefined && favoriteMatches(favorite, deck);
  }

  /** Today's reviews as a shared progress goal, while the summary is current; yesterday's numbers are never shared as today's. */
  provision(): ModuleProvision {
    const { summary, favorite } = this.state;
    if (summary === undefined || !isSummaryCurrent(summary, this.context.now(), this.context.timeZone())) return moduleProvision();
    return moduleProvision({ progress: [ankiProgressItem(summary, this.context.id, favorite)] });
  }

  /* MARK: Lifecycle */

  /** The module was enabled: fetch once so Today and the ticker have numbers, then follow the day. */
  start(): void {
    if (this.isStarted) return;
    this.isStarted = true;
    if (this.isStatic) return;
    this.stopWatching = this.context.closedPreview.watchedKinds.subscribe(() => this.tickerDidChange());
    this.tickerDidChange();
    this.refresh();
    this.scheduleRollover();
  }

  stop(): void {
    if (!this.isStarted) return;
    this.isStarted = false;
    this.stopWatching?.();
    this.stopWatching = undefined;
    this.refreshController?.abort();
    this.refreshController = undefined;
    this.openController?.abort();
    this.openController = undefined;
    globalThis.clearTimeout(this.rolloverTimer);
    globalThis.clearTimeout(this.actionErrorTimer);
    globalThis.clearTimeout(this.openNoticeTimer);
    this.problemSince = undefined;
    this.stopPolling();
    this.setState({ isRefreshing: false, actionError: undefined, opening: undefined, openNotice: undefined });
  }

  panelDidAppear(): void {
    this.isPanelVisible = true;
    if (this.isStatic) return;
    this.refresh();
    this.schedulePoll();
  }

  panelDidDisappear(): void {
    this.isPanelVisible = false;
    if (!this.shouldPoll) this.stopPolling();
  }

  private tickerDidChange(): void {
    const watches = this.context.closedPreview.watchedKinds.get().has(TICKER_KINDS.progress);
    if (watches === this.tickerWatches) return;
    this.tickerWatches = watches;
    if (this.shouldPoll) this.schedulePoll();
    else this.stopPolling();
  }

  /* MARK: Refresh */

  /** Fetches the summary. A refresh already in flight is replaced, so the newest request always wins. */
  refresh(): void {
    if (this.isStatic || !this.isStarted) return;
    this.refreshController?.abort();
    const controller = new AbortController();
    this.refreshController = controller;
    this.setState({ isRefreshing: true });
    fetchAnkiSummary(this.client, { now: this.context.now(), timeZone: this.context.timeZone(), signal: controller.signal }).then(
      (summary) => {
        if (controller.signal.aborted) return;
        this.finishRefresh({ ok: true, summary });
      },
      (error: unknown) => {
        if (controller.signal.aborted) return;
        if (error instanceof AnkiConnectFailure) this.finishRefresh({ ok: false, error: error.error });
        else this.finishRefresh({ ok: false, error: AnkiErrors.transport(error instanceof Error ? error.message : String(error)) });
      },
    );
  }

  private finishRefresh(outcome: { ok: true; summary: AnkiSummary } | { ok: false; error: AnkiConnectError }): void {
    this.refreshController = undefined;
    const now = this.context.now();
    if (outcome.ok) {
      /* A piece Anki couldn't send keeps what the last summary showed. */
      const value = fillingSummary(outcome.summary, this.state.summary);
      for (const gap of outcome.summary.gaps) this.context.logger.info(`Anki summary without ${gap.action}: ${gap.message}`);
      const favorite = this.state.favorite;
      const current = favorite === undefined ? undefined : updatedFavorite(favorite, value.decks);
      if (current !== undefined) this.saveFavorite(current);
      this.setState({ summary: value, updatedAt: now, connection: { kind: "ready" }, isRefreshing: false });
      /* Placeholder counts must not be logged. */
      if (!value.missing.has("todayCount")) void this.logReviews(value, now);
    } else {
      const connection = resolveAnkiConnectionState(outcome.error, true, undefined, now);
      this.setState({ connection, isRefreshing: false, ...(keepsLastSummary(connection) ? {} : { summary: undefined }) });
    }
    if (this.state.connection.kind === "problem") this.problemSince ??= now;
    else this.problemSince = undefined;
    if (this.shouldPoll) this.schedulePoll();
    else this.stopPolling();
  }

  /**
   * Logs the cards answered since the last logged count. The log is read
   * back each time (yesterday and today, which covers Anki's rollover), so
   * a relaunch never logs the same cards twice.
   */
  private async logReviews(summary: AnkiSummary, now: Instant): Promise<void> {
    const log = this.context.activityLog;
    const today = plannerDayKeyOf(now, this.context.timeZone());
    const logged = await log.recordsBetween(addingDaysToKey(today, -1), today);
    const record = reviewActivity(summary, logged, this.context.id, now);
    if (record !== undefined) await log.record(record);
  }

  /** One timer at a time, re-armed after every refresh with the interval the current state calls for. */
  private schedulePoll(): void {
    globalThis.clearTimeout(this.pollTimer);
    const interval = refreshInterval(this.state.connection, this.problemAge);
    this.pollTimer = globalThis.setTimeout(() => {
      this.pollTimer = undefined;
      if (this.shouldPoll) this.refresh();
    }, interval * 1000);
  }

  /** Polls run while the panel shows, while the closed island can show the numbers, while Anki starts, and in a problem's first minute. */
  private get shouldPoll(): boolean {
    if (!this.isStarted || this.isStatic) return false;
    return this.isPanelVisible || this.tickerWatches || pollsWhileHidden(this.state.connection, this.problemAge);
  }

  /** How long the current problem has lasted; 0 outside one. */
  private get problemAge(): Seconds {
    return this.problemSince === undefined ? 0 : this.context.now() - this.problemSince;
  }

  private stopPolling(): void {
    globalThis.clearTimeout(this.pollTimer);
    this.pollTimer = undefined;
  }

  /** Once a day, at Anki's rollover: stop sharing yesterday's numbers and fetch the new day's. One wake-up per day, not a poll. */
  private scheduleRollover(): void {
    globalThis.clearTimeout(this.rolloverTimer);
    const now = this.context.now();
    const delay = Math.max(nextRollover(now, this.context.timeZone()) - now, 1);
    this.rolloverTimer = globalThis.setTimeout(
      () => {
        if (!this.isStarted) return;
        if (delay * 1000 > MAX_TIMER_MS) {
          this.scheduleRollover();
          return;
        }
        this.setState((state) => ({ rollover: state.rollover + 1 }));
        this.refresh();
        this.scheduleRollover();
      },
      Math.min(delay * 1000, MAX_TIMER_MS),
    );
  }

  /* MARK: Actions */

  /** Opens the Anki download page in the browser. */
  getAnki(): void {
    if (this.isStatic) return;
    void this.context.host.openUrl("https://apps.ankiweb.net").catch((error: unknown) => this.context.logger.error("Could not open the Anki site", error));
  }

  /** Shows every deck with cards due, or the top decks beside the ring again. */
  setShowsAllDecks(shows: boolean): void {
    this.setState({ showsAllDecks: shows });
  }

  /**
   * One click on a deck: asks AnkiConnect to open `deck` (or the deck with
   * the most due) for review. A newer click replaces one still waiting.
   */
  startReviews(deck?: string): void {
    if (this.isStatic) return;
    const summary = this.state.summary;
    const raw = deck ?? (summary === undefined ? undefined : topDecks(summary)[0]?.name);
    const name = raw === undefined ? undefined : normalizedDeckName(raw);
    this.openController?.abort();
    const controller = new AbortController();
    this.openController = controller;
    this.setState({ opening: { deck: name }, openNotice: undefined });
    const open = name === undefined ? this.client.guiDeckOverview("Default", controller.signal).then(() => true) : this.client.guiDeckReview(name, controller.signal);
    open.then(
      (opened) => {
        if (controller.signal.aborted) return;
        this.finishOpening(opened || name === undefined ? undefined : { kind: "deckNotFound", deck: name });
      },
      (error: unknown) => {
        if (controller.signal.aborted) return;
        if (error instanceof AnkiConnectFailure) {
          const kind = error.error.kind;
          this.finishOpening(kind === "ankiNotRunning" || kind === "addOnMissing" ? { kind: "ankiClosed" } : { kind: "failed", error: error.error });
        } else {
          this.finishOpening({ kind: "failed", error: AnkiErrors.transport(error instanceof Error ? error.message : String(error)) });
        }
      },
    );
  }

  private finishOpening(notice: AnkiOpenNotice | undefined): void {
    this.openController = undefined;
    if (!this.isStarted) return;
    this.setState({ opening: undefined, openNotice: notice, ...(notice === undefined ? { actionError: undefined } : {}) });
    this.scheduleOpenNoticeExpiry();
    /* A missing deck changes what Anki has to show. */
    this.refresh();
  }

  /** Clears a failed click's notice after a while, so one failed click doesn't leave a warning up for good. */
  private scheduleOpenNoticeExpiry(): void {
    globalThis.clearTimeout(this.openNoticeTimer);
    if (this.state.openNotice === undefined || this.isStatic) return;
    this.openNoticeTimer = globalThis.setTimeout(() => this.setState({ openNotice: undefined }), ACTION_ERROR_LIFETIME * 1000);
  }

  /** Pins `deck` as the Study button's deck, or unpins it when it is already the favorite. */
  toggleFavorite(deck: AnkiDeckStats): void {
    this.saveFavorite(this.isFavorite(deck) ? undefined : favoriteFromDeck(deck));
  }

  /** Opens the favorite deck, falling back to the deck with the most due. */
  studyFavorite(): void {
    this.startReviews(this.favoriteDeck?.name ?? this.state.favorite?.name);
  }

  /** The one-click study from Today's Anki row or the closed island's Anki preview: the favorite deck, else the deck with the most due. */
  studyFromShared(): void {
    const { summary, favorite } = this.state;
    this.startReviews(summary === undefined ? favorite?.name : (studyDeck(summary, favorite) ?? favorite?.name));
  }

  private saveFavorite(favorite: AnkiFavoriteDeck | undefined): void {
    this.setState({ favorite });
    const documents = this.documents;
    if (documents === undefined) return;
    const write = favorite === undefined ? documents.remove(ANKI_FAVORITE_DOCUMENT) : documents.write(ANKI_FAVORITE_DOCUMENT, encodedFavoriteDeck(favorite));
    write.catch((error: unknown) => this.context.logger.error("Could not save the favorite deck", error));
  }

  private async loadFavorite(): Promise<void> {
    const documents = this.documents;
    if (documents === undefined) return;
    try {
      const favorite = decodeFavoriteDeck(await documents.read(ANKI_FAVORITE_DOCUMENT));
      if (favorite !== undefined && this.state.favorite === undefined) this.setState({ favorite });
    } catch (error) {
      this.context.logger.error("Could not read the favorite deck", error);
    }
  }

  /** Syncs with AnkiWeb, then refreshes the counts. */
  sync(): void {
    if (this.isStatic || this.state.isSyncing || !this.isStarted) return;
    this.setState({ isSyncing: true, actionError: undefined });
    this.client.sync().then(
      () => this.finishSync(undefined),
      (error: unknown) => this.finishSync(error instanceof AnkiConnectFailure ? error.error : AnkiErrors.transport(error instanceof Error ? error.message : String(error))),
    );
  }

  private finishSync(failure: AnkiConnectError | undefined): void {
    this.setState({ isSyncing: false });
    if (!this.isStarted) return;
    this.setState({ actionError: failure });
    globalThis.clearTimeout(this.actionErrorTimer);
    if (failure !== undefined) this.actionErrorTimer = globalThis.setTimeout(() => this.setState({ actionError: undefined }), ACTION_ERROR_LIFETIME * 1000);
    this.refresh();
  }

  /* MARK: Demo and snapshots */

  private demoSummary(): AnkiSummary {
    return demoAnkiSummary(this.context.now(), this.context.timeZone());
  }

  private showDemo(): void {
    const summary = this.demoSummary();
    const deck = summary.decks.find((candidate) => candidate.name === DEMO_FAVORITE);
    this.setState({
      summary,
      updatedAt: this.context.now(),
      connection: { kind: "ready" },
      favorite: deck === undefined ? { name: DEMO_FAVORITE } : favoriteFromDeck(deck),
      showsAllDecks: false,
      opening: undefined,
      openNotice: undefined,
      actionError: undefined,
    });
  }

  /** Puts the store into one of `ANKI_SNAPSHOT_STATES` (snapshot runs only). */
  showSnapshotState(name: string): void {
    if (!this.context.isSnapshot) return;
    this.showDemo();
    const now = this.context.now();
    const summary = this.demoSummary();
    const caughtUp: AnkiSummary = {
      ...summary,
      newDue: 0,
      learnDue: 0,
      reviewDue: 0,
      reviewedToday: 112,
      decks: summary.decks.map((deck) => ({ ...deck, newCount: 0, learnCount: 0, reviewCount: 0 })),
    };
    switch (name) {
      case "allDecks":
        this.setState({ showsAllDecks: true });
        return;
      case "allDone":
        this.setState({ summary: caughtUp });
        return;
      case "noDecks":
        this.setState({
          summary: { ...caughtUp, reviewedToday: 0, streak: 0, decks: [], history: summary.history.map((entry) => ({ ...entry, count: 0 })) },
          favorite: undefined,
        });
        return;
      case "opening":
        this.setState({ opening: { deck: topDecks(summary)[0]?.name } });
        return;
      case "problem":
        /* A transient problem keeps the last numbers, dimmed as stale. */
        this.setState({ connection: { kind: "problem", error: AnkiErrors.timeout }, updatedAt: now - 9 * 60 });
        return;
      case "deckCountsUnavailable":
        this.setState({ connection: { kind: "problem", error: AnkiErrors.anki("Deck counts unavailable.") }, summary: undefined });
        return;
      default: {
        const connection = ankiConnectionStateFromPreviewName(name);
        if (connection === undefined) return;
        this.setState({ connection, ...(keepsLastSummary(connection) && connection.kind !== "checking" ? {} : { summary: undefined }) });
      }
    }
  }
}
