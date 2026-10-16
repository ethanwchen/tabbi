/*
 * Port of NotchPreviewLayout (Sources/TabbiKit/Notch): sizes for the closed
 * pill's live preview. The wing width is worked out from the text rather
 * than measured from the drawn page, so the pill's shape, its window region
 * and a snapshot all agree on it in the same frame. Text is measured by an
 * injected function (a canvas in the app, a fixed width in tests).
 */

import { FRAME_SIZE } from "../../core/pets/petComposer";
import type { ModuleCatalog } from "../../core/modules/moduleCatalog";
import { tr } from "../../core/localization/tr";
import {
  meetingOffersJoin,
  tickerPetIsSipping,
  type TickerItem,
} from "../../core/ticker/tickerItem";
import {
  tickerCharging,
  tickerFocusClock,
  tickerFocusSummary,
  tickerMeetingCountdown,
  tickerMeetingSummary,
  tickerPartySize,
  tickerPetExploring,
  tickerPetLabel,
  tickerPetSummary,
  tickerProgressLeft,
  tickerTasksLeft,
  TICKER_PET_SLEEPING,
} from "../../core/ticker/tickerFormat";
import type { Instant } from "../../core/time";
import { textWidth } from "./measure";

/** How wide `text` is in the preview's type: caption (10.5 px, medium) or the Join button's semibold. */
export type TextMeasure = (text: string, weight: "medium" | "semibold") => number;

export const PREVIEW = {
  iconSize: 20,
  /** Stroke of the ring that fills around the closed timer's icon. */
  focusRingWidth: 1.5,
  /** Gap between the wing content and the outer edge of the pill. */
  outerInset: 8,
  /** Keeps a long meeting title from turning the pill into a menu bar. */
  maxWingWidth: 120,
  /** Music keeps a narrow pair of wings: artwork and the equalizer (Theme.Layout.compactWingWidth). */
  compactWingWidth: 34,
  /** Pixels per sprite pixel for party pets: a 24 px pet fits the pill's height. */
  partyPetPixelSize: 0.75,
  /** Party pets overlap a little, since each sprite has empty room around it. */
  partyPetStep: 18,
  /** The pill's height (the virtual notch's 32 px bar). */
  barHeight: 32,
  joinHeight: 16,
  joinPadding: 6,
  chargingSymbolSize: 9,
  unlockHintWidth: 16,
  unlockHintHeight: 3,
  /** Gap between the trailing text and the middle of the pill. */
  innerGap: 8,
  /** The closed pet's sprite side, one pixel per sprite pixel (NotchPetWing.side). */
  petSide: FRAME_SIZE,
} as const;

/** Width of `count` overlapping party pets. */
export function partyPetsWidth(count: number): number {
  const side = FRAME_SIZE * PREVIEW.partyPetPixelSize;
  return count > 0 ? side + (count - 1) * PREVIEW.partyPetStep : 0;
}

/** The Join button's width, from its title in semibold. */
export function joinWidth(measure: TextMeasure): number {
  return Math.ceil(measure(tr("Join"), "semibold") + 2 * PREVIEW.joinPadding);
}

/** Width of each wing; both are equal so the pill stays centered. */
export function wingWidth(item: TickerItem, measure: TextMeasure, locale = "en"): number {
  const text = (value: string) => Math.ceil(measure(value, "medium"));
  let cap: number = PREVIEW.maxWingWidth;
  let content: number;
  switch (item.type) {
    case "nowPlaying":
      return PREVIEW.compactWingWidth;
    case "meeting": {
      /* The countdown rides beside the icon and the title has the other wing to itself. */
      const join = meetingOffersJoin(item.meeting) ? 4 + joinWidth(measure) : 0;
      cap += join;
      content = Math.max(PREVIEW.iconSize + 4 + text(tickerMeetingCountdown(item.meeting.timing)), text(item.meeting.title) + join);
      break;
    }
    case "focus":
      /* A fixed-width sample, so the wing doesn't breathe as the digits change. */
      content = text(tickerFocusClock(item.focus.time).replace(/\d/g, "0"));
      break;
    case "tasks":
      content = text(tickerTasksLeft(item.remaining));
      break;
    case "progress":
      content = text(tickerProgressLeft(item.item, locale));
      break;
    case "highlight":
      content = text(item.highlight.text);
      break;
    case "pet":
      if (tickerPetIsSipping(item.pet)) {
        content = Math.max(PREVIEW.chargingSymbolSize + 2 + text(tickerCharging()), PREVIEW.petSide);
      } else {
        /* Measured asleep (or exploring) too, so the wing doesn't jump when the pet dozes off. */
        const label = tickerPetLabel(item.pet);
        const name = label === undefined ? 0 : text(label) + 4;
        const state = item.pet.adventure === undefined ? TICKER_PET_SLEEPING : tickerPetExploring();
        content = Math.max(name + Math.max(text(state), PREVIEW.unlockHintWidth), PREVIEW.petSide);
      }
      break;
    case "party":
      content = Math.max(partyPetsWidth(item.party.pets.length), text(tickerPartySize(item.party.memberCount)));
      break;
  }
  const wing = Math.ceil(content + PREVIEW.outerInset + PREVIEW.innerGap);
  return Math.min(Math.max(wing, PREVIEW.iconSize + PREVIEW.outerInset + PREVIEW.innerGap), cap);
}

/** The icon beside the pill; a module's progress, and its highlight unless it names a symbol, use the module's symbol. */
export function previewSymbol(item: TickerItem, catalog: ModuleCatalog): string {
  switch (item.type) {
    case "meeting":
      return item.meeting.canJoin ? "video.fill" : "calendar";
    case "nowPlaying":
      return "music.note";
    case "focus":
      return item.focus.phase === "focus" ? "timer" : "cup.and.saucer.fill";
    case "tasks":
      return "checklist";
    case "progress":
      return catalog.descriptor(item.item.source).symbol;
    case "highlight":
      return item.highlight.symbol ?? catalog.descriptor(item.highlight.source).symbol;
    case "pet":
      return "pawprint.fill";
    case "party":
      return "person.3.fill";
  }
}

/** The full sentence for the tooltip, e.g. "Standup in 4 min". */
export function previewSummary(item: TickerItem, now: Instant, locale = "en"): string {
  switch (item.type) {
    case "meeting":
      return tickerMeetingSummary(item.meeting);
    case "nowPlaying":
      return tr("Now Playing");
    case "focus":
      return tickerFocusSummary(item.focus);
    case "tasks":
      return tickerTasksLeft(item.remaining);
    case "progress":
      return `${item.item.title}: ${tickerProgressLeft(item.item, locale)}`;
    case "highlight":
      return item.highlight.summary;
    case "pet":
      return tickerPetSummary(item.pet, now);
    case "party":
      return tickerPartySize(item.party.memberCount);
  }
}

/** Measures in the island font, as the page draws the preview. */
export const islandMeasure: TextMeasure = (text, weight) => textWidth(text, 10.5, weight === "semibold" ? 600 : 500);
