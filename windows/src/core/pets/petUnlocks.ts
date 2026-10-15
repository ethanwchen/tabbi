import { PET_PRICE_TIERS, tierForCost, tierPriceRange, type PetPriceTier } from "../closet/petEconomy";
import { PET_LIMITED_EDITIONS, editionItem, isLimited } from "../closet/petLimited";
import { StreakFreezeRules, type StudyStreak } from "../streaks/studyStreak";
import type { Instant } from "../time";
import { ALL_ITEMS_IN_DECLARATION_ORDER, accessoryItem, itemFromID, type PetItem } from "./petItem";
import { PetPointsRules } from "./petPointsRules";

/*
 * Port of PetUnlocks.swift: item prices, the points ledger and the rules
 * for buying items and streak freezes.
 */

/** Swift's `Date` encodes as seconds since 2001-01-01, so saves stay readable on both platforms. */
export const REFERENCE_DATE_OFFSET = 978307200;

/**
 * Price in study points (1 per focused minute, 35 for a finished 25 minute
 * block), set against three blocks a day, five days a week. Limited
 * edition items have no price and are not for sale.
 */
export function itemCost(item: PetItem): number {
  return ITEM_COSTS[item] ?? 0;
}

const ITEM_COSTS: Partial<Record<PetItem, number>> = {
  /* Starters: up to one typical day (105). */
  "accessory.beanie": 35,
  "accessory.roundGlasses": 50,
  "accessory.ninjaHeadband": 65,
  "accessory.bunnyEars": 75,
  "accessory.coolSunglasses": 90,
  "accessory.flowerCrown": 105,
  /* Mid-tier: two to five typical days (210 to 525). */
  "accessory.frogHat": 210,
  "outfit.scrubs": 240,
  "accessory.stethoscope": 270,
  "accessory.cowboyHat": 300,
  "accessory.surgicalCap": 330,
  "accessory.chefHat": 360,
  "outfit.cozyHoodie": 390,
  "accessory.chunkyHeadphones": 420,
  "accessory.headMirror": 450,
  "accessory.witchHat": 480,
  "accessory.pirateHat": 520,
  /* Showpieces: two to four typical weeks (1050 to 2100). */
  "accessory.tinyCrown": 1050,
  "accessory.wizardHat": 1150,
  "outfit.whiteCoat": 1250,
  "outfit.superheroCape": 1400,
  "outfit.dinosaurHoodie": 1500,
  "outfit.wizardRobe": 1650,
  "accessory.astronautHelmet": 1800,
  "accessory.blindfoldedSorcerer": 1950,
  "accessory.graduationCap": 2100,
  /* Animated showpieces sit at the top of the tier. */
  "accessory.rainCloud": 1600,
  "accessory.cherryPetals": 1700,
  "accessory.sparkleTrail": 1750,
  "accessory.halo": 1900,
  "accessory.angelWings": 2000,
  "accessory.kingsCape": 2050,
};

/** Owned from the start. Limited edition items cost nothing but are never free. */
export function isFree(item: PetItem): boolean {
  return itemCost(item) === 0 && !isLimited(item);
}

/** The item's price tier; a price in a gap counts as the tier below. */
export function itemTier(item: PetItem): PetPriceTier {
  const price = itemCost(item);
  const exact = tierForCost(price);
  if (exact) return exact;
  let below: PetPriceTier = "free";
  for (const tier of PET_PRICE_TIERS) if (tierPriceRange(tier).upper < price) below = tier;
  return below;
}

/** Every item: the shop cheapest first (ties by id), then the limited edition items in shelf order. */
export const ALL_ITEMS: readonly PetItem[] = [
  ...ALL_ITEMS_IN_DECLARATION_ORDER.filter((item) => !isLimited(item)).sort(
    (a, b) => itemCost(a) - itemCost(b) || (a < b ? -1 : a > b ? 1 : 0),
  ),
  ...PET_LIMITED_EDITIONS.map(editionItem),
];

