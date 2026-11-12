/*
 * Port of ClosetStore: the study pet's look and points, persisted as one
 * `PetSave` in the edition's `Pet` folder, plus the animated preview the
 * Closet shows. It is the only reader and writer of the pet's save: modules
 * share it as `studyPet(context)` and follow its state, so the Closet, the
 * coach, Study's corner pet and Party all show the same pet.
 *
 * Demo runs start from `PetCloset.demo` and never write; snapshot runs
 * neither read nor write the save, so they show a fresh install's starter
 * pet wherever they run. The host's storage is asynchronous, so a live run
 * starts on the kit's starter and takes the saved pet over the moment it
 * arrives; nothing is written before that, so a slow read can never be
 * overwritten by the starter.
 */

import { celebrations } from "../../app/celebrations";
import type { ModuleContext } from "../../app/context";
import type { KitApplication } from "../../app/settingsStore";
import { Emitter, Store } from "../../app/store";
import { activityDay, type ActivityRecord } from "../../core/activity/activityRecord";
import { PetCloset, type PetClosetTapResult } from "../../core/closet/petCloset";
import { starterForKit } from "../../core/closet/petKitDefaults";
import { PetMilestoneProgress } from "../../core/closet/petLimited";
import { creditFocus, creditPartySession, creditRecord, awardIsLevelUp, type PartySessionCompletion, type PetStudyAward } from "../../core/closet/petStudyCredit";
import { SeasonalEventCatalog, SeasonalEventTally } from "../../core/events/seasonalEventCatalog";
import { seasonalEventDemo } from "../../core/events/seasonalEventDemo";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { UnlockProgress } from "../../core/motivation/unlockProgress";
import type { SurpriseGift } from "../../core/motivation/surpriseGift";
import { entryDetail, entryText, PetAdventure, PetJournal, type JournalEntry, type JournalGift } from "../../core/pets/petAdventure";
import { PetBond, bondLooksEqual } from "../../core/pets/petBond";
import type { PetItem } from "../../core/pets/petItem";
import type { PetBreed, PetSpecies } from "../../core/pets/petKinds";
import { PetNightRhythm } from "../../core/pets/petNightRhythm";
import type { PetColor } from "../../core/pets/petPalette";
import { PetPresence } from "../../core/pets/petPresence";
import { PetProfile } from "../../core/pets/petProfile";
import { PetSave } from "../../core/pets/petSave";
import { PetPointsLedger, itemCost } from "../../core/pets/petUnlocks";
import type { PetRadiantIntensity } from "../../core/pets/radiant/radiantArt";
import { isRadiantEligible, radiantPrice } from "../../core/pets/radiant/radiantResolver";
import { editionItem } from "../../core/closet/petLimited";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { ProvidedFocus } from "../../core/providers/providedFocus";
import type { DayCalendar } from "../../core/streaks/dayCalendar";
import type { StudyStreak } from "../../core/streaks/studyStreak";
import { resolveTheme } from "../../core/themes/themeCatalog";
import type { Instant } from "../../core/time";
import { PetPlayer } from "../../ui/kit/petPlayer";
import { PetProgression, changeIsEmpty } from "../../core/progression/petProgression";
import { progressionDemo } from "../../core/progression/progressionDemo";
import { ProgressTally } from "../../core/progression/progressTally";
import { ProgressionSave } from "../../core/progression/progressionSave";
import { badgeFromID, badgeID, compareBadges } from "../../core/progression/progressTrack";
import { accentCss } from "../../ui/kit/tokens";
import { closetCalendar } from "./closetCalendar";
import { CLOSET_ACCENT } from "./closetDescriptor";

/** The Closet's sections, in the order its header lists them. Port of ClosetSection. */
export type ClosetSection = "activity" | "wardrobe" | "limited" | "goals" | "streak" | "look" | "weeks";

export const CLOSET_SECTIONS: readonly ClosetSection[] = ["activity", "wardrobe", "limited", "goals", "streak", "look", "weeks"];

/** The pet's save in the edition's `Pet` folder. */
export const PET_SAVE_DOCUMENT = "pet.json";
/** The adventure journal, beside the save but its own file, so it never syncs. */
export const PET_JOURNAL_DOCUMENT = "journal.json";
/** The Goals section's own file, beside the save; it never syncs. */
export const PET_PROGRESSION_DOCUMENT = "progression.json";

