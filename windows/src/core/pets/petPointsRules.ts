/*
 * Port of PetPointsRules: how study time turns into points, kept as plain
 * rules so the numbers are easy to tune and test.
 */
export const PetPointsRules = {
  /** One point per full minute studied. */
  pointsPerMinute: 1,
  /** Sessions shorter than this earn nothing, so starting and stopping a timer farms nothing. */
  minimumMinutes: 5,
  /** Finishing a focus block of at least `bonusMinutes` earns a bonus. */
  completionBonus: 10,
  bonusMinutes: 25,
  /** A finished Party shared session earns this much per friend who studied along. */
  sharedBonusPerFriend: 5,
  /** The most a shared session's team bonus adds. */
  maxSharedBonus: 15,

  /** Points for one study session. */
  points(minutes: number, completed: boolean): number {
    if (minutes < PetPointsRules.minimumMinutes) return 0;
    const bonus = completed && minutes >= PetPointsRules.bonusMinutes ? PetPointsRules.completionBonus : 0;
    return minutes * PetPointsRules.pointsPerMinute + bonus;
  },

  /**
   * Points for a stay in a Party shared session: a finished one pays a
   * completed solo session plus the team bonus; one cut short pays the
   * minutes studied, without bonuses.
   */
  sharedPoints(minutes: number, friends: number, finished = true): number {
    const solo = PetPointsRules.points(minutes, finished);
    if (!(solo > 0) || !finished) return solo;
    return solo + Math.min(Math.max(friends, 0) * PetPointsRules.sharedBonusPerFriend, PetPointsRules.maxSharedBonus);
  },
} as const;
