import type { ModuleID } from "../modules/moduleId";
import type { Instant } from "../time";

/** Port of TickerHighlight.Tone: how a highlight's text is colored. */
export type TickerHighlightTone =
  /** The module's accent, for a live number. */
  | "accent"
  /** Plain primary text, for a calm status. */
  | "primary"
  /** Secondary text, for something paused or waiting. */
  | "secondary"
  /** The danger color, for a limit that has been hit. */
  | "danger";

export const TICKER_HIGHLIGHT_TONES: readonly TickerHighlightTone[] = ["accent", "primary", "secondary", "danger"];

export interface TickerHighlightInit {
  id: string;
  source: ModuleID;
  symbol?: string | undefined;
  text: string;
  summary?: string | undefined;
  tone?: TickerHighlightTone;
  priority?: number;
  isPinned?: boolean;
  expiresAt?: Instant | undefined;
}

/**
 * Port of TickerHighlight: a short line a module wants beside the closed
 * island, such as "5h 86%" from AI Usage. The HighlightSource role of a
 * module: the ticker shows it with the module's symbol and accent and opens
 * that module on click, with no ticker code knowing the module.
 *
 * The ticker shows at most one highlight per module at a time: the one with
 * the highest `priority` that has not expired. Modules with highlights take
 * turns in the rotation, the highest priority first, ties in tab order.
 */
export class TickerHighlight {
  /** Stable within its source module. */
  readonly id: string;
  /** The module that provided it; `ProviderSnapshot` sets it when merging. */
  readonly source: ModuleID;
  /** Symbol name beside the island; undefined uses the source module's symbol. */
  readonly symbol: string | undefined;
  /** A few words, e.g. "5h 86%". The wing has room for about 20 characters. */
  readonly text: string;
  /** The full sentence for the tooltip, e.g. "Claude usage 5h 86%". */
  readonly summary: string;
  readonly tone: TickerHighlightTone;
  /** Higher wins, both within its module and in the rotation order. */
  readonly priority: number;
  /** Holds the island instead of rotating away, like an imminent meeting; only for what the user must not miss. */
  readonly isPinned: boolean;
  /**
   * When the highlight stops being true (say, a usage window resets). The
   * ticker hides it from then on and wakes up at that moment, so the module
   * doesn't have to publish again just to take it down.
   */
  readonly expiresAt: Instant | undefined;

  constructor(init: TickerHighlightInit) {
    this.id = init.id;
    this.source = init.source;
    this.symbol = init.symbol;
    this.text = init.text;
    this.summary = init.summary ?? init.text;
    this.tone = init.tone ?? "accent";
    this.priority = init.priority ?? 0;
    this.isPinned = init.isPinned ?? false;
    this.expiresAt = init.expiresAt;
  }

  /** The same highlight from `source`, as `ProviderSnapshot` stamps it when merging. */
  withSource(source: ModuleID): TickerHighlight {
    return new TickerHighlight({ ...this, source });
  }

  /** Whether the highlight still holds at `now`. */
  isLive(now: Instant): boolean {
    return this.expiresAt === undefined || this.expiresAt > now;
  }
}
