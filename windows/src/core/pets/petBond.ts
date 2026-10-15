import { tr } from "../localization/tr";
import { PET_COLLARS, type PetCollar } from "./costumeArt";

/*
 * Port of PetBond, PetCollar and PetBondLook: how close the pet and the user
 * have grown, from 1 ("Just met") to 10 ("Forever friends"), derived from
 * focused minutes and study days. Nothing ever takes bond away.
 */

export type { PetCollar } from "./costumeArt";
export { PET_COLLARS } from "./costumeArt";

/** The bond level that unlocks each collar. */
export function collarUnlockLevel(collar: PetCollar): number {
  switch (collar) {
    case "none":
      return 1;
    case "plain":
      return 2;
    case "bell":
      return 4;
    case "star":
      return 6;
    case "gold":
      return 8;
  }
}

export function collarDisplayName(collar: PetCollar): string {
  switch (collar) {
    case "none":
      return tr("No collar");
    case "plain":
      return tr("Plain collar");
    case "bell":
      return tr("Bell collar");
    case "star":
      return tr("Star tag");
    case "gold":
      return tr("Gold tag");
  }
}

/** The visible growth that comes with a bond level: a collar, a happier idle, a sparkle. */
export interface PetBondLook {
  readonly collar: PetCollar;
  readonly happyIdle: boolean;
  readonly sparkle: boolean;
}

/** The bond level that adds the happier idle. */
export const HAPPY_IDLE_LEVEL = 3;
/** The bond level that adds the soft sparkle. */
export const SPARKLE_LEVEL = 9;

export function bondLook(level: number): PetBondLook {
  let collar: PetCollar = "none";
  for (const candidate of PET_COLLARS) if (level >= collarUnlockLevel(candidate)) collar = candidate;
  return { collar, happyIdle: level >= HAPPY_IDLE_LEVEL, sparkle: level >= SPARKLE_LEVEL };
}

/** A pet that has just met its owner: nothing grown in yet. */
export const NO_BOND_LOOK: PetBondLook = bondLook(1);

export function bondLooksEqual(a: PetBondLook, b: PetBondLook): boolean {
  return a.collar === b.collar && a.happyIdle === b.happyIdle && a.sparkle === b.sparkle;
}

/** What the next level up unlocks, for a "Next: Bell collar" hint, or undefined. */
export function bondUnlock(level: number): string | undefined {
  const collar = PET_COLLARS.find((candidate) => collarUnlockLevel(candidate) === level && candidate !== "none");
  if (collar) return collarDisplayName(collar);
  if (level === HAPPY_IDLE_LEVEL) return tr("Happy wiggle");
  if (level === SPARKLE_LEVEL) return tr("Sparkle");
  return undefined;
}

/** What the bond is computed from: focused minutes and the days with enough study. */
export interface BondProgress {
  readonly focusMinutes: number;
  readonly studyDays: readonly string[];
}

/** Port of PetBond. */
export class PetBond {
  static readonly maxLevel = 10;
  /** Bond points needed to reach each level, level 1 first. */
  static readonly thresholds: readonly number[] = [0, 100, 300, 600, 1000, 1600, 2400, 3500, 5000, 7000];
  /** Bond points one study day adds on top of its minutes. */
  static readonly pointsPerStudyDay = 30;

  readonly points: number;

  constructor(points: number) {
    this.points = Math.max(0, points);
  }

  /** The bond for focused minutes and study days, from the activity log. */
  static fromProgress(progress: BondProgress): PetBond {
    const minutes = Number.isFinite(progress.focusMinutes) ? Math.floor(progress.focusMinutes) : 0;
    return new PetBond(minutes + progress.studyDays.length * PetBond.pointsPerStudyDay);
  }

  get level(): number {
    return PetBond.level(this.points);
  }

  static level(points: number): number {
    let index = -1;
    PetBond.thresholds.forEach((threshold, i) => {
      if (points >= threshold) index = i;
    });
    return index < 0 ? 1 : index + 1;
  }

  get tierName(): string {
    return PetBond.tierName(this.level);
  }

  static tierName(level: number): string {
    switch (Math.min(Math.max(level, 1), PetBond.maxLevel)) {
      case 1:
        return tr("Just met");
      case 2:
        return tr("New friends");
      case 3:
        return tr("Pals");
      case 4:
        return tr("Best friends");
      case 5:
        return tr("Study buddies");
      case 6:
        return tr("Partners in focus");
      case 7:
        return tr("Inseparable");
      case 8:
        return tr("Kindred spirits");
      case 9:
        return tr("Soulmates");
      default:
        return tr("Forever friends");
    }
  }

  get isMaxed(): boolean {
    return this.level === PetBond.maxLevel;
  }

  /** Points to reach the next level, or undefined at the top. */
  get pointsToNextLevel(): number | undefined {
    return this.isMaxed ? undefined : (PetBond.thresholds[this.level] ?? 0) - this.points;
  }

  /** How far into the current level the bond is, 0 to 1 (1 at the top). */
  get progressInLevel(): number {
    if (this.isMaxed) return 1;
    const floor = PetBond.thresholds[this.level - 1] ?? 0;
    const ceiling = PetBond.thresholds[this.level] ?? floor;
    return (this.points - floor) / (ceiling - floor);
  }

  get look(): PetBondLook {
    return bondLook(this.level);
  }
}
