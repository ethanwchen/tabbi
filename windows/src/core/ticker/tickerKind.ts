import { tr } from "../localization/tr";
import type { ModuleCatalog } from "../modules/moduleCatalog";
import { MODULE_IDS, type ModuleID } from "../modules/moduleId";

/**
 * Port of TickerKind: a kind of live activity the closed island can preview,
 * and the unit the user turns previews on and off by.
 *
 * Open rather than a closed union: besides the built-in kinds with their own
 * look (meetings, music, the focus clock, the pet), every module that
 * publishes `TickerHighlight`s gets a kind of its own whose raw value is the
 * module id. So a new module's previews need no ticker code, and a kit's
 * `ticker` list names them by module id.
 */
export type TickerKind = string;

export const TICKER_KINDS = {
  meeting: "meeting",
  nowPlaying: "nowPlaying",
  focus: "focus",
  tasks: "tasks",
  progress: "progress",
  party: "party",
  /** The study pet, last so live data always comes first. */
  pet: "pet",
} as const satisfies Record<string, TickerKind>;

/** Built-in kinds that come before module highlights in the rotation. */
export const LEADING_TICKER_KINDS: readonly TickerKind[] = [
  TICKER_KINDS.meeting,
  TICKER_KINDS.nowPlaying,
  TICKER_KINDS.focus,
  TICKER_KINDS.tasks,
  TICKER_KINDS.progress,
];
/** Built-in kinds that come after module highlights. */
export const TRAILING_TICKER_KINDS: readonly TickerKind[] = [TICKER_KINDS.party, TICKER_KINDS.pet];
/** Every built-in kind, in rotation order. */
export const BUILT_IN_TICKER_KINDS: readonly TickerKind[] = [...LEADING_TICKER_KINDS, ...TRAILING_TICKER_KINDS];

/** The kind for `module`'s highlights. */
export function highlightsKind(module: ModuleID): TickerKind {
  return module;
}

export function isBuiltInTickerKind(kind: TickerKind): boolean {
  return BUILT_IN_TICKER_KINDS.includes(kind);
}

/**
 * The module this preview needs turned on, and whose panel a click opens.
 * Undefined for the focus clock and progress, which any module can provide;
 * only enabled modules publish them, and `tickerItemModule` opens the one
 * they came from.
 */
export function tickerKindModule(kind: TickerKind): ModuleID | undefined {
  switch (kind) {
    case TICKER_KINDS.meeting:
    case TICKER_KINDS.tasks:
      return MODULE_IDS.planner;
    case TICKER_KINDS.focus:
    case TICKER_KINDS.progress:
      return undefined;
    case TICKER_KINDS.nowPlaying:
      return MODULE_IDS.spotify;
    case TICKER_KINDS.pet:
      return MODULE_IDS.closet;
    case TICKER_KINDS.party:
      return MODULE_IDS.party;
    default:
      return kind;
  }
}

/**
 * Every kind this build can show: the built-in ones, with the highlights of
 * each module in `catalog` that declares a `highlightTitle` in between, in
 * catalog order. A built-in kind whose module the edition leaves out (Party
 * in a store edition) is dropped, so Settings offers no preview that can
 * never show.
 */
export function allTickerKinds(catalog: ModuleCatalog): TickerKind[] {
  const highlightKinds = catalog.descriptors.filter((d) => d.highlightTitle !== undefined).map((d) => highlightsKind(d.id));
  return [...LEADING_TICKER_KINDS, ...highlightKinds, ...TRAILING_TICKER_KINDS].filter((kind) => {
    const module = tickerKindModule(kind);
    return module === undefined || !catalog.isUnavailable(module);
  });
}

/** Label for the per-item toggle in Settings; a module's highlights use its descriptor's `highlightTitle`. */
export function tickerKindTitle(kind: TickerKind, catalog: ModuleCatalog): string {
  switch (kind) {
    case TICKER_KINDS.meeting:
      return tr("Next meeting");
    case TICKER_KINDS.nowPlaying:
      return tr("Now Playing");
    case TICKER_KINDS.focus:
      return tr("Focus timer");
    case TICKER_KINDS.tasks:
      return tr("Tasks left today");
    case TICKER_KINDS.progress:
      return tr("Goals left today");
    case TICKER_KINDS.pet:
      return tr("Pet");
    case TICKER_KINDS.party:
      return tr("Party pets");
    default: {
      const descriptor = catalog.descriptor(kind);
      return descriptor.highlightTitle ?? descriptor.title;
    }
  }
}
