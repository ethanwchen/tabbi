/*
 * Port of PetCoachController: runs the study pet's coach. While a focus
 * phase runs it samples how long the user has been idle and which app is
 * in front (the host's `coachSample`: only the time since the last input
 * and the foreground executable's name, never window titles or keys), feeds
 * `PetCoach`, and plays each nudge as the island's closed overlay: the pet
 * trots out from under the pill and says its line in a bubble.
 *
 * The focus timer comes from the shared provider snapshot, so the coach
 * works with whichever module runs the timer. Coach state (cooldowns,
 * snooze, app lists) persists next to the pet's save. In demo and snapshot
 * runs the coach never samples, nudges or writes. It also backs
 * Settings > Pet Coach: the nudges switch and the user's distracting apps.
 */

import { celebrations } from "../../../app/celebrations";
import type { ModuleContext } from "../../../app/context";
import { Store } from "../../../app/store";
import { closedOverlaySlot, type ClosedOverlay } from "../../../app/takeover";
import { CoachAppList } from "../../../core/coach/coachAppList";
import { PetCoach, type PetCoachNudge } from "../../../core/coach/petCoach";
import { coachLines, coachMessages, type PetCoachMessage, type PetCoachNudgeKind } from "../../../core/coach/petCoachMessages";
import { replyPausesTimer, replyResumesTimer, type PetCoachReply } from "../../../core/coach/petCoachReply";
import { PetCoachSave, coachInput, coachStudyState } from "../../../core/coach/petCoachSession";
import { PetCoachStroll } from "../../../core/coach/petCoachStroll";
import type { PetStudyAward } from "../../../core/closet/petStudyCredit";
import { CAT_WISDOM_COMEBACK, CAT_WISDOM_DAILY, catWisdomSessionFromAward, milestoneLine, type CatWisdomLine } from "../../../core/motivation/catWisdom";
import { RARE_FURS, type SurpriseGiftDelivery } from "../../../core/motivation/surpriseGift";
import { UnlockProgress } from "../../../core/motivation/unlockProgress";
import type { JournalEntry } from "../../../core/pets/petAdventure";
import { PetPointsLedger } from "../../../core/pets/petUnlocks";
import type { DocumentStore } from "../../../core/persistence/documentStore";
import type { ProvidedFocus } from "../../../core/providers/providedFocus";
import type { Instant } from "../../../core/time";
import type { ClosetStore } from "../closetStore";
import type { SurpriseGiftKeeper } from "../surpriseGiftKeeper";
import { makeCoachOverlay } from "./PetCoachOverlay";
import { PetCoachScene, lineTalkDuration, type PetCoachLine } from "./petCoachScene";

export const COACH_DOCUMENT = "coach.json";

/** An award line earned while a panel was open plays once the island closes, within this long. */
const WAIT_LIMIT = 10 * 60;

export interface PetCoachControllerState {
  readonly nudgesOn: boolean;
  readonly apps: CoachAppList;
  /** The scene on screen, or undefined while the pet is home. */
  readonly scene: PetCoachScene | undefined;
}

export interface PetCoachControllerOptions {
  readonly profile: () => import("../../../core/pets/petProfile").PetProfile;
  readonly closet: ClosetStore;
  readonly gifts: SurpriseGiftKeeper;
  readonly pauseTimer: () => void;
  readonly resumeTimer: () => void;
}

export class PetCoachController extends Store<PetCoachControllerState> {
  /** The overlay moments the snapshot harness draws, the Mac's PetCoachSnapshots. */
  static readonly snapshotStates: readonly string[] = [
    "coach-glance-lowering",
    "coach-glance",
    "coach-walking",
    "coach-distraction",
    "coach-offer-pause",
    "coach-idle-check",
    "coach-auto-pause",
    "coach-celebrate",
    "coach-session-end",
    "coach-level-up",
    "coach-session-end-all-owned",
    "coach-gift",
    "coach-gift-fur",
    "coach-gift-adventure",
    "coach-wisdom",
    "coach-wisdom-comeback",
    "coach-wisdom-milestone",
  ];

