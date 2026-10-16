/*
 * Port of StudyStore: the Study tab's timer. It owns the `StudySession` so
 * a block keeps running while the island is closed or another tab shows.
 *
 * Like `FocusStore`, time comes from wall-clock instants. A wall-clock
 * alarm fires at the running phase's end to roll into the next phase, and
 * the view only ticks once a second while the panel is visible. The
 * session is saved on every change so a relaunch picks up where it was.
 * Finished stretches move from the session into the persisted `StudyLog`,
 * which totals the day and holds the points the pet earned. With deep
 * focus on, study phases drive the shared focus mode (the focus sound)
 * through `focusMode(context)`, alongside the Focus timer. It also plays
 * the corner pet, which dozes while the clock is stopped, wakes when it
 * runs and celebrates each finished block (`StudyPetCue`). In demo mode it
 * shows a sample Pomodoro round and a sample day, and never touches sounds
 * or disk.
 */

import type { ModuleContext } from "../../app/context";
import { Emitter, Store } from "../../app/store";
import { phaseActivityRecord } from "../../core/studyMethods/studyPhaseRecord";
import { startOfDay } from "../../core/calendar/zonedCalendar";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { defaultsBool, defaultsInteger, defaultsString } from "../../core/persistence/defaults";
import { stringifyJSON } from "../../core/persistence/json";
import type { PetProfile } from "../../core/pets/petProfile";
import { newUUID } from "../../core/planner/uuid";
import type { ProviderSnapshot } from "../../core/providers/providerSnapshot";
import type { ProvidedPartySession } from "../../core/providers/providedParty";
import { cardsReviewedToday } from "../../core/studyMethods/studyCardFeed";
import { StudyCustomRhythm, presetMethod } from "../../core/studyMethods/studyCustomRhythm";
import { StudyDailyGoal } from "../../core/studyMethods/studyDailyGoal";
import { studyFocusActivity } from "../../core/studyMethods/studyFocusShare";
import { loadStudyLog, STUDY_LOG_DOCUMENT_NAME, StudyLog, writeStudyLog } from "../../core/studyMethods/studyLog";
import type { StudyMethodKind } from "../../core/studyMethods/studyMethod";
import { StudyMethodMenu } from "../../core/studyMethods/studyMethodMenu";
import { studyPetEvents, studyPetIsDozing } from "../../core/studyMethods/studyPetCue";
import { StudySession } from "../../core/studyMethods/studySession";
import { decodeStudySession, encodeStudySession } from "../../core/studyMethods/studySessionStorage";
import type { StudyPhaseRecord } from "../../core/studyMethods/studyPhaseRecord";
import { StudyTimerLength } from "../../core/studyMethods/studyTimerLength";
import type { Instant, Seconds } from "../../core/time";
import { WallClockAlarm } from "../../ui/kit/clock";
import { PetPlayer } from "../../ui/kit/petPlayer";
import type { FocusController } from "../focus/focusController";
import { HEARTBEAT_INTERVAL_SECONDS } from "../focus/focusStore";
import type { ModulePreferences } from "../focus/modulePreferences";

/**
 * What covers the timer: the method picker, a method's info view that
 * returns to wherever it was opened from, the sound mixer, or the Custom
 * method's lengths. Port of StudyPanelOverlay.
 */
export type StudyPanelOverlay =
  | { readonly kind: "picker" }
  | { readonly kind: "info"; readonly method: StudyMethodKind; readonly from: StudyPanelOverlay | undefined }
  | { readonly kind: "sounds" }
  | { readonly kind: "custom" };