export interface ClosetState {
  /** The closet with the save; the same object across edits, which `revision` counts. */
  readonly closet: PetCloset;
  readonly revision: number;
  /** The pet as shown everywhere: the saved look plus what it has grown into with the bond. */
  readonly profile: PetProfile;
  /** An item the pointer rests on, shown on the big preview ("try it on") without changing the save. */
  readonly tryingOn: PetItem | undefined;
  /** The Closet's open section, kept while the island closes. */
  readonly section: ClosetSection;
  /** Progress toward the limited edition milestones, from the whole activity log. */
  readonly milestones: PetMilestoneProgress;
  /** Focus logged during each seasonal event run. */
  readonly seasons: SeasonalEventTally;
  /** The Goals section: badge tiers, monthly quests and the mastery outfits they unlock. */
  readonly progression: PetProgression;
  readonly journal: PetJournal;
  /** The saved pet plus when a study session last ran, which the closed island shows. */
  readonly presence: PetPresence;
  /** How close the pet and the user have grown. */
  readonly bond: PetBond;
  /** Whether the pet was ever saved; until then it is the kit's starter and follows kit switches. */
  readonly hasSave: boolean;
  /** Snapshot runs only: how far (0 to 1) a scrolling grid is scrolled, since a still image cannot scroll. */
  readonly snapshotScrolled: number | undefined;
  /** The item whose Radiant sheet is open in the wardrobe (to upgrade it, or set its effect), or undefined. */
  readonly radiantSheet: PetItem | undefined;
  /** The intensity the Radiant sheet previews on the big pet. */
  readonly radiantPreview: PetRadiantIntensity;
}

/**
 * The Radiant states the snapshot run shows: an upgrade about to be bought,
 * a pinned goal part of the way, and an upgraded item's setting. Port of
 * ClosetStore.RadiantSnapshot.
 */
export type RadiantSnapshot = "upgrade" | "goal" | "setting";

export const RADIANT_SNAPSHOT_UPGRADE_ITEM: PetItem = "accessory.wizardHat";
export const RADIANT_SNAPSHOT_GOAL_ITEM: PetItem = "accessory.blindfoldedSorcerer";

/** The item a Radiant shot's sheet is open on, if any. */
export function radiantSnapshotSheet(shot: RadiantSnapshot): PetItem | undefined {
  return shot === "upgrade" ? RADIANT_SNAPSHOT_UPGRADE_ITEM : shot === "setting" ? RADIANT_SNAPSHOT_GOAL_ITEM : undefined;
}

/**
 * A wardrobe weeks in: the showpieces these shots use owned, and a balance
 * that covers the Wizard Hat's upgrade (5,750) but is part of the way to the
 * sorcerer's (9,750).
 */
export function radiantSnapshotSave(shot: RadiantSnapshot, base: PetSave): PetSave {
  const owned: PetItem[] = [RADIANT_SNAPSHOT_UPGRADE_ITEM, RADIANT_SNAPSHOT_GOAL_ITEM, "outfit.whiteCoat", "accessory.tinyCrown"];
  const spent = base.ledger.spent + owned.reduce((sum, item) => sum + itemCost(item), 0);
  const purchased = [...base.ledger.purchased, ...owned];
  const ledgerWith = (earned: number) =>
    new PetPointsLedger({ earned, spent, purchased, granted: base.ledger.granted, streakFreezes: base.ledger.streakFreezes });
  let ledger = ledgerWith(spent + 6120);
  let profile = base.profile;
  switch (shot) {
    case "upgrade":
      profile = PetCloset.wearing(RADIANT_SNAPSHOT_UPGRADE_ITEM, profile);
      break;
    case "goal":
      ledger = ledgerWith(spent + 4210);
      profile = PetCloset.wearing(RADIANT_SNAPSHOT_GOAL_ITEM, profile);
      break;
    case "setting":
      /* Upgraded weeks ago: its price is spent, the rest is left. */
      ledger = ledgerWith(spent + 6120 + radiantPrice(RADIANT_SNAPSHOT_GOAL_ITEM));
      ledger.upgradeToRadiant(RADIANT_SNAPSHOT_GOAL_ITEM);
      profile = PetCloset.wearing("outfit.whiteCoat", PetCloset.wearing(RADIANT_SNAPSHOT_GOAL_ITEM, profile));
      break;
  }
  const save = new PetSave(profile, ledger);
  if (shot === "goal") save.radiantGoal = RADIANT_SNAPSHOT_GOAL_ITEM;
  save.creditedFocusCount = base.creditedFocusCount;
  return save;
}