  private save = new PetCoachSave();
  private readonly store: DocumentStore | undefined;
  private unreadable = false;
  private readonly loaded: Promise<void>;
  private timer: ProvidedFocus | undefined;
  private isRunning = false;
  private sampler: ReturnType<typeof globalThis.setInterval> | undefined;
  private sampling = false;
  private closer: ReturnType<typeof globalThis.setTimeout> | undefined;
  /** Whether the coach saw a focus phase run since the last award, so a session settled at launch brings no wisdom line or gift. */
  private watchedFocus = false;
  private waitingLine: { readonly line: PetCoachLine; readonly since: Instant } | undefined;
  private readonly stops: (() => void)[] = [];
  /** A snapshot's frozen moment, drawn instead of the clock. */
  private frozenAt: Instant | undefined;

  constructor(
    private readonly context: ModuleContext,
    private readonly options: PetCoachControllerOptions,
  ) {
    super({ nudgesOn: true, apps: new CoachAppList(), scene: undefined });
    const isDemo = context.isDemo;
    if (isDemo) {
      /* A realistic Settings pane: two suggestions and one added app. */
      const apps = new CoachAppList();
      apps.markDistracting("PhoneExperienceHost.exe");
      apps.markDistracting("Discord.exe");
      apps.markDistracting("Spotify.exe");
      this.save = new PetCoachSave(new PetCoach(), apps);
      this.setState({ apps: apps.clone() });
    }
    this.store = isDemo || context.isSnapshot ? undefined : context.storage.folder("Pet");
    this.loaded = this.store === undefined ? Promise.resolve() : this.load(this.store);
    this.timer = context.snapshot.get().focus;
    this.stops.push(
      context.snapshot.subscribe(() => this.focusChanged(context.snapshot.get().focus)),
      options.closet.awards.on((award) => this.awarded(award)),
    );
    /* The island closing plays the award line a panel was hiding. */
    const kinds = context.closedPreview.watchedKinds;
    let wasClosed = kinds.get().size > 0;
    this.stops.push(
      kinds.subscribe(() => {
        const closed = kinds.get().size > 0;
        if (closed === wasClosed) return;
        wasClosed = closed;
        if (closed) this.playWaitingLine();
      }),
    );
  }

  private async load(store: DocumentStore): Promise<void> {
    try {
      const saved = await PetCoachSave.load(store, COACH_DOCUMENT);
      if (saved === undefined) return;
      this.save = saved;
      this.setState({ nudgesOn: saved.nudgesOn, apps: saved.apps.clone() });
      this.updateSampling();
    } catch (error) {
      this.unreadable = true;
      this.context.logger.error("The coach's save could not be read; running on defaults without overwriting it", error);
    }
  }

  /** What the pet can say: the standard lines plus the active kit's, read on every nudge so switching kits changes the flavor at once. */
  get lines(): PetCoachMessage[] {
    return coachLines(this.context.kitSettings());
  }

  /** Turns the coach on, with the pet's module. */
  start(): void {
    if (this.context.isDemo || this.isRunning) return;
    this.isRunning = true;
    this.updateSampling();
  }

  /** Turns the coach off and sends the pet home at once. */
  stop(): void {
    if (!this.isRunning) return;
    this.isRunning = false;
    this.waitingLine = undefined;
    this.updateSampling();
    this.closeOverlay();
  }

  /* Settings */

  get nudgesOn(): boolean {
    return this.state.nudgesOn;
  }

  setNudgesOn(on: boolean): void {
    if (on === this.save.nudgesOn) return;
    this.save.nudgesOn = on;
    this.setState({ nudgesOn: on });
    this.updateSampling();
    this.persist();
    if (!on) this.closeOverlay();
  }

  toggleDistracting(executable: string): void {
    this.save.apps.toggleDistracting(executable);
    this.setState({ apps: this.save.apps.clone() });
    this.persist();
  }

  /** Adds an app by its executable name (typed in Settings) as distracting. */
  addDistractingApp(executable: string): void {
    const name = executable.trim();
    if (name === "" || this.save.apps.isDistracting(name)) return;
    this.save.apps.markDistracting(name);
    this.setState({ apps: this.save.apps.clone() });
    this.persist();
  }

  /* Sampling */

  private focusChanged(timer: ProvidedFocus | undefined): void {
    this.timer = timer;
    if (coachStudyState(timer) === "focusing") this.watchedFocus = true;
    this.updateSampling();
  }