export interface StudyState {
  readonly session: StudySession;
  /** Whether study phases turn on focus mode. Opt-in, like the focus sound. */
  readonly deepFocus: boolean;
  /** The moment the view measures against; advances every second while visible. */
  readonly now: Instant;
  /** Every logged study stretch and the points earned. */
  readonly log: StudyLog;
  /** The methods the picker offers and where a fresh timer starts, set by the kit. */
  readonly menu: StudyMethodMenu;
  /** The user's own lengths for the Custom method. */
  readonly custom: StudyCustomRhythm;
  /** How long the plain Timer counts down. */
  readonly timer: StudyTimerLength;
  /** Minutes a day to aim for, set by the kit; shared with Today as progress. */
  readonly goal: StudyDailyGoal;
  /** Cards reviewed today from the modules that share a card goal (Anki), or undefined when none does. */
  readonly cardsReviewedToday: number | undefined;
  /** The party's shared session while the user is in it: the panel shows it in place of the user's own timer. */
  readonly partySession: ProvidedPartySession | undefined;
  /** What the panel shows over the timer, or undefined for the timer. */
  readonly overlay: StudyPanelOverlay | undefined;
}

const SESSION_KEY = "study.session";
const DEEP_FOCUS_KEY = "study.deepFocus";
const CUSTOM_KEY = "study.custom";
const TIMER_KEY = "study.timerMinutes";
/** The last moment a session under way was known to run, in seconds since 1970. */
const LAST_ALIVE_KEY = "study.lastAlive";

/** Fresh phase ends older than this stay quiet: the PC was asleep or Tabbi busy. */
const FRESH_END_SECONDS = 60;
/** A heartbeat this late means the PC slept: the session ends at the last beat. */
const SLEEP_GAP_SECONDS = 120;

/** Time left in the demo Pomodoro's focus block: about a quarter of its 25 minutes gone, as the App Store's first screenshot shows it. */
export const DEMO_FOCUS_LEFT: Seconds = 18 * 60 + 42;

/** A 45/10 rhythm with a long break every third round. */
const DEMO_CUSTOM = new StudyCustomRhythm({ focusMinutes: 45, breakMinutes: 10, longBreakMinutes: 25, longBreakEvery: 3, hasLongBreak: true });

export interface StudyStoreOptions {
  readonly menu: StudyMethodMenu;
  readonly goal: StudyDailyGoal;
  readonly preferences: ModulePreferences;
  readonly focusMode?: FocusController;
  readonly petProfile: PetProfile;
}

export class StudyStore extends Store<StudyState> {
  /** The pet in the panel's corner, wearing the look saved by the Closet. */
  readonly pet: PetPlayer;
  /** A paw print burst to play over the panel when a block finishes in view. */
  readonly celebrations = new Emitter<void>();
  /** Resolves once the saved session and log are in (at once in demo and snapshot runs). */
  readonly ready: Promise<void>;

  private readonly context: ModuleContext;
  private readonly preferences: ModulePreferences;
  private readonly focusMode: FocusController | undefined;
  private readonly isDemo: boolean;
  /** Snapshot runs read the saved session but never write it back, so rendering with another kit can't change the user's method. */
  private readonly isSnapshot: boolean;
  private isVisible = false;
  /** False while the Study module is turned off, so a session left running in a hidden tab never holds focus mode on. */
  private isEnabled = false;
  private loaded = false;
  /** Whether the user changed the session before the saved one had loaded. */
  private touched = false;
  /** Set when the log on disk could not be read: new stretches are still logged in memory, but the file is never overwritten. */
  private logIsUnreadable = false;
  private ticker: ReturnType<typeof setInterval> | undefined;
  private heartbeat: ReturnType<typeof setInterval> | undefined;
  private lastBeat: Instant | undefined;
  private readonly phaseEnd: WallClockAlarm;
  /** A block finished while the panel was hidden; the pet celebrates it the next time the panel shows. */
  private celebrationPending = false;
  /** The party session the provider snapshot shows, which a snapshot shot can stand in for. */
  private followedPartySession: ProvidedPartySession | undefined;
  private lastFocusActivity: string | undefined;