/** The items points can buy (and the free starters), cheapest first. */
export const SHOP_ITEMS: readonly PetItem[] = ALL_ITEMS.filter((item) => !isLimited(item));

/** Why a purchase was refused. Port of PetPurchaseError. */
export class PetPurchaseError extends Error {
  constructor(
    readonly reason: "alreadyOwned" | "notForSale" | "notEnoughPoints",
    readonly missing = 0,
  ) {
    super(reason === "notEnoughPoints" ? `${missing} more points needed` : reason);
  }
}

/** Why an extra streak freeze could not be bought. Port of StreakFreezePurchaseError. */
export class StreakFreezePurchaseError extends Error {
  constructor(
    readonly reason: "holdingLimit" | "notEnoughPoints",
    readonly missing = 0,
  ) {
    super(reason === "notEnoughPoints" ? `${missing} more points needed` : reason);
  }
}

/** What older builds charged for items that are free now; a save that still lists one gets its points back once. */
const REFUNDED_PRICES: Partial<Record<PetItem, number>> = { [accessoryItem("scarf")]: 30 };

/**
 * The user's study points and the items they own. Points are kept as
 * lifetime earned and spent, so the balance can never drift. Port of
 * PetPointsLedger.
 */
export class PetPointsLedger {
  private earnedPoints: number;
  private spentPoints: number;
  /** Purchased items. Free items are owned implicitly and never stored. */
  private readonly purchasedItems: Set<PetItem>;
  /** Limited edition items earned or granted, kept for good. */
  private readonly grantedItems: Set<PetItem>;
  /** When each extra streak freeze was bought, oldest first. */
  private freezes: Instant[];

  constructor(
    options: {
      earned?: number;
      spent?: number;
      purchased?: Iterable<PetItem>;
      granted?: Iterable<PetItem>;
      streakFreezes?: Iterable<Instant>;
    } = {},
  ) {
    this.earnedPoints = Math.max(0, options.earned ?? 0);
    this.purchasedItems = new Set([...(options.purchased ?? [])].filter((item) => !isFree(item) && !isLimited(item)));
    this.grantedItems = new Set([...(options.granted ?? [])].filter(isLimited));
    this.spentPoints = Math.min(Math.max(0, options.spent ?? 0), this.earnedPoints);
    this.freezes = [...(options.streakFreezes ?? [])].sort((a, b) => a - b);
  }

  get earned(): number {
    return this.earnedPoints;
  }

  get spent(): number {
    return this.spentPoints;
  }

  get purchased(): ReadonlySet<PetItem> {
    return this.purchasedItems;
  }

  get granted(): ReadonlySet<PetItem> {
    return this.grantedItems;
  }

  get streakFreezes(): readonly Instant[] {
    return this.freezes;
  }

  get balance(): number {
    return this.earnedPoints - this.spentPoints;
  }

  copy(): PetPointsLedger {
    return new PetPointsLedger({
      earned: this.earnedPoints,
      spent: this.spentPoints,
      purchased: this.purchasedItems,
      granted: this.grantedItems,
      streakFreezes: this.freezes,
    });
  }

  owns(item: PetItem): boolean {
    return isFree(item) || this.purchasedItems.has(item) || this.grantedItems.has(item);
  }

  canBuy(item: PetItem): boolean {
    return !isLimited(item) && !this.owns(item) && this.balance >= itemCost(item);
  }

  /** Gives a limited edition item for free. Returns whether it is new; shop items are never granted. */
  grant(item: PetItem): boolean {
    if (!isLimited(item) || this.grantedItems.has(item)) return false;
    this.grantedItems.add(item);
    return true;
  }

  /** Credits a finished or abandoned study session and returns the points it earned. */
  recordStudy(minutes: number, completed: boolean): number {
    const points = PetPointsRules.points(minutes, completed);
    this.earnedPoints += points;
    return points;
  }

  /** Credits a surprise gift's bonus points. */
  recordGift(points: number): void {
    this.earnedPoints += Math.max(0, points);
  }

