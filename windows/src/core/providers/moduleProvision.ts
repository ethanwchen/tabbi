import type { PetPresence } from "../pets/petPresence";
import type { ProgressItem } from "./progressItem";
import type { ProvidedEvent } from "./providedEvent";
import type { ProvidedFocus } from "./providedFocus";
import type { ProvidedParty } from "./providedParty";
import type { ProvidedTask } from "./providedTask";
import type { StudyDayTally } from "./studyDayTally";
import type { TickerHighlight } from "./tickerHighlight";

/**
 * Port of ModuleProvision: what one module offers the rest of the app right
 * now. Each field is one provider role; a module fills only the ones it has:
 * - `tasks`: TaskSource, things to do today.
 * - `events`: EventSource, calendar events.
 * - `progress`: ProgressSource, today's study or practice goals.
 * - `focus`: FocusState, the focus or break clock the module runs, in the
 *   engine-neutral `ProvidedFocus` shape.
 * - `study`: StudySource, today's study minutes, sessions and points.
 * - `pet`: PetSource, the study pet the closed island shows.
 * - `party`: PartySource, the study party the user is in.
 * - `highlights`: HighlightSource, short lines for the closed-island ticker.
 * - `isPlaying`: MediaSource, music is playing.
 * - `badge`: how many things wait in this module (Party: friend requests),
 *   shown as a count on its tab; 0 shows none.
 *
 * Modules publish a new value whenever their data changes, and
 * `ProviderSnapshot` merges the enabled modules' values, so consumers such
 * as the ticker never depend on a specific module.
 */
export interface ModuleProvision {
  readonly tasks: readonly ProvidedTask[];
  readonly events: readonly ProvidedEvent[];
  readonly progress: readonly ProgressItem[];
  readonly focus: ProvidedFocus | undefined;
  readonly study: StudyDayTally | undefined;
  readonly pet: PetPresence | undefined;
  readonly party: ProvidedParty | undefined;
  readonly highlights: readonly TickerHighlight[];
  readonly isPlaying: boolean;
  readonly badge: number;
}

/** The Mac initializer's defaults: every role empty. */
export const EMPTY_PROVISION: ModuleProvision = {
  tasks: [],
  events: [],
  progress: [],
  focus: undefined,
  study: undefined,
  pet: undefined,
  party: undefined,
  highlights: [],
  isPlaying: false,
  badge: 0,
};

/** A provision with only the roles in `roles` filled. */
export function moduleProvision(roles: Partial<ModuleProvision> = {}): ModuleProvision {
  return { ...EMPTY_PROVISION, ...roles };
}