  constructor(context: ModuleContext, options: StudyStoreOptions) {
    const now = context.now();
    const isDemo = context.isDemo;
    const custom = isDemo ? DEMO_CUSTOM : StudyCustomRhythm.standard;
    const timer = StudyTimerLength.standard;
    const session = isDemo
      ? StudyStore.demoSession("pomodoro", now, DEMO_FOCUS_LEFT, custom)
      : new StudySession(presetMethod(options.menu.startingKind, custom, timer));
    super({
      session,
      deepFocus: isDemo,
      now,
      log: isDemo ? StudyStore.demoLog(now, context.timeZone()) : new StudyLog(),
      menu: options.menu,
      custom,
      timer,
      goal: options.goal,
      cardsReviewedToday: undefined,
      partySession: undefined,
      overlay: undefined,
    });
    this.context = context;
    this.preferences = options.preferences;
    this.focusMode = options.focusMode;
    this.isDemo = isDemo;
    this.isSnapshot = context.isSnapshot;
    this.pet = new PetPlayer(options.petProfile, { asleep: studyPetIsDozing(session), ...(isDemo ? { seed: 7 } : {}) });
    this.phaseEnd = new WallClockAlarm(() => this.catchUp());
    if (isDemo) {
      this.loaded = true;
      this.ready = Promise.resolve();
      return;
    }
    this.ready = options.preferences.ready.then(() => this.load());
  }

  /* Takes on the saved lengths, session and log once the preferences are in. */
  private async load(): Promise<void> {
    const defaults = this.preferences.defaults;
    const custom = StudyCustomRhythm.fromJSON(parse(defaultsString(defaults, CUSTOM_KEY)));
    const timer = StudyTimerLength.fromJSON(defaultsInteger(defaults, TIMER_KEY)) ?? StudyTimerLength.standard;
    const launch = this.context.now();
    const menu = this.state.menu;
    /* A snapshot run starts on the kit's method, as a new user would, so the PNGs never depend on what this PC happens to have saved. */
    let saved = (this.isSnapshot ? undefined : decodeSaved(defaultsString(defaults, SESSION_KEY))) ?? new StudySession(presetMethod(menu.startingKind, custom, timer));
    /*
     * Quitting stops a session under way, so one still under way means Tabbi
     * crashed or the PC lost power: it ends at the last heartbeat. Without one
     * (or in a snapshot run, which never recovers) a phase that ran out is
     * caught up quietly.
     */
    const lastAlive = defaults.get(LAST_ALIVE_KEY);
    if (!this.isSnapshot && typeof lastAlive === "number" && Number.isFinite(lastAlive)) saved.recover(lastAlive, launch);
    else saved.advance(launch);
    const recovered = this.isSnapshot ? [] : saved.takeLog();
    const replacement = menu.replacement(saved, false);
    if (replacement !== undefined) saved.switchMethod(presetMethod(replacement, custom, timer), launch);
    const deepFocus = defaultsBool(defaults, DEEP_FOCUS_KEY) ?? false;
    let log = new StudyLog();
    try {
      log = (await loadStudyLog(this.context.storage.root(), STUDY_LOG_DOCUMENT_NAME)) ?? new StudyLog();
    } catch {
      this.logIsUnreadable = true;
    }
    /* A session the user already started while the saved one loaded is kept; only an untouched fresh one gives way. */
    if (this.touched) saved = this.state.session;
    this.loaded = true;
    const old = this.state.session;
    this.changed({ ...this.state, session: saved, custom, timer, deepFocus, log, now: launch });
    this.pet.send({ kind: studyPetIsDozing(saved) ? "sleep" : "wake" });
    this.reactPet(old);
    this.reportFocusActivity();
    this.record(recovered);
    this.scheduleSideEffects();
    this.updateTicker();
  }

  // MARK: Reading

  get session(): StudySession {
    return this.state.session;
  }

  /** The kit's methods for the picker, with Custom and the Timer on the user's lengths. */
  get methods() {
    return this.state.menu.methods(this.state.custom, this.state.timer);
  }

  /** Minutes, finished stretches and points logged today. */
  get today() {
    return this.state.log.summary(this.state.now, this.context.timeZone());
  }

