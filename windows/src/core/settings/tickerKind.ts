import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { ModuleID } from "../modules/moduleId";

/**
 * A narrow stand-in for the Ticker's TickerKind, which the ticker port owns:
 * the unit the user turns closed-notch previews on and off by. Open, like
 * ModuleID: besides the built-in kinds, every module that publishes
 * highlights gets a kind whose raw value is its module id. Settings and kit
 * validation only need the raw values and which ones a catalog can show.
 */
export type TickerKind = string;

/** Built-in kinds that come before module highlights in the rotation. */
export const LEADING_TICKER_KINDS: readonly TickerKind[] = ["meeting", "nowPlaying", "focus", "tasks", "progress"];
/** Built-in kinds that come after module highlights. */
export const TRAILING_TICKER_KINDS: readonly TickerKind[] = ["party", "pet"];
/** Every built-in kind, in rotation order. */
export const BUILT_IN_TICKER_KINDS: readonly TickerKind[] = [...LEADING_TICKER_KINDS, ...TRAILING_TICKER_KINDS];

/** The module a built-in kind belongs to, or a highlight kind's own module id. */
export function tickerKindModule(kind: TickerKind): ModuleID | undefined {
  switch (kind) {
    case "meeting":
    case "tasks":
      return "planner";
    case "nowPlaying":
      return "spotify";
    case "focus":
    case "progress":
      return undefined;
    case "party":
      return "party";
    case "pet":
      return "closet";
    default:
      return kind;
  }
}

/**
 * Every kind this build can show: the built-in ones, with the highlights of
 * each module in `catalog` that declares a `highlightTitle` in between, in
 * catalog order. A kind whose module the edition leaves out is dropped.
 */
export function allTickerKinds(catalog: ModuleCatalog): TickerKind[] {
  const highlights = catalog.descriptors.filter((d) => d.highlightTitle !== undefined).map((d) => d.id);
  return [...LEADING_TICKER_KINDS, ...highlights, ...TRAILING_TICKER_KINDS].filter((kind) => {
    const module = tickerKindModule(kind);
    return module === undefined || !catalog.isUnavailable(module);
  });
}
