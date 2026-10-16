/*
 * How a panel asks the island to show another tab, the Mac's
 * `notch.selected = id` (Today's shared rows open the module that shares
 * them; the shared focus card opens its owner's tab), with the one-click
 * action the shared item carries, if any (Anki's "Study <deck>"), which the
 * island hands to that module through the registry first. The island
 * follows the requests; a module only asks, through `requestTab`, and never
 * reaches the shell. A request for a tab that isn't on is ignored.
 */

import type { ModuleID } from "../core/modules/moduleId";
import type { ProvidedAction } from "../core/providers/progressItem";
import type { ModuleContext } from "./context";
import { serviceKey, type SharedServices } from "./sharedServices";
import { Emitter } from "./store";

export interface TabRequest {
  readonly module: ModuleID;
  /** What to run in that module before showing it. */
  readonly action?: ProvidedAction;
}

const TAB_REQUESTS = serviceKey<Emitter<TabRequest>>("app.tabRequests");

/** The one stream of tab requests in this window. */
export function tabRequests(shared: SharedServices): Emitter<TabRequest> {
  return shared.resolve(TAB_REQUESTS, () => new Emitter<TabRequest>());
}

/** Asks the island to show `module`'s tab, running `action` in it first when given. */
export function requestTab(context: ModuleContext, module: ModuleID, action?: ProvidedAction): void {
  tabRequests(context.shared).emit(action === undefined ? { module } : { module, action });
}