  /** Whether an Anki sprint has a card count to follow; the demo's sample sprint always does. */
  get canCountCards(): boolean {
    return this.isDemo || this.state.cardsReviewedToday !== undefined;
  }

  // MARK: Visibility and lifecycle

  /** Call from the panel's mount and unmount; the clock ticks only while it's visible. */
  setVisible(visible: boolean): void {
    if (visible === this.isVisible) return;
    this.isVisible = visible;
    this.catchUp();
    this.updateTicker();
    if (!visible) return;
    if (this.celebrationPending) {
      this.celebrationPending = false;
      this.pet.send({ kind: "celebrate" });
      this.celebrations.emit();
      if (studyPetIsDozing(this.state.session)) this.pet.send({ kind: "sleep" });
    }
  }

  /** Called by the module's `start()` / `stop()`. */
  setEnabled(enabled: boolean): void {
    if (enabled === this.isEnabled) return;
    this.isEnabled = enabled;
    this.reportFocusActivity();
  }

  /** Ends the session now, for the app quitting (the Mac's SessionInterruptions). An idle session keeps its rounds. */
  interrupt(): void {
    if (this.state.session.runState === "idle") return;
    this.stop();
  }

  dispose(): void {
    this.phaseEnd.dispose();
    this.isVisible = false;
    this.updateTicker();
    this.updateHeartbeat();
  }

  /** Shows `overlay` over the timer, or the timer for undefined. */
  show(overlay: StudyPanelOverlay | undefined): void {
    this.setState({ overlay });
  }

  // MARK: Controls

  setDeepFocus(on: boolean): void {
    if (on === this.state.deepFocus) return;
    this.setState({ deepFocus: on });
    this.reportFocusActivity();
    if (!this.isDemo && !this.isSnapshot) {
      this.preferences.defaults.set(DEEP_FOCUS_KEY, on);
      this.preferences.save();
    }
  }

  /** The big button: start, pause, resume, or end a Flowtime stretch. */
  primaryAction(): void {
    this.catchUp();
    const session = this.state.session;
    if (session.isRunning && session.phase === "focus" && session.method.focus.kind === "openEnded") {
      this.change((edited) => edited.stopFocus(this.state.now));
    } else if (session.isRunning) {
      this.change((edited) => edited.pause(this.state.now));
    } else {
      this.start();
    }
  }

  private start(): void {
    this.change((edited) => edited.start(this.state.now));
  }

  pause(): void {
    this.catchUp();
    this.change((edited) => edited.pause(this.state.now));
  }

  skip(): void {
    this.catchUp();
    this.change((edited) => edited.skip(this.state.now));
  }

  /** Ends the session and banks the time so far: the phase is logged as abandoned with the minutes it ran. */
  stop(): void {
    this.catchUp();
    this.change((edited) => edited.reset(this.state.now));
  }

  /** Starts over with `kind`'s preset; no-op if it's already the method. */
  choose(kind: StudyMethodKind): void {
    if (kind === this.state.session.method.kind) return;
    this.catchUp();
    this.change((edited) => edited.switchMethod(presetMethod(kind, this.state.custom, this.state.timer), this.state.now));
  }

  /** Saves new Custom lengths. A session on Custom keeps its round and clock and takes them on at once. */
  setCustom(rhythm: StudyCustomRhythm): void {
    if (rhythm.equals(this.state.custom)) return;
    this.setState({ custom: rhythm });
    if (!this.isDemo && !this.isSnapshot) {
      this.preferences.defaults.set(CUSTOM_KEY, stringifyJSON(rhythm.toJSON()));
      this.preferences.save();
    }
    this.catchUp();
    this.change((edited) => edited.retune(rhythm.method, this.state.now));
  }

  /** Saves a new Timer length. A session on the Timer takes it on at once; one already counting keeps at least a minute. */
  setTimer(length: StudyTimerLength): void {
    if (length.minutes === this.state.timer.minutes) return;
    this.setState({ timer: length });
    if (!this.isDemo && !this.isSnapshot) {
      this.preferences.defaults.set(TIMER_KEY, length.minutes);
      this.preferences.save();
    }
    this.catchUp();
    this.change((edited) => edited.retune(length.method, this.state.now));
  }

