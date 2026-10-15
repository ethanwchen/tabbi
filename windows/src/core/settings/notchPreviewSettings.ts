import type { TickerKind } from "../ticker/tickerKind";

/** Port of TickerInterval: seconds each closed-panel preview item stays before the next. */
export type TickerInterval = 5 | 8 | 12;

export const TICKER_INTERVALS: readonly TickerInterval[] = [5, 8, 12];

export function isTickerInterval(value: unknown): value is TickerInterval {
  return typeof value === "number" && (TICKER_INTERVALS as readonly number[]).includes(value);
}

/** Picker label, e.g. "8 seconds", the wide unit style the Mac's Duration formatting uses, in `locale`. */
export function tickerIntervalTitle(interval: TickerInterval, locale = "en"): string {
  return new Intl.NumberFormat(locale, { style: "unit", unit: "second", unitDisplay: "long" }).format(interval);
}

/**
 * Port of NotchPreviewSettings: preferences for the live preview beside the
 * closed panel. Stores the kinds the user turned off, so a kind added later
 * starts enabled instead of silently hidden.
 */
export interface NotchPreviewSettings {
  /** Master switch; when off the closed panel is always plain. */
  readonly isEnabled: boolean;
  readonly disabledKinds: ReadonlySet<TickerKind>;
  readonly interval: TickerInterval;
}

export const DEFAULT_NOTCH_PREVIEW: NotchPreviewSettings = {
  isEnabled: true,
  disabledKinds: new Set(),
  interval: 8,
};

/** Whether the ticker may show `kind`: false for every kind while the master switch is off. */
export function previewShows(settings: NotchPreviewSettings, kind: TickerKind): boolean {
  return settings.isEnabled && !settings.disabledKinds.has(kind);
}

/** Whether `kind`'s own toggle is on, whatever the master switch says. */
export function previewKindEnabled(settings: NotchPreviewSettings, kind: TickerKind): boolean {
  return !settings.disabledKinds.has(kind);
}

/** The settings with `kind` turned on or off. */
export function settingPreviewKind(
  settings: NotchPreviewSettings,
  kind: TickerKind,
  enabled: boolean,
): NotchPreviewSettings {
  const disabledKinds = new Set(settings.disabledKinds);
  if (enabled) disabledKinds.delete(kind);
  else disabledKinds.add(kind);
  return { ...settings, disabledKinds };
}

export function samePreviewSettings(a: NotchPreviewSettings, b: NotchPreviewSettings): boolean {
  return (
    a.isEnabled === b.isEnabled &&
    a.interval === b.interval &&
    a.disabledKinds.size === b.disabledKinds.size &&
    [...a.disabledKinds].every((kind) => b.disabledKinds.has(kind))
  );
}
