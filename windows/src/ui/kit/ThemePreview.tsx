/*
 * The Mac's `ThemePreview`: a miniature open panel drawn in one theme (the
 * black body with the theme's glow spread over the whole body so it reads
 * at this size, a tab bar with a few module accents, the first selected, and
 * a card with a timer and a progress bar). It reads the theme it is given,
 * never the active one, so a picker can show every theme side by side.
 */

import type { CSSProperties } from "react";
import { themeAccent, type AppTheme } from "../../core/themes/appTheme";
import type { ModuleAccent } from "../../core/themes/themeColor";
import { cssColor } from "./tokens";

export interface ThemePreviewProps {
  readonly theme: AppTheme;
  /** The module accents to sample, in tab order; the first is the selected tab. Only four are drawn. */
  readonly accents: readonly ModuleAccent[];
  readonly width?: number;
  readonly height?: number;
  readonly className?: string;
}

const FALLBACK_ACCENT: ModuleAccent = { red: 0.4, green: 0.62, blue: 1.0 };

export function ThemePreview({ theme, accents, width = 112, height = 60, className }: ThemePreviewProps) {
  const samples = (accents.length === 0 ? [FALLBACK_ACCENT] : accents).slice(0, 4);
  const palette = theme.palette;
  const lead = cssColor(themeAccent(theme, samples[0] ?? FALLBACK_ACCENT));
  const style: CSSProperties = {
    width,
    height,
    background: palette.glow
      ? `linear-gradient(to bottom, transparent, ${cssColor(palette.glow)}), ${cssColor(palette.background)}`
      : cssColor(palette.background),
  };
  return (
    <div className={["kit-theme-preview", className].filter(Boolean).join(" ")} style={style} data-theme-preview={theme.id} aria-hidden="true">
      <div className="kit-theme-preview-tabs">
        {samples.map((accent, index) => (
          <span
            key={index}
            className="kit-theme-preview-tab"
            data-selected={index === 0}
            style={{
              background: index === 0 ? cssColor(palette.surfaceHover) : undefined,
              boxShadow: index === 0 && theme.controls === "glass" ? "inset 0 0 0 0.5px rgb(255 255 255 / 0.24)" : undefined,
            }}
          >
            <span className="kit-theme-preview-dot" style={{ background: cssColor(themeAccent(theme, accent)) }} />
          </span>
        ))}
      </div>
      <div
        className="kit-theme-preview-card"
        style={{ background: cssColor(palette.surface), boxShadow: `inset 0 0 0 0.5px ${cssColor(palette.stroke)}` }}
      >
        <span className="kit-theme-preview-time" style={{ color: cssColor(palette.primaryText) }}>
          25:00
        </span>
        <span className="kit-theme-preview-bar" style={{ background: cssColor(palette.surfaceHover) }}>
          <span style={{ width: "62%", background: lead }} />
        </span>
        <span className="kit-theme-preview-line" style={{ background: cssColor(palette.tertiaryText) }} />
      </div>
    </div>
  );
}
