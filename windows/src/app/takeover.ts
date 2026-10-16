/*
 * Port of NotchTakeover: a flow that fills the whole open island for a
 * while (first-run setup, the weekly recap card), with its own header wings
 * and a body in the panel canvas. The tab bar and the tab keys pause until
 * it ends, so the island itself is the setup surface and no extra window is
 * needed. Whoever owns the moment sets the slot (`takeoverSlot`) while it
 * runs and clears it at the end, the way the Mac's AppTakeover hands the
 * slot to onboarding, a Party invite or the recap; the shell shows whatever
 * it holds.
 *
 * `ClosedOverlay` is the closed island's counterpart: something drawn over
 * the canvas while the island is a pill or hidden (the pet coach trotting
 * out from under the island), with the region the window must take so it
 * draws and takes clicks there.
 */

import type { ComponentType } from "react";
import type { HitRect } from "../ui/shell/geometry";
import { serviceKey, type SharedServices } from "./sharedServices";
import { Observable } from "./store";

export interface NotchTakeover {
  /** Where the tab bar usually sits. */
  readonly Leading: ComponentType;
  /** Where the tab's title, the gear and the paw usually sit. */
  readonly Trailing: ComponentType;
  /** The panel canvas below the header. */
  readonly Body: ComponentType;
}

const TAKEOVER = serviceKey<Observable<NotchTakeover | undefined>>("app.takeover");

/** The one takeover slot of this window: what fills the open island instead of the tabs, or undefined for the tabs. */
export function takeoverSlot(shared: SharedServices): Observable<NotchTakeover | undefined> {
  return shared.resolve(TAKEOVER, () => new Observable<NotchTakeover | undefined>(undefined));
}

/** What a closed overlay is drawn against: the pill's region (its wings included) in the canvas. */
export interface ClosedOverlayFrame {
  readonly pill: HitRect;
  readonly canvas: { readonly width: number; readonly height: number };
}

export interface ClosedOverlay {
  /** Drawn in the island's canvas beside the pill, positioned by its own styles from the frame. */
  readonly Body: ComponentType<ClosedOverlayFrame>;
  /** The part of the canvas the overlay needs, in logical pixels; the window region grows to include it. */
  readonly rect: (frame: ClosedOverlayFrame) => HitRect;
}

const CLOSED_OVERLAY = serviceKey<Observable<ClosedOverlay | undefined>>("app.closedOverlay");

/** The one closed-island overlay slot of this window. */
export function closedOverlaySlot(shared: SharedServices): Observable<ClosedOverlay | undefined> {
  return shared.resolve(CLOSED_OVERLAY, () => new Observable<ClosedOverlay | undefined>(undefined));
}
