/*
 * The modules the phase 1 tab bar shows, with the ids, titles, symbols and
 * accents of their Mac descriptors (Sources/Tabbi/Modules/<Module>/), so kits
 * and the tab order match. Each module gets its own folder under
 * src/modules/ with its real descriptor from phase 2 on, and this table goes.
 */

import essentials from "../../../Sources/TabbiKitCore/Kits/Bundled/essentials.json";

export interface ModuleStub {
  readonly id: string;
  readonly title: string;
  readonly symbol: string;
  /* sRGB channels 0 to 1, as ModuleAccent stores them. */
  readonly accent: readonly [number, number, number];
  /* Opens from a button at the far right of the header instead of a tab (the Closet's paw, key P). */
  readonly headerShortcut?: string;
}

/* ModuleAccent.claude, shared by Ask AI and AI Usage. */
const CLAUDE: readonly [number, number, number] = [0.85, 0.47, 0.34];

export const MODULES: readonly ModuleStub[] = [
  { id: "study", title: "Timer", symbol: "timer", accent: [1.0, 0.62, 0.26] },
  { id: "planner", title: "Today", symbol: "checklist", accent: [0.66, 0.55, 1.0] },
  { id: "spotify", title: "Now Playing", symbol: "music.note", accent: [0.12, 0.84, 0.38] },
  { id: "claudeAsk", title: "Ask AI", symbol: "sparkles", accent: CLAUDE },
  { id: "closet", title: "Closet", symbol: "pawprint.fill", accent: [0.98, 0.8, 0.3], headerShortcut: "p" },
];

export function accentColor(module: ModuleStub, opacity = 1): string {
  const [r, g, b] = module.accent.map((v) => Math.round(v * 255));
  return `rgb(${r} ${g} ${b} / ${opacity})`;
}

/* The default kit's modules, in its order, split into tabs and header shortcuts. */
export function kitLayout(moduleIds: readonly string[] = essentials.modules): {
  tabs: ModuleStub[];
  shortcuts: ModuleStub[];
} {
  const known = moduleIds.flatMap((id) => MODULES.filter((m) => m.id === id));
  return {
    tabs: known.filter((m) => !m.headerShortcut),
    shortcuts: known.filter((m) => m.headerShortcut),
  };
}
