/*
 * Port of NotchTakeover: a flow that fills the whole open island for a
 * while (first-run setup), with its own header wings and a body in the
 * panel canvas. The tab bar and the tab keys pause until it ends, so the
 * island itself is the setup surface and no extra window is needed.
 * Onboarding sets `AppServices.takeover` while it runs and clears it at the
 * end; the shell shows whatever it holds.
 */

import type { ComponentType } from "react";

export interface NotchTakeover {
  /** Where the tab bar usually sits. */
  readonly Leading: ComponentType;
  /** Where the tab's title, the gear and the paw usually sit. */
  readonly Trailing: ComponentType;
  /** The panel canvas below the header. */
  readonly Body: ComponentType;
}