  /** A Timer length chip: saves the length and, when no countdown has started yet, starts one, so a common length is a single click. */
  startTimer(length: StudyTimerLength): void {
    this.setTimer(length);
    this.catchUp();
    const session = this.state.session;
    if (session.method.kind !== "timer" || session.runState !== "idle") return;
    this.start();
  }

  /**
   * Follows a new kit: the picker offers its methods, and a stopped timer
   * moves to its starting method. A running block is never cut short.
   * `kitApplied` is true when the user just picked or reset the kit, so even
   * a still-offered method gives way to the kit's start.
   */
  use(menu: StudyMethodMenu, goal: StudyDailyGoal, kitApplied: boolean): void {
    this.setState({ menu, goal });
    this.catchUp();
    const kind = menu.replacement(this.state.session, kitApplied);
    if (kind === undefined) return;
    this.change((edited) => edited.switchMethod(presetMethod(kind, this.state.custom, this.state.timer), this.state.now));
  }

  /** Dresses the corner pet in the study pet's look as it changes. Demo runs keep their sample pet. */
  followPet(profile: PetProfile): void {
    if (this.isDemo) return;
    this.pet.update(profile);
  }

  /** Counts an Anki sprint's cards from the shared progress goals, and shows the party's shared session, so the Timer never needs those modules. */
  followSnapshot(snapshot: ProviderSnapshot): void {
    if (!this.isDemo) this.receiveCards(cardsReviewedToday(snapshot.progress, MODULE_IDS.study));
    const session = snapshot.party?.session;
    this.followedPartySession = session;
    this.setPartySession(session);
  }

  /** Snapshot runs only: shows `session` as the party's shared session, as if Party were on and the user in it; undefined puts back the followed one. */
  showForSnapshot(session: ProvidedPartySession | undefined): void {
    if (!this.isSnapshot) return;
    this.setPartySession(session ?? this.followedPartySession);
  }

  /** Demo runs only: a believable session on `kind`, so every method can be reviewed. */
  showDemoMethod(kind: StudyMethodKind, paused = false): void {
    if (!this.isDemo) return;
    const now = this.context.now();
    const old = this.state.session;
    const session = StudyStore.demoSession(kind, now, DEMO_FOCUS_LEFT, this.state.custom);
    if (paused) session.pause(now);
    this.changed({ ...this.state, session, now });
    this.reactPet(old);
    this.updateTicker();
  }

  /** The study phase this session asks of focus mode, for the module's provision. */
  get focusActivity() {
    return studyFocusActivity(this.state.session, this.state.deepFocus && this.isEnabled);
  }

  // MARK: Private

  private setPartySession(session: ProvidedPartySession | undefined): void {
    const had = this.state.partySession !== undefined;
    this.setState({ partySession: session });
    if (had === (session !== undefined)) return;
    this.catchUp();
    this.updateTicker();
    /* The pet studies along with the party, and dozes again after it when the user's own timer is stopped. */
    if (studyPetIsDozing(this.state.session)) this.pet.send({ kind: session === undefined ? "sleep" : "wake" });
  }

  private receiveCards(count: number | undefined): void {
    if (count === this.state.cardsReviewedToday) return;
    this.setState({ cardsReviewedToday: count });
    if (count === undefined) return;
    this.catchUp();
    /* Reaching the card goal ends the sprint like a timer running out. */
    this.change(() => {});
  }

  /** Applies `edit`, then the latest card count, then saves and re-arms the phase-end alarm and ticker. */
  private change(edit: (session: StudySession) => void): void {
    const updated = this.state.session.clone();
    edit(updated);
    const cards = this.state.cardsReviewedToday;
    if (cards !== undefined) updated.recordReviewedToday(cards, this.state.now);
    if (sessionsEqual(updated, this.state.session)) return;
    this.touched = true;
    const old = this.state.session;
    this.changed({ ...this.state, session: updated });
    this.reportFocusActivity();
    this.reactPet(old);
    this.scheduleSideEffects();
    this.updateTicker();
  }