  /** Credits a stay in a Party shared session and returns the points it earned. */
  recordSharedSession(minutes: number, friends: number, finished = true): number {
    const points = PetPointsRules.sharedPoints(minutes, friends, finished);
    this.earnedPoints += points;
    return points;
  }

  /** Buys a shop item; throws a PetPurchaseError when it cannot. */
  buy(item: PetItem): void {
    if (this.owns(item)) throw new PetPurchaseError("alreadyOwned");
    if (isLimited(item)) throw new PetPurchaseError("notForSale");
    const cost = itemCost(item);
    if (this.balance < cost) throw new PetPurchaseError("notEnoughPoints", cost - this.balance);
    this.spentPoints += cost;
    this.purchasedItems.add(item);
  }

  /** Buys an extra streak freeze; `streak` is the streak as it stands at `date`. */
  buyStreakFreeze(streak: StudyStreak, date: Instant): void {
    if (!streak.canBuyFreeze) throw new StreakFreezePurchaseError("holdingLimit");
    const price = StreakFreezeRules.price();
    if (this.balance < price) throw new StreakFreezePurchaseError("notEnoughPoints", price - this.balance);
    this.spentPoints += price;
    this.freezes = [...this.freezes, date].sort((a, b) => a - b);
  }

  /** Adds freezes bought on another copy of this ledger, whose points are already spent. */
  keepStreakFreezes(other: PetPointsLedger): void {
    this.freezes = [...new Set([...this.freezes, ...other.streakFreezes])].sort((a, b) => a - b);
  }

  /** The cheapest shop item not yet owned, for a "next unlock" hint. */
  get nextUnlock(): PetItem | undefined {
    return SHOP_ITEMS.find((item) => !this.owns(item));
  }

  equals(other: PetPointsLedger): boolean {
    const sameSet = (a: ReadonlySet<PetItem>, b: ReadonlySet<PetItem>) => a.size === b.size && [...a].every((x) => b.has(x));
    return (
      this.earned === other.earned &&
      this.spent === other.spent &&
      sameSet(this.purchased, other.purchased) &&
      sameSet(this.granted, other.granted) &&
      this.freezes.length === other.streakFreezes.length &&
      this.freezes.every((value, index) => value === other.streakFreezes[index])
    );
  }

  /** The Mac's JSON form: ids sorted, `granted` and `streakFreezes` only when not empty. */
  toJSON(): Record<string, unknown> {
    return {
      earned: this.earnedPoints,
      spent: this.spentPoints,
      purchased: [...this.purchasedItems].sort(),
      ...(this.grantedItems.size > 0 ? { granted: [...this.grantedItems].sort() } : {}),
      ...(this.freezes.length > 0 ? { streakFreezes: this.freezes.map((instant) => instant - REFERENCE_DATE_OFFSET) } : {}),
    };
  }

  /** Reads leniently: unknown item ids are skipped, and a save listing a now free item gets its price back. */
  static fromJSON(raw: unknown): PetPointsLedger {
    const object = typeof raw === "object" && raw !== null ? (raw as Record<string, unknown>) : {};
    const ids = (value: unknown) =>
      Array.isArray(value) ? value.filter((id): id is string => typeof id === "string") : [];
    const number = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : 0);
    const items = new Set(ids(object.purchased).flatMap((id) => itemFromID(id) ?? []));
    const refund = [...items].filter(isFree).reduce((sum, item) => sum + (REFUNDED_PRICES[item] ?? 0), 0);
    const freezes = Array.isArray(object.streakFreezes) && object.streakFreezes.every((value) => typeof value === "number")
      ? (object.streakFreezes as number[]).map((seconds) => seconds + REFERENCE_DATE_OFFSET)
      : [];
    return new PetPointsLedger({
      earned: number(object.earned),
      spent: number(object.spent) - refund,
      purchased: items,
      granted: ids(object.granted).flatMap((id) => itemFromID(id) ?? []),
      streakFreezes: freezes,
    });
  }
}
