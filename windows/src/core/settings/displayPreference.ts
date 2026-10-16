/**
 * Port of DisplayPreference: which screen the panel lives on. On Windows,
 * "builtIn" is the laptop's own panel when there is one, and "main" the
 * primary display.
 */
export type DisplayPreference =
  | { readonly kind: "builtIn" }
  | { readonly kind: "main" }
  /** A specific display by its id. */
  | { readonly kind: "specific"; readonly id: number };

/** A screen as `resolveDisplay` sees it, decoupled from the host for testing. */
export interface DisplayScreen {
  readonly id: number;
  readonly isBuiltIn: boolean;
  readonly isMain: boolean;
}

export const DEFAULT_DISPLAY_PREFERENCE: DisplayPreference = { kind: "builtIn" };

/**
 * Picks the screen to use, falling back built-in, then main, then the first,
 * so the panel stays visible when the preferred display is unplugged.
 */
export function resolveDisplay(preference: DisplayPreference, screens: readonly DisplayScreen[]): DisplayScreen | undefined {
  const builtIn = screens.find((screen) => screen.isBuiltIn);
  const main = screens.find((screen) => screen.isMain);
  switch (preference.kind) {
    case "builtIn":
      return builtIn ?? main ?? screens[0];
    case "main":
      return main ?? builtIn ?? screens[0];
    case "specific":
      return screens.find((screen) => screen.id === preference.id) ?? builtIn ?? main ?? screens[0];
  }
}

/** The stable stored form: "builtIn", "main", or "screen:<id>". */
export function displayPreferenceStorageValue(preference: DisplayPreference): string {
  switch (preference.kind) {
    case "builtIn":
      return "builtIn";
    case "main":
      return "main";
    case "specific":
      return `screen:${preference.id}`;
  }
}

/** Reads a stored preference, or undefined when it isn't one. */
export function displayPreferenceFromStorage(value: string): DisplayPreference | undefined {
  if (value === "builtIn") return { kind: "builtIn" };
  if (value === "main") return { kind: "main" };
  const match = /^screen:(\d+)$/.exec(value);
  if (!match) return undefined;
  const id = Number(match[1]);
  return id <= 0xffffffff ? { kind: "specific", id } : undefined;
}
