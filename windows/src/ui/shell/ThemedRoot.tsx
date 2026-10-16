/*
 * Applies the user's theme and motion pace from the settings, live: a theme
 * picked in the Settings window reaches the island through the settings
 * store, and this redraws every token on the document root and in the kit's
 * environment. Reduce Motion follows Windows' setting unless a run forces it.
 */

import { useLayoutEffect, type ReactNode } from "react";
import type { SettingsStore } from "../../app/settingsStore";
import { useStore } from "../../app/useStore";
import { KitProvider, useKit } from "../kit/context";
import { applyKitTheme } from "../kit/tokens";

export interface ThemedRootProps {
  readonly settings: SettingsStore;
  /** A still render (snapshots): no motion, loaders at their first frame. */
  readonly still?: boolean;
  /** Forces Reduce Motion on; undefined follows the system. */
  readonly reduceMotion?: boolean;
  readonly children: ReactNode;
}

export function ThemedRoot({ settings, still = false, reduceMotion, children }: ThemedRootProps) {
  const themeID = useStore(settings.settings, (value) => value.themeID);
  const pace = useStore(settings.settings, (value) => value.motionPace);
  useLayoutEffect(() => {
    const root = document.documentElement;
    applyKitTheme(root, themeID, pace);
    root.classList.add("kit-root");
  }, [themeID, pace]);
  return (
    <KitProvider themeId={themeID} pace={pace} still={still} reduceMotion={reduceMotion}>
      <MotionFlag />
      {children}
    </KitProvider>
  );
}

/** Marks the root while Reduce Motion is on, so the shell's CSS turns movement into fades. */
function MotionFlag() {
  const { reduceMotion } = useKit();
  useLayoutEffect(() => {
    document.documentElement.dataset.reduceMotion = String(reduceMotion);
  }, [reduceMotion]);
  return null;
}