  /** Moves `now` forward and applies phase ends that have passed. */
  private catchUp(): void {
    const now = this.context.now();
    const session = this.state.session.clone();
    const ended = session.advance(now);
    if (ended.length === 0) {
      if (now !== this.state.now) this.changed({ ...this.state, now });
      return;
    }
    const old = this.state.session;
    this.changed({ ...this.state, session, now });
    this.reportFocusActivity();
    this.reactPet(old);
    /* Stale ends (the PC was asleep) stay quiet, and so do demo and snapshot runs. */
    const last = ended[ended.length - 1];
    if (!this.isDemo && !this.isSnapshot && last !== undefined && now - last.endedAt < FRESH_END_SECONDS) {
      this.context.logger.debug(`${last.phase} ended`);
    }
    this.scheduleSideEffects();
    this.updateTicker();
  }

  /** Moves finished stretches into the log, saves the session and the log, and arms the alarm for the running phase's end. */
  private scheduleSideEffects(): void {
    if (this.isDemo || this.isSnapshot || !this.loaded) return;
    this.collectLog();
    this.preferences.defaults.set(SESSION_KEY, stringifyJSON(encodeStudySession(this.state.session)));
    this.updateHeartbeat();
    const endsAt = this.state.session.endsAt;
    if (endsAt === undefined) this.phaseEnd.cancel();
    else this.phaseEnd.schedule(endsAt * 1000);
  }

  /** Ticks once a second, only while the panel is visible and the clock runs (or a party session shows). The demo ticks too. */
  private updateTicker(): void {
    const wanted = this.isVisible && (this.state.session.isRunning || this.state.partySession !== undefined) && !this.isSnapshot;
    if (!wanted) {
      if (this.ticker !== undefined) clearInterval(this.ticker);
      this.ticker = undefined;
      return;
    }
    if (this.ticker !== undefined) return;
    this.ticker = setInterval(() => this.catchUp(), 1000);
  }

  /** Tells focus mode what the session needs. `FocusController` ignores repeats and is inert in demo and snapshot runs. */
  private reportFocusActivity(): void {
    const activity = this.focusActivity;
    if (activity === this.lastFocusActivity) return;
    this.lastFocusActivity = activity;
    this.focusMode?.activityChanged(activity, "study");
  }

  /** Plays the pet's reaction to a session change. A celebration in view scatters paw prints over the panel; one behind another tab waits for this panel. */
  private reactPet(old: StudySession): void {
    for (const event of studyPetEvents(old, this.state.session)) {
      if (event.kind === "celebrate" && !this.isVisible) {
        this.celebrationPending = true;
        continue;
      }
      this.pet.send(event);
      if (event.kind === "celebrate") this.celebrations.emit();
    }
  }

  /*
   * Saves the last-alive time now and every heartbeat while the clock runs.
   * A beat that arrives minutes late means the PC slept: the session is
   * settled at the last beat, the way the Mac stops it before sleeping.
   */
  private updateHeartbeat(): void {
    const session = this.state.session;
    const now = this.context.now();
    if (session.runState !== "idle") {
      this.preferences.defaults.set(LAST_ALIVE_KEY, now);
      this.lastBeat = now;
    }
    this.preferences.save();
    if (!session.isRunning) {
      if (this.heartbeat !== undefined) clearInterval(this.heartbeat);
      this.heartbeat = undefined;
      return;
    }
    if (this.heartbeat !== undefined) return;
    this.heartbeat = setInterval(() => this.beat(), HEARTBEAT_INTERVAL_SECONDS * 1000);
  }

  private beat(): void {
    const now = this.context.now();
    const last = this.lastBeat;
    if (last !== undefined && now - last > HEARTBEAT_INTERVAL_SECONDS + SLEEP_GAP_SECONDS) {
      this.change((edited) => edited.recover(last, now));
      return;
    }
    this.lastBeat = now;
    this.preferences.defaults.set(LAST_ALIVE_KEY, now);
    this.preferences.save();
  }

