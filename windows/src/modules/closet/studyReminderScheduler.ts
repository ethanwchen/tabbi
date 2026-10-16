/*
 * Port of StudyReminderScheduler: the daily study reminder ("Mochi misses
 * you. 10 minutes?") in the pet's voice. It saves the user's choice and
 * plans the next reminder the moment `StudyReminderSave.plan` picks,
 * planning again whenever study, the day's goal, the pet's name, the
 * settings or the day change, so a day the user already studied gets no
 * reminder, and none gets two.
 *
 * Off by default. The Mac hands the pending reminder to the system, which
 * delivers it without Tabbi running; Windows has no scheduled toast in the
 * host, so the reminder is a wall-clock alarm that posts a toast while Tabbi
 * is running (the tray keeps it running in the background). Demo and
 * snapshot runs post and save nothing; a demo shows the reminder on at 7 pm
 * for a realistic Settings pane.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { ProgressItem } from "../../core/providers/progressItem";
import { reminderGoalMet, reminderMessage, reminderSpeaker, StudyReminderSave, StudyReminderSettings } from "../../core/streaks/studyReminder";
import type { Instant } from "../../core/time";
import { WallClockAlarm } from "../../ui/kit/clock";
import { alarmTimers } from "./alarmTimers";
import type { ClosetStore } from "./closetStore";

export const REMINDER_DOCUMENT = "reminder.json";

export interface StudyReminderState {
  readonly settings: StudyReminderSettings;
  /** The moment the next reminder is set for, or undefined while it is off. */
  readonly scheduledFor: Instant | undefined;
}

export class StudyReminderScheduler extends Store<StudyReminderState> {
  private save: StudyReminderSave;
  private readonly store: DocumentStore | undefined;
  private unreadable = false;
  private readonly loaded: Promise<void>;
  private readonly alarm = new WallClockAlarm(() => this.fire(), alarmTimers(() => this.context.now()));
  private goalMet = false;
  private readonly stops: (() => void)[] = [];
  private started = false;
  /** Several changes land at once (a study record moves the streak and the milestones); one plan serves them all. */
  private replanTimer: ReturnType<typeof globalThis.setTimeout> | undefined;

  constructor(
    private readonly context: ModuleContext,
    private readonly pet: ClosetStore,
    private readonly progress: { get(): readonly ProgressItem[]; subscribe(listener: () => void): () => void },
  ) {
    const save = new StudyReminderSave(context.isDemo ? StudyReminderSettings.at(true, 19, 0) : StudyReminderSettings.off);
    super({ settings: save.settings, scheduledFor: undefined });
    this.save = save;
    this.store = context.isDemo || context.isSnapshot ? undefined : context.storage.folder("Pet");
    this.loaded = this.store === undefined ? Promise.resolve() : this.load(this.store);
  }

  private async load(store: DocumentStore): Promise<void> {
    try {
      const saved = await StudyReminderSave.load(store, REMINDER_DOCUMENT);
      if (saved === undefined) return;
      this.save = saved;
      this.setState({ settings: saved.settings, scheduledFor: saved.scheduledFor });
    } catch (error) {
      this.unreadable = true;
      this.context.logger.error("The study reminder's save could not be read; running on defaults", error);
    }
  }

  /** Plans now and again on every change that can move the reminder. */
  start(): void {
    if (this.started || this.store === undefined) return;
    this.started = true;
    this.goalMet = reminderGoalMet(this.progress.get());
    this.stops.push(
      this.pet.subscribe(() => this.scheduleReplan()),
      this.progress.subscribe(() => {
        const met = reminderGoalMet(this.progress.get());
        if (met === this.goalMet) return;
        this.goalMet = met;
        this.scheduleReplan();
      }),
    );
    void this.loaded.then(() => this.replan());
  }

  /** Stops following changes and the alarm. */
  stop(): void {
    this.started = false;
    for (const stop of this.stops) stop();
    this.stops.length = 0;
    globalThis.clearTimeout(this.replanTimer);
    this.alarm.cancel();
  }

  get isEnabled(): boolean {
    return this.state.settings.isEnabled;
  }

  /** Whose voice the reminder speaks in. */
  get petName(): string {
    return reminderSpeaker(this.pet.profile);
  }

  /** Turns the reminder on or off. */
  setEnabled(on: boolean): void {
    this.update(this.save.settings.withEnabled(on));
  }

  /** The reminder's time of day, in minutes after midnight. */
  get minuteOfDay(): number {
    return this.state.settings.minuteOfDay;
  }

  setMinuteOfDay(minuteOfDay: number): void {
    this.update(this.save.settings.withMinuteOfDay(minuteOfDay));
  }

  private update(settings: StudyReminderSettings): void {
    if (settings.equals(this.save.settings)) return;
    this.save.settings = settings;
    this.setState({ settings });
    this.persist();
    this.scheduleReplan();
  }

  private scheduleReplan(): void {
    if (!this.started) return;
    globalThis.clearTimeout(this.replanTimer);
    this.replanTimer = globalThis.setTimeout(() => this.replan(), 200);
  }

  /** Settles the past and sets the alarm for the next reminder, if any. */
  private replan(): void {
    if (!this.started) return;
    const now = this.context.now();
    const before = this.save.scheduledFor;
    const fire = this.save.plan(now, this.pet.streak.studiedToday, this.goalMet, this.pet.calendar);
    if (fire !== before) this.persist();
    this.setState({ scheduledFor: fire });
    if (fire === undefined) this.alarm.cancel();
    else this.alarm.schedule(fire * 1000);
  }

  /** The alarm went off: the toast goes out, and the following day gets planned. */
  private fire(): void {
    const message = reminderMessage(this.petName, this.pet.streak.length);
    void this.context.host.notify(message.title, message.body).catch((error: unknown) => this.context.logger.error("The study reminder could not be shown", error));
    this.replan();
  }

  private persist(): void {
    const store = this.store;
    if (store === undefined) return;
    void this.loaded.then(async () => {
      if (this.unreadable) return;
      try {
        await this.save.write(store, REMINDER_DOCUMENT);
      } catch (error) {
        this.context.logger.error("The study reminder's save could not be written", error);
      }
    });
  }
}
