import { tr } from "../localization/tr";
import { breedsOf } from "../pets/petBreed";
import { PET_ITEM_THEMES, itemIsNew, themeItems, type PetItemTheme } from "../pets/petItemTheme";
import { itemParts, outfitItem, accessoryItem, itemFromID, type PetItem } from "../pets/petItem";
import type { PetBreed, PetSpecies } from "../pets/petKinds";
import { colorFromHex, colorHex, type PetColor } from "../pets/petPalette";
import { PetProfile, defaultPetName } from "../pets/petProfile";
import { PetSave } from "../pets/petSave";
import { PetPointsLedger, PetPurchaseError, SHOP_ITEMS, itemCost } from "../pets/petUnlocks";
import { StudyStreak } from "../streaks/studyStreak";
import type { DayCalendar } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import { PET_LIMITED_EDITIONS, editionItem, editionMilestone, isLimited, type PetMilestoneProgress } from "./petLimited";

/*
 * Port of PetCloset.swift: the Closet tab's editing rules over one PetSave.
 * Every edit keeps the save valid (a pet only ever wears owned items), so
 * the app can persist `save` after any call without further checks.
 */

/** Where a costume item stands for the wardrobe grid. Port of PetClosetItemState. */
export type PetClosetItemState =
  | { readonly kind: "wearing" }
  | { readonly kind: "owned" }
  | { readonly kind: "affordable" }
  | { readonly kind: "locked"; readonly missing: number }
  | { readonly kind: "unearned" };

export function stateIsOwned(state: PetClosetItemState): boolean {
  return state.kind === "wearing" || state.kind === "owned";
}

/** What a tap on a wardrobe tile did. Port of PetClosetTapResult. */
export type PetClosetTapResult =
  | { readonly kind: "wore" }
  | { readonly kind: "tookOff" }
  | { readonly kind: "boughtAndWore" }
  | { readonly kind: "needsPoints"; readonly missing: number }
  | { readonly kind: "notEarnedYet" };

/** A rare fur a surprise gift can bring, as the swatch names read it (the Mac's RareFur.all). */
const RARE_FURS: readonly { readonly name: string; readonly color: PetColor }[] = [
  { name: "Mint", hex: "#A9DCC4" },
  { name: "Honey", hex: "#E6C36A" },
  { name: "Midnight", hex: "#5C6A8E" },
  { name: "Moonstone", hex: "#D7DCE8" },
].flatMap(({ name, hex }) => {
  const color = colorFromHex(hex);
  return color ? [{ name, color }] : [];
});

function colorsFrom(hexes: readonly string[]): PetColor[] {
  return hexes.flatMap((hex) => colorFromHex(hex) ?? []);
}

/** A seasonal event tally, as far as the Closet reads it: the items its runs earned. */
export interface SeasonalTally {
  readonly earned: readonly PetItem[];
}

export class PetCloset {
  save: PetSave;

  constructor(save: PetSave) {
    this.save = save;
    const tint = save.profile.furTint;
    const replacement = tint ? RETIRED_SWATCHES.get(colorHex(tint)) : undefined;
    if (replacement) this.save.profile.tintFur(replacement);
  }

  get profile(): PetProfile {
    return this.save.profile;
  }

  get balance(): number {
    return this.save.ledger.balance;
  }

  /** The shop items the wardrobe grid shows, cheapest first. "No outfit" is not a tile. */
  static readonly wardrobe: readonly PetItem[] = SHOP_ITEMS.filter((item) => item !== outfitItem("none"));

  /** The limited edition items, in shelf order. */
  static readonly limitedShelf: readonly PetItem[] = PET_LIMITED_EDITIONS.map(editionItem);

  /** The wardrobe grouped by theme in shelf order, each shelf cheapest first. */
  static readonly shelves: readonly { readonly theme: PetItemTheme; readonly items: readonly PetItem[] }[] =
    PET_ITEM_THEMES.map((theme) => ({ theme, items: themeItems(theme) })).filter((shelf) => shelf.items.length > 0);

  /** Whether the tile shows a "New" badge: fresh in the catalog and not owned yet. */
  isNew(item: PetItem): boolean {
    return itemIsNew(item) && !this.save.ledger.owns(item);
  }