  /** Samples every few seconds during a focus phase with nudges on, and not at all otherwise. */
  private updateSampling(): void {
    const focusing = this.isRunning && this.save.nudgesOn && coachStudyState(this.timer) === "focusing";
    if (focusing && this.sampler === undefined) {
      this.sampler = globalThis.setInterval(() => void this.sample(), PetCoach.sampleInterval * 1000);
    } else if (!focusing && this.sampler !== undefined) {
      globalThis.clearInterval(this.sampler);
      this.sampler = undefined;
      /* Leaving focus takes one last sample, which ends any episode in the coach; switching off ends them without one. */
      if (this.isRunning && this.save.nudgesOn) void this.sample();
      else this.save.coach.endEpisodes();
    }
  }

  private async sample(): Promise<void> {
    if (this.sampling) return;
    this.sampling = true;
    try {
      const reading = await this.context.host.coachSample();
      await this.loaded;
      const now = this.context.now();
      const input = coachInput(now, reading?.idleSeconds ?? 0, this.save.apps.category(reading?.frontmost ?? undefined), this.timer);
      const before = this.save.coach.toJSON();
      const decision = this.save.coach.evaluate(input, Math.random, this.lines);
      if (JSON.stringify(before) !== JSON.stringify(this.save.coach.toJSON())) this.persist();
      switch (decision.type) {
        case "none":
          break;
        case "lookOver":
          this.glance(now);
          break;
        case "nudge":
          if (decision.nudge.kind === "autoPause") this.options.pauseTimer();
          this.presentNudge(decision.nudge, now);
          break;
      }
    } catch (error) {
      this.context.logger.error("The coach could not sample", error);
    } finally {
      this.sampling = false;
    }
  }

  /* Awards */

  /** Celebrates an award on the next turn, once the closet has settled the save. */
  private awarded(award: PetStudyAward): void {
    const watched = this.watchedFocus;
    this.watchedFocus = coachStudyState(this.timer) === "focusing";
    globalThis.setTimeout(() => void this.celebrate(award, watched), 0);
  }

  /**
   * Sends the pet out to celebrate points just earned: a happy hop with a
   * heart, the points counting up and a bar filling toward the next unlock,
   * now and then a surprise gift, then now and then a Cat wisdom line. Plays
   * whenever the coach is on, nudges or not, since it never interrupts.
   * Wisdom and gifts only follow a session the coach `watched` run.
   */
  async celebrate(award: PetStudyAward, watched = true): Promise<void> {
    if (!this.isRunning) return;
    await this.loaded;
    /* The bar first: it shows what the session earned, before a gift's bonus points land on the balance. */
    const progress = UnlockProgress.after(award, this.options.closet.closet);
    const now = this.context.now();
    const line: PetCoachLine = {
      kind: "celebration",
      award,
      progress,
      ...(watched ? wrapOptional("wisdom", this.wisdom(award, now)) : {}),
      ...(watched ? wrapOptional("gift", await this.options.gifts.roll(award, now)) : {}),
    };
    if (celebrations(this.context).isShowing) {
      this.waitingLine = { line, since: now };
      return;
    }
    this.waitingLine = undefined;
    this.present(new PetCoachScene(this.options.profile(), new PetCoachStroll(now, { talkDuration: lineTalkDuration(line) }), line));
  }

  /** Plays the award line held while a panel was open, unless it got old. */
  private playWaitingLine(): void {
    const waiting = this.waitingLine;
    if (waiting === undefined) return;
    this.waitingLine = undefined;
    const now = this.context.now();
    if (!this.isRunning || now - waiting.since >= WAIT_LIMIT) return;
    this.present(new PetCoachScene(this.options.profile(), new PetCoachStroll(now, { talkDuration: lineTalkDuration(waiting.line) }), waiting.line));
  }

  /** The Cat wisdom line for the session behind `award`, if one is due, keeping the rotation and caps in the save. */
  private wisdom(award: PetStudyAward, now: Instant): CatWisdomLine | undefined {
    const closet = this.options.closet;
    const session = catWisdomSessionFromAward(award, now, this.save.lastCompletion, closet.streak, closet.state.milestones, this.context.timeZone());
    if (session === undefined) return undefined;
    const line = this.save.wisdom.line(session, this.context.timeZone(), Math.random, this.context.settings.current.catWisdomEnabled);
    if (session.outcome === "completed") this.save.lastCompletion = now;
    this.persist();
    return line;
  }

  /* Overlay */

  /** The silent look: the pet peeks out of the island's edge and back. Never over a bubble that's still up. */
  private glance(now: Instant): void {
    if (this.state.scene !== undefined) return;
    this.present(PetCoachScene.glance(this.options.profile(), now));
  }