export interface ClosetStoreOptions {
  /** Whether Reduce Motion is on, which keeps the pet home (and so out of the journal). */
  readonly reduceMotion?: () => boolean;
}

function systemReduceMotion(): boolean {
  return typeof window !== "undefined" && typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export class ClosetStore extends Store<ClosetState> {
  /** The large preview in the Closet. */
  readonly preview: PetPlayer;
  /** A snapshot run draws the study chart already filled in, since a still image can't play its entrance. */
  readonly isSnapshot: boolean;
  readonly isDemo: boolean;
  /** Points earned from study sessions, as they are credited, so the coach can send the pet out to celebrate. */
  readonly awards = new Emitter<PetStudyAward>();
  /** One value each time the pet comes back from an adventure as a focus block ends, with the journal line it brought back. */
  readonly adventureReturns = new Emitter<JournalEntry>();
  /** The save on every change, for sync. */
  readonly saves = new Emitter<PetSave>();
  /** When the user last changed the pet's look on this PC, so sync can tell the newest look; undefined until an edit since launch. */
  lookChangedAt: Instant | undefined;
  /** Whether Reduce Motion is on; read when a block ends, tests replace it. */
  reduceMotion: () => boolean;

  private readonly store: DocumentStore | undefined;
  /** Set when the save on disk could not be read: the closet then runs on a fresh pet but never overwrites the file. */
  private saveIsUnreadable = false;
  private journalIsUnreadable = false;
  /** Set when `progression.json` could not be read, so it is never overwritten. */
  private progressionIsUnreadable = false;
  /** The Goals section a snapshot run started with, while `showForSnapshot` shows a tier as new. */
  private snapshotProgression: PetProgression | undefined;
  /** Resolves once the saved pet (or none) has been read; writes wait for it. */
  private readonly loaded: Promise<void>;
  private readonly pinnedSeasonMoment: Instant | undefined;
  private lastFocus: ProvidedFocus | undefined;
  /** The closet a snapshot run started with, while `showForSnapshot` shows another. */
  private snapshotBase: PetCloset | undefined;
  private readonly stops: (() => void)[] = [];

  constructor(
    private readonly context: ModuleContext,
    options: ClosetStoreOptions = {},
  ) {
    const isDemo = context.isDemo;
    const isSnapshot = context.isSnapshot;
    const now = context.now();
    const calendar = closetCalendar(context.timeZone());
    const starter = starterForKit(context.activeKit?.defaults);
    const closet = isDemo ? PetCloset.demo() : new PetCloset(new PetSave(starter));
    const milestones = isDemo ? PetMilestoneProgress.demo(now, calendar) : new PetMilestoneProgress();
    const demoSeason = isDemo ? seasonalEventDemo(now, calendar.timeZone) : undefined;
    const seasons = demoSeason?.tally ?? new SeasonalEventTally(SeasonalEventCatalog.bundled, calendar.timeZone);
    const journal = isDemo ? PetJournal.demo(now) : new PetJournal(ClosetStore.randomSeed());
    const progression = isDemo ? progressionDemo(now, calendar) : new PetProgression();
    if (isDemo) closet.unlockMastery(progression);
    const bond = PetBond.fromProgress(milestones);
    const profile = ClosetStore.grown(closet.profile, bond);
    /* A snapshot renders the same pet whatever the hour, so only real and demo runs doze at night. */
    const presence = new PetPresence(profile, now, calendar, {
      ...(UnlockProgress.of(closet) === undefined ? {} : { nextUnlock: UnlockProgress.of(closet) }),
      ...(isSnapshot ? {} : { night: PetNightRhythm.standard }),
    });
    super({ closet, revision: 0, profile, tryingOn: undefined, section: "activity", milestones, seasons, progression, journal, presence, bond, hasSave: isDemo, snapshotScrolled: undefined, radiantSheet: undefined, radiantPreview: "bold" });
    this.isDemo = isDemo;
    this.isSnapshot = isSnapshot;
    this.pinnedSeasonMoment = demoSeason?.moment;
    this.reduceMotion = options.reduceMotion ?? systemReduceMotion;
    this.preview = new PetPlayer(profile);
    this.store = isDemo || isSnapshot ? undefined : context.storage.folder("Pet");
    this.loaded = this.store === undefined ? Promise.resolve() : this.load(this.store);
  }

  private static randomSeed(): bigint {
    const high = BigInt(Math.floor(Math.random() * 0x1_0000_0000));
    const low = BigInt(Math.floor(Math.random() * 0x1_0000_0000));
    return (high << 32n) | low;
  }

  private static grown(profile: PetProfile, bond: PetBond): PetProfile {
    const copy = profile.copy();
    copy.bondLook = bond.look;
    return copy;
  }

  /** Reads the save and the journal; a file that can't be read is left alone for good. */
  private async load(store: DocumentStore): Promise<void> {
    let save: PetSave | undefined;
    try {
      const text = await store.read(PET_SAVE_DOCUMENT);
      if (text !== undefined) save = PetSave.decode(JSON.parse(text));
    } catch (error) {
      this.saveIsUnreadable = true;
      this.context.logger.error("The pet's save could not be read; running on a fresh pet without overwriting it", error);
    }
    try {
      const journal = await PetJournal.load(store, PET_JOURNAL_DOCUMENT);
      if (journal !== undefined) this.setState({ journal });
    } catch (error) {
      this.journalIsUnreadable = true;
      this.context.logger.error("The pet's journal could not be read", error);
    }
    try {
      const text = await store.read(PET_PROGRESSION_DOCUMENT);
      if (text !== undefined) {
        const saved = ProgressionSave.decode(text);
        this.setState((state) => ({ progression: new PetProgression(saved, state.progression.tally) }));
      }
    } catch (error) {
      this.progressionIsUnreadable = true;
      this.context.logger.error("The Goals section's file could not be read", error);
    }
    if (save === undefined) return;
    /* A session that ran while the starter showed is already credited on the starter's save; the saved pet keeps its own baseline. */
    const closet = new PetCloset(save);
    this.replace(closet, { hasSave: true });
  }

  /** The moment the Closet reads seasonal events at: now, or in a demo a pinned moment inside the featured event. */
  get seasonNow(): Instant {
    return this.pinnedSeasonMoment ?? this.context.now();
  }

  /** Now, on the app's clock. */
  now(): Instant {
    return this.context.now();
  }

  get calendar(): DayCalendar {
    return closetCalendar(this.context.timeZone());
  }

  get closet(): PetCloset {
    return this.state.closet;
  }

  /** The pet as shown everywhere. */
  get profile(): PetProfile {
    return this.state.profile;
  }

  get bond(): PetBond {
    return this.state.bond;
  }

  /** The study streak today, with its freezes; computed on read, so it follows new study, purchases and a new day. */
  get streak(): StudyStreak {
    return this.state.closet.streak(this.state.milestones, this.context.now(), this.calendar);
  }

  /** The newest journal line with the pet's name ("Mochi explored the bookshelf"), or undefined before its first adventure. */
  get latestAdventure(): string | undefined {
    const latest = this.state.journal.latest;
    return latest === undefined ? undefined : entryText(latest, this.profile.name);
  }

  /** The newest journal line with the gift it brought home, if any, for tooltips. */
  get latestAdventureDetail(): string | undefined {
    const latest = this.state.journal.latest;
    return latest === undefined ? undefined : entryDetail(latest, this.profile.name);
  }

  /* Following */

  /** Follows the shared focus clock, so the pet stays awake through sessions and finished sessions earn points. */
  followFocus(): void {
    const snapshot = this.context.snapshot;
    this.lastFocus = snapshot.get().focus;
    this.state.presence.observe(this.lastFocus, this.context.now());
    this.stops.push(snapshot.subscribe(() => this.focusChanged(snapshot.get().focus)));
  }

  /**
   * Follows new activity records, so focus time cut short earns points once
   * per record, and study milestones and focus during seasonal events unlock
   * their limited edition items. The log so far counts toward both without
   * paying points again; a goal it already reached unlocks quietly.
   */
  async followActivity(): Promise<void> {
    const log = this.context.activityLog;
    this.stops.push(log.recorded((record) => this.recorded(record)));
    if (this.isDemo) return;
    const today = activityDay({ end: this.context.now() }, this.context.timeZone());
    const history = await log.recordsBetween("0001-01-01", today);
    const calendar = this.calendar;
    const milestones = new PetMilestoneProgress();
    const seasons = new SeasonalEventTally(SeasonalEventCatalog.bundled, calendar.timeZone);
    for (const record of history) {
      milestones.add(record, calendar);
      seasons.add(record);
    }
    this.setState({ milestones, seasons });
    this.bondMayHaveGrown();
    await this.loaded;
    /* Goals the log had already reached count quietly: saved, with a dot on the Goals pill, and nothing celebrates. */
    const progression = new PetProgression(this.state.progression.save, new ProgressTally(history, calendar));
    const change = progression.refresh(this.context.now(), this.state.closet.save.ledger.streakFreezes, calendar);
    this.setState({ progression });
    if (!changeIsEmpty(change)) this.persistProgression();
    if (this.unlockLimited().length > 0) this.persist();
  }

  /** Until the pet is saved, it is the active kit's starter pet. */
  followKits(): void {
    this.stops.push(this.context.kitApplied((application: KitApplication) => this.useStarter(starterForKit(application.kit.defaults))));
  }

  /**
   * Follows the island opening and closing (one value each time), which
   * wakes a pet dozing late at night. Closing counts too: the dozing pet
   * only shows on the closed island, so a wake spell that started when the
   * island opened could run out unseen.
   */
  followIslandToggles(): void {
    const kinds = this.context.closedPreview.watchedKinds;
    let wasEmpty = kinds.get().size === 0;
    this.stops.push(
      kinds.subscribe(() => {
        const empty = kinds.get().size === 0;
        if (empty === wasEmpty) return;
        wasEmpty = empty;
        this.state.presence.wake(this.context.now());
        /* Closing the island mid-hover sends no hover exit either. */
        if (!empty) this.tryOn(undefined);
      }),
    );
  }

  /** Stops following everything (the window is closing). */
  dispose(): void {
    for (const stop of this.stops) stop();
    this.stops.length = 0;
  }

  private recorded(record: ActivityRecord): void {
    const calendar = this.calendar;
    this.state.milestones.add(record, calendar);
    this.state.seasons.add(record);
    const progression = this.state.progression;
    progression.add(record, calendar);
    const goals = progression.refresh(this.context.now(), this.state.closet.save.ledger.streakFreezes, calendar);
    if (!changeIsEmpty(goals)) this.persistProgression();
    const award = creditRecord(this.state.closet, record);
    const unlocked = this.unlockLimited();
    this.bump();
    this.bondMayHaveGrown();
    if (award === undefined && unlocked.length === 0 && changeIsEmpty(goals)) return;
    if (award !== undefined || unlocked.length > 0) this.persist();
    if (award !== undefined) this.celebrate(award);
    if (unlocked.length > 0 || !changeIsEmpty(goals)) this.celebrateLimited();
  }

  /** Badge tiers reached since the Goals section was last open, for the dot on its pill. */
  get hasUnseenGoals(): boolean {
    return this.state.progression.unseen.length > 0;
  }

  /** The Goals section is showing: every tier reached so far is seen. */
  markGoalsSeen(): void {
    if (!this.state.progression.markSeen()) return;
    this.bump();
    this.persistProgression();
  }

  /** Grants the limited items the milestones and seasonal events have earned and returns the new ones. */
  private unlockLimited(): PetItem[] {
    const closet = this.state.closet;
    return [
      ...closet.unlockMilestones(this.state.milestones),
      ...closet.unlockSeasonal(this.state.seasons),
      ...closet.unlockMastery(this.state.progression),
    ];
  }

  /** A limited edition item just became the user's: the pet celebrates and the panel sparkles, like a purchase. */
  private celebrateLimited(): void {
    this.preview.send({ kind: "celebrate" });
    this.celebrateUnlock(false);
  }

  /** Takes the limited edition items the Tabbi server granted (by item id) and celebrates new ones; returns the new ones. */
  applyGrants(ids: Iterable<string>): PetItem[] {
    const granted = this.state.closet.applyGrants(ids);
    if (granted.length === 0) return [];
    this.bump();
    this.persist();
    this.celebrateLimited();
    return granted;
  }

  private focusChanged(timer: ProvidedFocus | undefined): void {
    const now = this.context.now();
    this.state.presence.observe(timer, now);
    const old = this.lastFocus;
    this.lastFocus = timer;
    const adventure = PetAdventure.finished(old, timer, now, this.reduceMotion());
    if (adventure !== undefined) this.adventureEnded(adventure);
    const closet = this.state.closet;
    const before = closet.save.copy();
    const award = creditFocus(closet, old, timer, now);
    /*
     * A starter pet that only saw an idle clock stays unsaved, so it keeps
     * following kit switches (the first-run kit pick comes after the first
     * timer the pet sees). Once a clock runs, the pet and its baseline are
     * saved, so a session that ends while Tabbi is closed is still paid on
     * the next launch.
     */
    const changed = !this.saveEquals(closet.save, before);
    if (changed || award !== undefined) this.bump();
    if (this.state.hasSave ? changed : award !== undefined || timer?.isActive === true) this.persist();
    if (award !== undefined) this.celebrate(award);
  }

  private saveEquals(a: PetSave, b: PetSave): boolean {
    return (
      a.profile.equals(b.profile) &&
      a.ledger.equals(b.ledger) &&
      a.creditedFocusCount === b.creditedFocusCount &&
      a.creditedFocusSource === b.creditedFocusSource &&
      a.radiantGoal === b.radiantGoal
    );
  }

  /** The pet is back from its adventure: a line goes into the journal and out to `adventureReturns`. */
  private adventureEnded(adventure: PetAdventure): void {
    const entry = this.state.journal.record(adventure.endsAt);
    this.bump();
    this.persistJournal();
    this.adventureReturns.emit(entry);
  }

  /** Writes a surprise gift onto the journal line of the adventure it was carried home from; undefined when the line is gone or already has a gift. */
  recordGift(gift: SurpriseGift, broughtBackFrom: JournalEntry): JournalEntry | undefined {
    const stored: JournalGift =
      gift.kind === "bonusPoints"
        ? { kind: "bonusPoints", points: gift.points }
        : gift.kind === "rareFur"
          ? { kind: "rareFur", id: gift.fur.id, name: gift.fur.name }
          : { kind: "seasonMinutes", eventID: gift.eventID, minutes: gift.minutes };
    const updated = this.state.journal.attach(stored, broughtBackFrom);
    if (updated === undefined) return undefined;
    this.bump();
    this.persistJournal();
    return updated;
  }

  private celebrate(award: PetStudyAward): void {
    this.preview.send({ kind: "celebrate" });
    if (awardIsLevelUp(award)) this.celebrateUnlock(award.completedSessions > 0);
    this.awards.emit(award);
  }

  /** Pays a Party shared session that ran to its end and makes the pet celebrate; Party shows the award itself, so the coach is not told. */
  creditParty(session: PartySessionCompletion): PetStudyAward | undefined {
    const award = creditPartySession(this.state.closet, session);
    if (award === undefined) return undefined;
    this.bump();
    this.persist();
    this.preview.send({ kind: "celebrate" });
    return award;
  }

  /** Credits a surprise gift's bonus points. */
  receiveGift(points: number): void {
    this.state.closet.receiveGift(points);
    this.bump();
    this.persist();
  }

  /* Bond */

  /** Puts on a collar or sparkle the bond just unlocked, on the Closet preview and the closed island's pet. */
  private bondMayHaveGrown(): void {
    const bond = PetBond.fromProgress(this.state.milestones);
    if (bondLooksEqual(bond.look, this.state.bond.look) && bond.points === this.state.bond.points) return;
    this.setState({ bond });
    this.refreshProfile();
  }

  /* Streak */

  /** Buys an extra streak freeze with points and saves it; false when the purchase can't go through. */
  buyStreakFreeze(): boolean {
    try {
      this.state.closet.buyStreakFreeze(this.state.milestones, this.context.now(), this.calendar);
    } catch {
      return false;
    }
    this.bump();
    this.persist();
    this.preview.send({ kind: "celebrate" });
    return true;
  }

  /* Editing */

  /** Wears, takes off, or buys `item`. A purchase makes the pet celebrate and sparkles over the panel. */
  tap(item: PetItem): PetClosetTapResult {
    const result = this.edit((closet) => closet.tap(item));
    if (result.kind === "boughtAndWore") {
      this.preview.send({ kind: "celebrate" });
      this.celebrateUnlock(false);
    }
    return result;
  }

  /* Radiant */

  /** Opens the Radiant sheet for `item` (previewing its Bold effect, or the effect as set when it is upgraded), or closes it with undefined. */
  showRadiant(item: PetItem | undefined): void {
    const sheet = item !== undefined && isRadiantEligible(item) ? item : undefined;
    const set = sheet === undefined ? undefined : this.state.closet.profile.radianceOf(sheet);
    this.setState({
      radiantSheet: sheet,
      ...(sheet === undefined ? {} : { radiantPreview: set === undefined || set === "off" ? "bold" : set }),
    });
    this.refreshPreview();
  }

  /** Previews the other intensity on the big pet while the sheet is open. */
  previewRadiance(intensity: PetRadiantIntensity): void {
    if (this.state.radiantSheet === undefined || intensity === "off") return;
    this.setState({ radiantPreview: intensity });
    this.refreshPreview();
  }

  /** Upgrades `item` to Radiant. The pet celebrates and the panel sparkles; the item is put on so the effect shows right away. */
  upgradeToRadiant(item: PetItem): boolean {
    const done = this.edit((closet) => {
      try {
        closet.upgradeToRadiant(item);
        return true;
      } catch {
        return false;
      }
    });
    if (!done) return false;
    this.setState({ radiantPreview: "bold" });
    this.refreshPreview();
    this.preview.send({ kind: "celebrate" });
    this.celebrateUnlock(false);
    return true;
  }

  /** Sets how strongly an upgraded item shows its effect. */
  setRadiance(intensity: PetRadiantIntensity, item: PetItem): void {
    this.edit((closet) => closet.setRadiance(intensity, item));
    if (intensity !== "off") this.setState({ radiantPreview: intensity });
    this.refreshPreview();
  }

  /** Pins (or with undefined, unpins) a Radiant upgrade as the wardrobe's goal. */
  pinRadiantGoal(item: PetItem | undefined): void {
    this.edit((closet) => closet.pinRadiantGoal(item));
  }

  private celebrateUnlock(hasOwnSound: boolean): void {
    const theme = resolveTheme(this.context.settings.current.themeID);
    celebrations(this.context).celebrate("milestone", "sparkles", accentCss(theme, CLOSET_ACCENT), theme, MODULE_IDS.closet, hasOwnSound);
  }

  rename(name: string): void {
    this.edit((closet) => closet.rename(name));
  }

  setSpecies(species: PetSpecies): void {
    this.edit((closet) => closet.setSpecies(species));
  }

  cycleBreed(offset: number): void {
    this.edit((closet) => closet.cycleBreed(offset));
  }

  setBreed(breed: PetBreed): void {
    this.edit((closet) => closet.setBreed(breed));
  }

  tintFur(color: PetColor | undefined): void {
    this.edit((closet) => closet.tintFur(color));
  }

  /** Replaces the pet's look as one edit (a profile another module hands over). */
  setProfile(profile: PetProfile): void {
    this.edit((closet) => {
      closet.save.profile = profile.restricted(closet.save.ledger);
    });
  }

  /** Starts or ends a hover preview of `item` on the big pet. */
  tryOn(item: PetItem | undefined): void {
    if (this.state.tryingOn === item) return;
    this.setState({ tryingOn: item });
    this.refreshPreview();
  }

  /** Switching sections mid-hover sends no hover exit, so the try-on ends here or it would greet the next visit. */
  setSection(section: ClosetSection): void {
    if (section === this.state.section) return;
    this.setState({ section });
    this.tryOn(undefined);
    if (this.state.radiantSheet !== undefined) this.showRadiant(undefined);
  }

  /**
   * Snapshot runs only: shows the pet as someone who never got the Founder's
   * Pin, or under another name, so the Closet's longest lines can be
   * reviewed; the defaults put the starting closet back.
   */
  showForSnapshot(
    options: {
      readonly foundingMember?: boolean;
      readonly name?: string;
      readonly scrolled?: number;
      /** Shows the newest badge tier as not seen yet (the Goals pill's dot). */
      readonly newGoal?: boolean;
      /** One of the Radiant shots. */
      readonly radiant?: RadiantSnapshot;
    } = {},
  ): void {
    if (!this.isSnapshot) return;
    this.setState({ snapshotScrolled: options.scrolled });
    this.showGoalForSnapshot(options.newGoal ?? false);
    const base = this.snapshotBase ?? this.state.closet;
    this.snapshotBase = base;
    const save = options.radiant === undefined ? base.save.copy() : radiantSnapshotSave(options.radiant, base.save);
    if (options.foundingMember === false) {
      const ledger = save.ledger;
      save.ledger = new PetPointsLedger({
        earned: ledger.earned,
        spent: ledger.spent,
        purchased: ledger.purchased,
        granted: [...ledger.granted].filter((item) => item !== editionItem("foundingMember")),
        streakFreezes: ledger.streakFreezes,
        radiant: ledger.radiant,
      });
      save.profile = save.profile.restricted(save.ledger);
    }
    if (options.name !== undefined) save.profile.rename(options.name);
    this.replace(new PetCloset(save), {});
    const sheet = options.radiant === undefined ? undefined : radiantSnapshotSheet(options.radiant);
    if (sheet !== this.state.radiantSheet) this.showRadiant(sheet);
  }

  /** Snapshot runs only: shows the highest tier reached as new and unseen, so the Goals pill's dot can be reviewed. */
  private showGoalForSnapshot(isNew: boolean): void {
    const base = this.snapshotProgression ?? this.state.progression;
    this.snapshotProgression = base;
    const save = base.save.copy();
    if (isNew) {
      const latest = [...save.reached.keys()].flatMap((id) => badgeFromID(id) ?? []).sort(compareBadges).pop();
      if (latest) save.seen.delete(badgeID(latest));
    }
    if (save.equals(this.state.progression.save)) return;
    const shown = new PetProgression(save, base.tally);
    shown.refresh(this.context.now(), this.state.closet.save.ledger.streakFreezes, this.calendar);
    this.setState({ progression: shown });
  }

  private persistProgression(): void {
    const store = this.store;
    if (store === undefined) return;
    void this.loaded.then(async () => {
      if (this.progressionIsUnreadable) return;
      try {
        await store.write(PET_PROGRESSION_DOCUMENT, this.state.progression.save.encoded());
      } catch (error) {
        this.context.logger.error("The Goals section's file could not be written", error);
      }
    });
  }

  private edit<Result>(change: (closet: PetCloset) => Result): Result {
    const closet = this.state.closet;
    const before = closet.profile.copy();
    const result = change(closet);
    if (!closet.profile.equals(before)) this.lookChangedAt = this.context.now();
    this.bump();
    this.refreshProfile();
    this.persist();
    return result;
  }

  /** Re-reads the grown profile and the next unlock after a change, and redraws the preview. */
  private refreshProfile(): void {
    const closet = this.state.closet;
    const profile = ClosetStore.grown(closet.profile, this.state.bond);
    const presence = this.state.presence;
    if (!presence.profile.equals(profile) || !bondLooksEqual(presence.profile.bondLook, profile.bondLook)) presence.profile = profile;
    presence.nextUnlock = UnlockProgress.of(closet);
    this.setState({ profile });
    this.refreshPreview();
  }

  private refreshPreview(): void {
    const tryingOn = this.state.tryingOn;
    let shown = tryingOn === undefined ? this.profile : PetCloset.wearing(tryingOn, this.profile);
    /* The Radiant sheet shows the effect it is about, worn, at the intensity picked (an item not upgraded yet shows what it would get). */
    const sheet = this.state.radiantSheet;
    if (sheet !== undefined) {
      shown = PetCloset.radiantPreview(sheet, this.state.radiantPreview, shown);
    }
    this.preview.update(shown);
  }

  /** A change inside the closet (same object): count it, so readers redraw. */
  private bump(): void {
    const closet = this.state.closet;
    const presence = this.state.presence;
    presence.nextUnlock = UnlockProgress.of(closet);
    this.setState((state) => ({ revision: state.revision + 1 }));
  }

  /** Swaps a pet that was never saved for a new kit's starter. */
  useStarter(starter: PetProfile): void {
    if (this.state.hasSave || this.saveIsUnreadable || this.state.closet.profile.equals(starter)) return;
    const save = new PetSave(starter);
    save.creditedFocusCount = this.state.closet.save.creditedFocusCount;
    save.creditedFocusSource = this.state.closet.save.creditedFocusSource;
    this.replace(new PetCloset(save), {});
  }

  /** Takes on the save a sync merged (the account's look, points and unlocks) and keeps it, like any edit. */
  adoptSynced(save: PetSave): void {
    if (this.saveEquals(save, this.state.closet.save)) return;
    this.replace(new PetCloset(save), { hasSave: true });
    this.persist();
  }

  private replace(closet: PetCloset, patch: Partial<Pick<ClosetState, "hasSave">>): void {
    this.setState((state) => ({ closet, revision: state.revision + 1, ...patch }));
    this.refreshProfile();
  }

  private persist(): void {
    const store = this.store;
    if (store === undefined) return;
    void this.loaded.then(async () => {
      if (this.saveIsUnreadable) return;
      const save = this.state.closet.save;
      try {
        await store.write(PET_SAVE_DOCUMENT, save.encoded());
        if (!this.state.hasSave) this.setState({ hasSave: true });
        this.saves.emit(save);
      } catch (error) {
        this.context.logger.error("The pet's save could not be written", error);
      }
    });
  }

  private persistJournal(): void {
    const store = this.store;
    if (store === undefined) return;
    void this.loaded.then(async () => {
      if (this.journalIsUnreadable) return;
      try {
        await this.state.journal.write(store, PET_JOURNAL_DOCUMENT);
      } catch (error) {
        this.context.logger.error("The pet's journal could not be written", error);
      }
    });
  }
}