  state(item: PetItem): PetClosetItemState {
    if (this.save.ledger.owns(item)) return this.profile.isWearing(item) ? { kind: "wearing" } : { kind: "owned" };
    if (isLimited(item)) return { kind: "unearned" };
    const missing = itemCost(item) - this.balance;
    return missing <= 0 ? { kind: "affordable" } : { kind: "locked", missing };
  }

  /** One tap on a tile: owned items toggle, affordable items are bought and worn, locked items change nothing. */
  tap(item: PetItem): PetClosetTapResult {
    const state = this.state(item);
    switch (state.kind) {
      case "wearing": {
        const profile = this.save.profile.copy();
        const parts = itemParts(item);
        if (parts.kind === "outfit") profile.outfit = "none";
        else profile.takeOff(parts.accessory);
        this.save.profile = profile;
        return { kind: "tookOff" };
      }
      case "owned":
        this.save.profile = PetCloset.wearing(item, this.save.profile);
        return { kind: "wore" };
      case "affordable":
        try {
          this.save.ledger.buy(item);
        } catch (error) {
          if (error instanceof PetPurchaseError && error.reason === "notEnoughPoints") {
            return { kind: "needsPoints", missing: error.missing };
          }
        }
        this.save.profile = PetCloset.wearing(item, this.save.profile);
        return { kind: "boughtAndWore" };
      case "locked":
        return { kind: "needsPoints", missing: state.missing };
      case "unearned":
        return { kind: "notEarnedYet" };
    }
  }

  /** The profile with `item` put on, for hover previews as well as real changes. Ownership is not checked here. */
  static wearing(item: PetItem, profile: PetProfile): PetProfile {
    const copy = profile.copy();
    const parts = itemParts(item);
    if (parts.kind === "outfit") copy.outfit = parts.outfit;
    else copy.wear(parts.accessory);
    return copy;
  }

  rename(name: string): void {
    this.save.profile.rename(name);
  }

  /**
   * Switches between cat and dog: the species' first breed, and a default
   * name follows the new species while a chosen name is kept.
   */
  setSpecies(species: PetSpecies): void {
    const current = this.profile.copy();
    const breed = breedsOf(species)[0];
    if (current.species === species || !breed) return;
    this.setBreed(breed);
    this.save.profile.rename(current.hasDefaultName ? defaultPetName(breed) : current.name);
  }

  /** Steps through the current species' breeds, wrapping at both ends. */
  cycleBreed(offset: number): void {
    const breeds = breedsOf(this.profile.species);
    const index = breeds.indexOf(this.profile.breed);
    if (index < 0 || breeds.length === 0) return;
    const next = breeds[(((index + offset) % breeds.length) + breeds.length) % breeds.length];
    if (next) this.setBreed(next);
  }

  /** Changes the breed; the fur tint carries over and follows the new breed's tones. */
  setBreed(breed: PetBreed): void {
    this.save.profile.breed = breed;
  }

  /** Fur colors offered as swatches; the breed's own colors are offered separately. */
  static readonly furSwatches: readonly PetColor[] = colorsFrom([
    "#F2A65A",
    "#C98B5B",
    "#8A5A3C",
    "#5E5856",
    "#A3A9B2",
    "#F3E2C4",
    "#B9A7D6",
    "#9EC3EC",
  ]);

  /** The name shown for a swatch ("Caramel") or a rare fur ("Mint"), or undefined for other colors. */
  static swatchName(color: PetColor): string | undefined {
    const names = [
      tr("Orange"),
      tr("Caramel"),
      tr("Chocolate"),
      tr("Charcoal"),
      tr("Silver"),
      tr("Cream"),
      tr("Lilac"),
      tr("Sky"),
    ];
    const hex = colorHex(color);
    const index = PetCloset.furSwatches.findIndex((swatch) => colorHex(swatch) === hex);
    if (index >= 0) return names[index];
    const rare = RARE_FURS.find((fur) => colorHex(fur.color) === hex);
    return rare ? tr(rare.name) : undefined;
  }