  private presentNudge(nudge: PetCoachNudge, now: Instant): void {
    this.present(new PetCoachScene(this.options.profile(), new PetCoachStroll(now), { kind: "nudge", nudge }));
  }

  private present(scene: PetCoachScene, frozenAt?: Instant): void {
    /* One pet on screen at a time; a newer line replaces an old one. */
    this.closeOverlay();
    this.frozenAt = frozenAt;
    this.setState({ scene });
    const overlay: ClosedOverlay = makeCoachOverlay({
      scene: () => this.state.scene ?? scene,
      now: () => this.frozenAt ?? this.context.now(),
      frozen: frozenAt !== undefined,
      subscribe: this.subscribe,
      onReply: (reply) => this.answer(reply),
      onHover: (over) => this.hover(over),
    });
    closedOverlaySlot(this.context.shared).set(overlay);
    if (frozenAt === undefined) this.scheduleClose(scene.stroll.endsAt);
  }

  private answer(reply: PetCoachReply): void {
    const now = this.context.now();
    this.save.coach.handle(reply, now);
    if (reply === "snooze") this.persist();
    if (replyPausesTimer(reply)) this.options.pauseTimer();
    if (replyResumesTimer(reply)) this.options.resumeTimer();
    const scene = this.state.scene;
    if (scene === undefined) return;
    scene.stroll.dismiss(now);
    this.setState({ scene: new PetCoachScene(scene.profile, scene.stroll, scene.line, scene.clips) });
    this.scheduleClose(scene.stroll.endsAt);
  }

  /** Hovering the bubble keeps it up; leaving lets it run out. */
  private hover(over: boolean): void {
    const scene = this.state.scene;
    if (scene === undefined || this.frozenAt !== undefined) return;
    const now = this.context.now();
    if (over) scene.stroll.hold(now);
    else scene.stroll.release(now);
    this.setState({ scene: new PetCoachScene(scene.profile, scene.stroll, scene.line, scene.clips) });
    this.scheduleClose(scene.stroll.endsAt);
  }

  /** Closes the overlay once the pet is back under the island. */
  private scheduleClose(at: Instant): void {
    globalThis.clearTimeout(this.closer);
    const wait = Number.isFinite(at) ? Math.max(0, (at + 0.1 - this.context.now()) * 1000) : undefined;
    if (wait === undefined) return;
    this.closer = globalThis.setTimeout(() => this.closeOverlay(), wait);
  }

  private closeOverlay(): void {
    globalThis.clearTimeout(this.closer);
    this.closer = undefined;
    if (this.state.scene === undefined) return;
    this.setState({ scene: undefined });
    const slot = closedOverlaySlot(this.context.shared);
    slot.set(undefined);
  }

  dispose(): void {
    this.stop();
    for (const stop of this.stops) stop();
    this.stops.length = 0;
  }

  private persist(): void {
    const store = this.store;
    if (store === undefined) return;
    void this.loaded.then(async () => {
      if (this.unreadable) return;
      try {
        await this.save.write(store, COACH_DOCUMENT);
      } catch (error) {
        this.context.logger.error("The coach's save could not be written", error);
      }
    });
  }

  /* Snapshots */

