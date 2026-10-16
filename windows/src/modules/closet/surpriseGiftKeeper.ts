/*
 * Port of SurpriseGiftKeeper: now and then a finished focus session brings
 * a small gift from the pet (`SurpriseGiftState` decides when and what).
 * The coach rolls once per award it celebrates and names the gift in its
 * bubble. Gifts are earned only: nothing is sold or spent to roll.
 *
 * The state lives in `Pet/gifts.json` and is written before the gift is
 * handed over, so a restart can never roll the same session twice. Demo and
 * snapshot runs never roll or write; a demo starts with two rare furs found
 * so the Closet shows them. The pet's adventure is wired in here: a gift
 * rolled for the session the pet just came home from is what it carried
 * back, and the journal line keeps it.
 */

import type { ModuleContext } from "../../app/context";
import { Emitter, Store } from "../../app/store";
import type { PetStudyAward } from "../../core/closet/petStudyCredit";
import { SurpriseGiftState, type RareFur, type SurpriseGiftDelivery } from "../../core/motivation/surpriseGift";
import type { JournalEntry } from "../../core/pets/petAdventure";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { Instant } from "../../core/time";
import type { ClosetStore } from "./closetStore";

export const GIFTS_DOCUMENT = "gifts.json";

export interface SurpriseGiftKeeperState {
  /** The rare furs found so far, which the Closet's Look offers. */
  readonly rareFurs: readonly RareFur[];
}

export class SurpriseGiftKeeper extends Store<SurpriseGiftKeeperState> {
  /** Each gift as the pet hands it over. */
  readonly delivered = new Emitter<SurpriseGiftDelivery>();
  /** The last gift handed over since launch. */
  latest: SurpriseGiftDelivery | undefined;

  /** How soon after the pet comes home a gift still counts as brought back: it only has to outlast a busy moment, never another session. */
  static readonly adventureWindow = 60;

  private gifts: SurpriseGiftState;
  private readonly store: DocumentStore | undefined;
  /** Set when the file could not be read: no gifts then, since a fresh state would forget the caps and could be farmed. */
  private unreadable = false;
  private readonly loaded: Promise<void>;
  /** The adventure the pet just came home from, and when, until the session's roll takes it. */
  private adventureReturn: { readonly entry: JournalEntry; readonly at: Instant } | undefined;

  constructor(
    private readonly context: ModuleContext,
    private readonly closet: ClosetStore,
  ) {
    const gifts = context.isDemo ? SurpriseGiftState.demo() : new SurpriseGiftState();
    super({ rareFurs: gifts.rareFurs });
    this.gifts = gifts;
    this.store = context.isDemo || context.isSnapshot ? undefined : context.storage.folder("Pet");
    this.loaded = this.store === undefined ? Promise.resolve() : this.load(this.store);
    closet.adventureReturns.on((entry) => {
      this.adventureReturn = { entry, at: context.now() };
    });
  }

  private async load(store: DocumentStore): Promise<void> {
    try {
      const text = await store.read(GIFTS_DOCUMENT);
      if (text === undefined) return;
      this.gifts = SurpriseGiftState.decode(text);
      this.setState({ rareFurs: this.gifts.rareFurs });
    } catch (error) {
      this.unreadable = true;
      this.context.logger.error("The surprise gifts file could not be read; no gifts until it can", error);
    }
  }

  /**
   * Rolls for the focus session behind `award`, saves the outcome, applies
   * a gift (bonus points go to the pet's balance; a rare fur joins the
   * Closet's Look) and publishes it. When the pet just came home from an
   * adventure, the gift is what it brought back and goes on that journal
   * line. Undefined when there is none. Resolves once the roll is saved.
   */
  async roll(award: PetStudyAward, date: Instant = this.context.now()): Promise<SurpriseGiftDelivery | undefined> {
    const adventure = this.takeAdventureReturn(date);
    const store = this.store;
    if (store === undefined) return undefined;
    await this.loaded;
    if (this.unreadable) return undefined;
    const season = this.closet.state.seasons.active(this.closet.seasonNow)[0]?.occurrence.event.id;
    const gift = this.gifts.rollAfter(award, date, this.context.timeZone(), Math.random, season);
    try {
      await store.write(GIFTS_DOCUMENT, this.gifts.encoded());
    } catch (error) {
      this.context.logger.error("The surprise gifts file could not be written", error);
    }
    if (gift === undefined) return undefined;
    if (gift.kind === "bonusPoints") this.closet.receiveGift(gift.points);
    if (gift.kind === "rareFur") this.setState({ rareFurs: this.gifts.rareFurs });
    const carried = adventure === undefined ? undefined : this.closet.recordGift(gift, adventure);
    const delivery: SurpriseGiftDelivery = { gift, date, ...(carried === undefined ? {} : { adventure: carried }) };
    this.latest = delivery;
    this.delivered.emit(delivery);
    return delivery;
  }

  /** The adventure the pet came home from within `adventureWindow` of `date`, if any; each one is taken once, by the roll right after it. */
  private takeAdventureReturn(date: Instant): JournalEntry | undefined {
    const pending = this.adventureReturn;
    this.adventureReturn = undefined;
    if (pending === undefined || Math.abs(date - pending.at) > SurpriseGiftKeeper.adventureWindow) return undefined;
    return pending.entry;
  }
}