  get furTint(): PetColor | undefined {
    return this.profile.furTint;
  }

  tintFur(color: PetColor | undefined): void {
    this.save.profile.tintFur(color);
  }

  /** Credits a surprise gift's bonus points. */
  receiveGift(points: number): void {
    this.save.ledger.recordGift(points);
  }

  /** Credits a study session; see PetPointsRules. */
  recordStudy(minutes: number, completed: boolean): number {
    return this.save.ledger.recordStudy(minutes, completed);
  }

  /** The cheapest item not owned yet, and how many points it still needs (0 when affordable). */
  get nextUnlock(): { item: PetItem; missing: number } | undefined {
    const item = this.save.ledger.nextUnlock;
    return item ? { item, missing: Math.max(0, itemCost(item) - this.balance) } : undefined;
  }

  /** The study streak on `today`, from the milestones' study days and the freezes this save bought. */
  streak(progress: PetMilestoneProgress, today: Instant, calendar: DayCalendar): StudyStreak {
    return new StudyStreak(progress.studyDays, this.save.ledger.streakFreezes, today, calendar);
  }

  /** Buys an extra streak freeze with points; throws a StreakFreezePurchaseError when it cannot. */
  buyStreakFreeze(progress: PetMilestoneProgress, date: Instant, calendar: DayCalendar): void {
    this.save.ledger.buyStreakFreeze(this.streak(progress, date, calendar), date);
  }

  /** Grants the limited items whose milestones `progress` has reached, returning the new ones. */
  unlockMilestones(progress: PetMilestoneProgress): PetItem[] {
    return PET_LIMITED_EDITIONS.flatMap((edition) => {
      const milestone = editionMilestone(edition);
      if (!milestone || !progress.isReached(milestone)) return [];
      return this.save.ledger.grant(editionItem(edition)) ? [editionItem(edition)] : [];
    });
  }

  /** Grants the seasonal items some event run in `tally` has earned, returning the new ones. */
  unlockSeasonal(tally: SeasonalTally): PetItem[] {
    return tally.earned.filter((item) => this.save.ledger.grant(item));
  }

  /** Applies the item ids the Tabbi server granted; unknown ids and shop items are ignored. */
  applyGrants(ids: Iterable<string>): PetItem[] {
    const items = new Set([...ids].flatMap((id) => itemFromID(id) ?? []));
    return PetCloset.limitedShelf.filter((item) => items.has(item) && this.save.ledger.grant(item));
  }

  /**
   * The demo closet the screenshots show: a well-stocked wardrobe weeks in,
   * the Cozy Hoodie and the Beanie worn. Never a cape (the product rule for
   * demo and snapshot art), though both capes exist in the Closet.
   */
  static demo(): PetCloset {
    const purchased: PetItem[] = [
      accessoryItem("beanie"),
      accessoryItem("roundGlasses"),
      outfitItem("scrubs"),
      accessoryItem("stethoscope"),
      accessoryItem("surgicalCap"),
      accessoryItem("chunkyHeadphones"),
      accessoryItem("headMirror"),
      outfitItem("cozyHoodie"),
    ];
    const spent = purchased.reduce((sum, item) => sum + itemCost(item), 0);
    const ledger = new PetPointsLedger({
      earned: spent + 240,
      spent,
      purchased,
      granted: [editionItem("launchWeekCap"), editionItem("foundingMember")],
    });
    const profile = new PetProfile("Mochi", "britishShorthair", { outfit: "cozyHoodie", accessories: ["beanie"] });
    return new PetCloset(new PetSave(profile, ledger));
  }
}

/** Swatches offered by earlier builds, paired with the swatch that took each one's place. */
const RETIRED_SWATCHES = new Map<string, PetColor>(
  [
    ["#3B3434", "#5E5856"],
    ["#9AA3AD", "#A3A9B2"],
    ["#F4ECE0", "#F3E2C4"],
    ["#E58FA8", "#B9A7D6"],
    ["#8FB8E8", "#9EC3EC"],
  ].flatMap(([from, to]) => {
    const replacement = colorFromHex(to ?? "");
    return from && replacement ? [[from, replacement] as [string, PetColor]] : [];
  }),
);