  /** Drains the session's phase records into the persisted log and the shared activity log. */
  private collectLog(): void {
    if (this.state.session.log.length === 0) return;
    const session = this.state.session.clone();
    const records = session.takeLog();
    this.changed({ ...this.state, session });
    this.record(records);
  }

  /** Adds `records` to the persisted log and the shared activity log. */
  private record(records: readonly StudyPhaseRecord[]): void {
    if (records.length === 0) return;
    const activities = records.flatMap((record) => phaseActivityRecord(record, MODULE_IDS.study) ?? []);
    if (activities.length > 0) void this.context.activityLog.record(activities);
    const { log, added } = this.state.log.recording(records, newUUID);
    if (added.length === 0) return;
    this.setState({ log });
    if (!this.logIsUnreadable && !this.isDemo && !this.isSnapshot) {
      void writeStudyLog(this.context.storage.root(), log, STUDY_LOG_DOCUMENT_NAME).catch((error: unknown) =>
        this.context.logger.error("could not save the study log", error),
      );
    }
  }

  /**
   * A believable session part-way through: a Pomodoro on its second round
   * with `focusLeft` to go, a Flowtime stretch counting up, a sprint with
   * cards done, or another method a bit over a third into its first focus block.
   */
  static demoSession(kind: StudyMethodKind, now: Instant, focusLeft: Seconds = DEMO_FOCUS_LEFT, custom: StudyCustomRhythm = DEMO_CUSTOM): StudySession {
    const session = new StudySession(presetMethod(kind, custom));
    switch (kind) {
      case "pomodoro": {
        /* Round one (25 min) and its break (5 min), then round two. */
        const secondRound = now - (25 * 60 - Math.min(Math.max(focusLeft, 1), 25 * 60));
        const start = secondRound - 30 * 60;
        session.start(start);
        session.advance(secondRound);
        session.start(secondRound);
        break;
      }
      case "flowtime":
        session.start(now - (23 * 60 + 12));
        break;
      case "ankiSprint": {
        const start = now - (11 * 60 + 5);
        session.start(start);
        session.recordReviewedToday(120, start);
        session.recordReviewedToday(157, now);
        break;
      }
      default: {
        const focus = session.method.focus;
        if (focus.kind === "duration") session.start(now - Math.round(focus.seconds * 0.38));
      }
    }
    session.takeLog();
    return session;
  }

  /** A morning's work: two finished Pomodoros and a short sprint. */
  static demoLog(now: Instant, timeZone: string): StudyLog {
    const start = startOfDay(now, timeZone) + 9 * 3600;
    const stretch = (method: StudyMethodKind, from: number, minutes: number, cards?: number): StudyPhaseRecord => ({
      method,
      phase: "focus",
      startedAt: start + from * 60,
      endedAt: start + (from + minutes) * 60,
      activeDuration: minutes * 60,
      outcome: "completed",
      ...(cards === undefined ? {} : { cards }),
    });
    let id = 0;
    return new StudyLog().recording(
      [stretch("pomodoro", 0, 25), stretch("pomodoro", 30, 25), stretch("ankiSprint", 70, 14, 100)],
      () => `demo-${++id}`,
    ).log;
  }
}

function parse(text: string | undefined): unknown {
  if (text === undefined) return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

/** The saved session, or undefined when there is none or it can't be read. */
function decodeSaved(text: string | undefined): StudySession | undefined {
  try {
    const json = parse(text);
    return json === undefined ? undefined : decodeStudySession(json as never);
  } catch {
    return undefined;
  }
}

/** Whether two sessions are the same value, the Mac's `!=` guard in `change`. */
export function sessionsEqual(a: StudySession, b: StudySession): boolean {
  return JSON.stringify(encodeStudySession(a)) === JSON.stringify(encodeStudySession(b));
}