  /** Freezes one overlay moment for the snapshot harness (the Mac's PetCoachSnapshots). Bubbles use the last line of each kind, the active kit's own when it has one. */
  showSnapshotState(state: string): void {
    if (!this.context.isSnapshot) return;
    const profile = this.options.profile();
    const start = this.context.now();
    const lines = this.lines;
    const nudge = (kind: PetCoachNudgeKind): PetCoachNudge => {
      const pool = coachMessages(kind, lines);
      const message = pool[pool.length - 1];
      if (message === undefined) throw new Error(`No ${kind} line`);
      return { kind, message };
    };
    const stroll = new PetCoachStroll(start);
    const party = new PetCoachStroll(start, { talkDuration: PetCoach.celebrationDuration });
    const session: PetStudyAward = { completedSessions: 1, minutes: 25, points: 35, unlocked: [] };
    /* The demo pet wears the glasses, so they are owned and the bar aims at the next item. */
    const toNext = UnlockProgress.make(40, new PetPointsLedger({ purchased: ["accessory.beanie", "accessory.roundGlasses"] }), 35);
    const talking = stroll.arrivesAt + 3;
    const celebration = (line: PetCoachLine, at: Instant, talk = party) => this.present(new PetCoachScene(profile, talk, line), at);
    const wisdomAt = (line: CatWisdomLine) => {
      const full: PetCoachLine = { kind: "celebration", award: session, progress: toNext, wisdom: line };
      const talk = new PetCoachStroll(start, { talkDuration: lineTalkDuration(full) });
      celebration(full, talk.arrivesAt + PetCoach.celebrationDuration + 1, talk);
    };
    const returned: JournalEntry = { line: "leaf", date: party.arrivesAt, gift: { kind: "rareFur", id: "moonstone", name: "Moonstone" } };
    const fur = (index: number) => RARE_FURS[index] ?? RARE_FURS[0];
    switch (state) {
      case "coach-glance-lowering": {
        const scene = PetCoachScene.glance(profile, start);
        const glance = scene.line.kind === "glance" ? scene.line.glance : undefined;
        return this.present(scene, start + (glance?.enter ?? 1) * 0.12);
      }
      case "coach-glance": {
        const scene = PetCoachScene.glance(profile, start);
        const glance = scene.line.kind === "glance" ? scene.line.glance : undefined;
        return this.present(scene, start + (glance?.enter ?? 1) + 1);
      }
      case "coach-walking":
        return this.present(new PetCoachScene(profile, stroll, { kind: "nudge", nudge: nudge("distraction") }), start + stroll.walkDuration * 0.6);
      case "coach-distraction":
        return this.present(new PetCoachScene(profile, stroll, { kind: "nudge", nudge: nudge("distraction") }), talking);
      case "coach-offer-pause":
        return this.present(new PetCoachScene(profile, stroll, { kind: "nudge", nudge: nudge("offerPause") }), talking);
      case "coach-idle-check":
        return this.present(new PetCoachScene(profile, stroll, { kind: "nudge", nudge: nudge("idleCheck") }), talking);
      case "coach-auto-pause":
        return this.present(new PetCoachScene(profile, stroll, { kind: "nudge", nudge: nudge("autoPause") }), talking);
      case "coach-celebrate":
        return celebration({ kind: "celebration", award: session, progress: toNext }, party.arrivesAt + 0.3);
      case "coach-session-end":
        return celebration({ kind: "celebration", award: session, progress: toNext }, party.arrivesAt + 2);
      case "coach-level-up":
        return celebration({ kind: "celebration", award: session, progress: UnlockProgress.make(40, new PetPointsLedger(), 35) }, party.arrivesAt + 2);
      case "coach-session-end-all-owned":
        return celebration({ kind: "celebration", award: { completedSessions: 1, minutes: 50, points: 60, unlocked: [] }, progress: undefined }, party.arrivesAt + 2);
      case "coach-gift":
        return celebration({ kind: "celebration", award: session, progress: toNext, gift: { gift: { kind: "bonusPoints", points: 15 }, date: party.arrivesAt } }, party.arrivesAt + 2);
      case "coach-gift-fur": {
        const gift: SurpriseGiftDelivery = { gift: { kind: "rareFur", fur: fur(0) as never }, date: party.arrivesAt };
        return celebration({ kind: "celebration", award: session, progress: toNext, gift }, party.arrivesAt + 2);
      }
      case "coach-gift-adventure": {
        const gift: SurpriseGiftDelivery = { gift: { kind: "rareFur", fur: fur(3) as never }, date: party.arrivesAt, adventure: returned };
        return celebration({ kind: "celebration", award: session, progress: toNext, gift }, party.arrivesAt + 2);
      }
      case "coach-wisdom":
        return wisdomAt({ kind: { type: "firstOfDay" }, text: CAT_WISDOM_DAILY[1] ?? "" });
      case "coach-wisdom-comeback":
        return wisdomAt({ kind: { type: "comeback" }, text: CAT_WISDOM_COMEBACK[1] ?? "" });
      case "coach-wisdom-milestone":
        return wisdomAt({ kind: { type: "milestone", milestone: "lastSquare" }, text: milestoneLine("lastSquare") });
      default:
        return;
    }
  }
}

/* `{ key: value }` when the value is there, nothing otherwise, so an optional field is never set to undefined. */
function wrapOptional<K extends string, V>(key: K, value: V | undefined): { [P in K]?: V } {
  return value === undefined ? {} : ({ [key]: value } as { [P in K]?: V });
}
