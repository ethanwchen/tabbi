/*
 * Port of ClosedNotchPreview: which closed-island previews can show right
 * now. The ticker writes it; a module that only refreshes while someone can
 * see the result follows it (Today keeps reloading the calendar while the
 * meeting preview can show), so nothing polls for a preview nobody sees.
 */

import type { TickerKind } from "../core/ticker/tickerKind";
import { Observable, type Readable } from "./store";

function sameKinds(a: ReadonlySet<TickerKind>, b: ReadonlySet<TickerKind>): boolean {
  return a.size === b.size && [...a].every((kind) => b.has(kind));
}

export class ClosedPreview {
  private readonly kinds = new Observable<ReadonlySet<TickerKind>>(new Set(), sameKinds);

  /** The kinds the user allows while the island is closed; empty while it is open or previews are off. */
  get watchedKinds(): Readable<ReadonlySet<TickerKind>> {
    return this.kinds;
  }

  /** Called by the ticker only. */
  setWatched(kinds: ReadonlySet<TickerKind>): void {
    this.kinds.set(kinds);
  }
}
