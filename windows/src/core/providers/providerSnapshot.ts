import type { ModuleID } from "../modules/moduleId";
import type { PetPresence } from "../pets/petPresence";
import type { Instant } from "../time";
import type { ModuleProvision } from "./moduleProvision";
import type { ProgressItem } from "./progressItem";
import type { UpcomingEvent } from "../planner/upcomingEvent";
import type { ProvidedFocus } from "./providedFocus";
import type { ProvidedParty } from "./providedParty";
import type { ProvidedTask } from "./providedTask";
import { addStudyDayTallies, EMPTY_STUDY_DAY_TALLY, type StudyDayTally } from "./studyDayTally";
import type { TickerHighlight } from "./tickerHighlight";

/** One enabled module's provision, in tab order. */
export interface ModuleProvisionEntry {
  readonly module: ModuleID;
  readonly provision: ModuleProvision;
}

/* A `(source, id)` key that can't collide whatever the two strings hold. */
function itemKey(module: ModuleID, id: string): string {
  return JSON.stringify([module, id]);
}

/**
 * Port of ProviderSnapshot: everything the enabled modules provide, merged
 * into one value.
 *
 * Built from provisions in tab order, so the user's ordering decides whose
 * tasks come first. Each item's `source` is set to the module that provided
 * it, and a repeated `(source, id)` keeps only its first occurrence. Events
 * are the one exception: they merge by id across modules (see `events`).
 */
export class ProviderSnapshot {
  /** Tasks in tab order, then each module's own order. */
  readonly tasks: readonly ProvidedTask[];
  /**
   * Events from every module, by start time. Unlike tasks and progress,
   * events are keyed by id alone, across modules: an event id is the
   * calendar's own identifier, so two modules that read the same calendar
   * list a meeting once, and the first in tab order wins. Ids that are not
   * calendar identifiers should carry a module prefix so they never merge
   * by accident.
   */
  readonly events: readonly UpcomingEvent[];
  readonly progress: readonly ProgressItem[];
  /**
   * The one clock the app shows when several modules run one (say the
   * Pomodoro and a Study block): a running clock beats a paused one, which
   * beats an idle one. Among running clocks the most recently started or
   * resumed one wins (`focusStarts`), since that is the one the user just
   * turned to; the rest, and clocks with no known start, go by tab order.
   * Its `source` is the module running it, so a click on its preview opens
   * that module.
   */
  readonly focus: ProvidedFocus | undefined;
  /** Every module's study tally added up; undefined when no module keeps one. */
  readonly study: StudyDayTally | undefined;
  /** The first pet in tab order. */
  readonly pet: PetPresence | undefined;
  /** The first party in tab order. */
  readonly party: ProvidedParty | undefined;
  /** Highlights in tab order, then each module's own order. */
  readonly highlights: readonly TickerHighlight[];
  /** Whether any module is playing music. */
  readonly isPlaying: boolean;
  /** The count each module's tab shows, for modules with one above zero. */
  readonly badges: ReadonlyMap<ModuleID, number>;

  /**
   * Merges `provisions` from modules listed in tab order. `focusStarts` says
   * when each module's focus clock last started or resumed running, which
   * decides between two running clocks.
   */
  constructor(provisions: readonly ModuleProvisionEntry[] = [], focusStarts: ReadonlyMap<ModuleID, Instant> = new Map()) {
    const tasks: ProvidedTask[] = [];
    const progress: ProgressItem[] = [];
    const highlights: TickerHighlight[] = [];
    const events: UpcomingEvent[] = [];
    const badges = new Map<ModuleID, number>();
    const taskKeys = new Set<string>();
    const progressKeys = new Set<string>();
    const highlightKeys = new Set<string>();
    const eventIDs = new Set<string>();
    const clocks: ProvidedFocus[] = [];
    let study: StudyDayTally | undefined;
    let pet: PetPresence | undefined;
    let party: ProvidedParty | undefined;
    let isPlaying = false;
    for (const { module, provision } of provisions) {
      for (const task of provision.tasks) {
        const key = itemKey(module, task.id);
        if (taskKeys.has(key)) continue;
        taskKeys.add(key);
        tasks.push({ ...task, source: module });
      }
      for (const item of provision.progress) {
        const key = itemKey(module, item.id);
        if (progressKeys.has(key)) continue;
        progressKeys.add(key);
        progress.push(item.withSource(module));
      }
      for (const highlight of provision.highlights) {
        const key = itemKey(module, highlight.id);
        if (highlightKeys.has(key)) continue;
        highlightKeys.add(key);
        highlights.push(highlight.withSource(module));
      }
      if (provision.isPlaying) isPlaying = true;
      if (provision.badge > 0) badges.set(module, provision.badge);
      pet ??= provision.pet;
      for (const event of provision.events) {
        if (eventIDs.has(event.id)) continue;
        eventIDs.add(event.id);
        events.push(event);
      }
      if (provision.study) study = addStudyDayTallies(study ?? EMPTY_STUDY_DAY_TALLY, provision.study);
      party ??= provision.party;
      if (provision.focus) clocks.push(provision.focus.withSource(module));
    }
    this.tasks = tasks;
    this.progress = progress;
    this.highlights = highlights;
    /* Array sort is stable, so events with equal starts keep their tab order. */
    this.events = events.sort((a, b) => a.start - b.start);
    this.focus = ProviderSnapshot.leadingClock(clocks, focusStarts);
    this.study = study;
    this.pet = pet;
    this.party = party;
    this.isPlaying = isPlaying;
    this.badges = badges;
  }

  static readonly empty = new ProviderSnapshot();

  /** The clock `focus` picks from `clocks`, which are in tab order. */
  private static leadingClock(clocks: readonly ProvidedFocus[], focusStarts: ReadonlyMap<ModuleID, Instant>): ProvidedFocus | undefined {
    const rank = (clock: ProvidedFocus) => (clock.isRunning ? 2 : clock.isPaused ? 1 : 0);
    const start = (clock: ProvidedFocus) => (clock.isRunning ? (focusStarts.get(clock.source) ?? -Infinity) : -Infinity);
    let best: ProvidedFocus | undefined;
    for (const clock of clocks) {
      /* Only a strictly better clock replaces the leader, so an earlier tab wins a tie. */
      if (best === undefined || rank(clock) > rank(best) || (rank(clock) === rank(best) && start(clock) > start(best))) {
        best = clock;
      }
    }
    return best;
  }

  /** Tasks not done yet, in order. */
  get openTasks(): ProvidedTask[] {
    return this.tasks.filter((task) => !task.isDone);
  }
}
