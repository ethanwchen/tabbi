/*
 * The one CelebrationCenter of a window, the Mac's `context.celebrations`:
 * where real events (a purchase, a level up, a limited item earned) ask for
 * a burst over the open panel. Modules resolve it through their context so
 * every module shares the pacer's limits; the island mounts the stage that
 * plays what it holds. A snapshot run plays nothing.
 */

import { CelebrationCenter } from "../ui/kit/celebrationCenter";
import type { ModuleContext } from "./context";
import { serviceKey, type SharedServices } from "./sharedServices";

const CELEBRATIONS = serviceKey<CelebrationCenter>("app.celebrations");

/** The window's celebration center, made on first use. */
export function celebrationsIn(shared: SharedServices, options: { readonly isSnapshot: boolean; readonly now: () => number; readonly timeZone: () => string }): CelebrationCenter {
  return shared.resolve(
    CELEBRATIONS,
    () => new CelebrationCenter({ isEnabled: !options.isSnapshot, now: options.now, timeZone: options.timeZone() }),
  );
}

/** The celebration center a module celebrates through. */
export function celebrations(context: ModuleContext): CelebrationCenter {
  return celebrationsIn(context.shared, { isSnapshot: context.isSnapshot, now: () => context.now(), timeZone: () => context.timeZone() });
}
