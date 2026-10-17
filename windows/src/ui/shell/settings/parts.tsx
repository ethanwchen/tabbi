/*
 * Small pieces the Settings sections share: the last row of a section that
 * puts it back to its defaults (ResetToDefaultsRow), a status line under a
 * group's buttons (SettingsMessage), a bordered text button (SettingsButton)
 * and a module's icon tile in its accent (ModuleIcon).
 */

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { tr } from "../../../core/localization/tr";
import type { ModuleDescriptor } from "../../../core/modules/moduleDescriptor";
import { useTheme, useTransition } from "../../kit/context";
import { Icon } from "../../kit/Icon";
import { useTactile } from "../../kit/tactile";
import { identityAccentCss } from "../../kit/tokens";
import { Tooltip } from "../../kit/Tooltip";

export interface SettingsButtonProps {
  readonly title: string;
  readonly help: string;
  readonly onClick: () => void;
  readonly disabled?: boolean;
  /** The one primary action of a sheet or row. */
  readonly primary?: boolean;
  /** A destructive action: quiet until hovered, then red. */
  readonly destructive?: boolean;
  readonly symbol?: string;
  readonly className?: string;
}

/** The Mac's bordered button: 24 px, body-emphasis text, a hairline that brightens on hover. */
export function SettingsButton({ title, help, onClick, disabled = false, primary = false, destructive = false, symbol, className }: SettingsButtonProps) {
  const tactile = useTactile({ disabled });
  const transition = useTransition("snappy", ["background-color", "color", "box-shadow"]);
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className={["settings-button", className].filter(Boolean).join(" ")}
        data-primary={primary}
        data-destructive={destructive}
        disabled={disabled}
        {...tactile.data}
        {...tactile.handlers}
        style={{ ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", ") }}
        onClick={onClick}
      >
        {symbol !== undefined && <Icon id={symbol} size={12} />}
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}

export interface SettingsMessageProps {
  readonly text: string;
  readonly warning?: boolean;
  /** Something to do about it, at the trailing end (Undo). */
  readonly action?: ReactNode;
}

/** A line under a group's buttons: a check or a warning sign, the words, and an optional action. */
export function SettingsMessage({ text, warning = false, action }: SettingsMessageProps) {
  return (
    <div className="settings-message" data-warning={warning} role="status">
      <Icon id={warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"} size={12} className="settings-message-symbol" />
      <span className="settings-message-text">{text}</span>
      {action !== undefined && action !== null && <span className="settings-message-action">{action}</span>}
    </div>
  );
}

export interface ResetToDefaultsRowProps {
  readonly isAtDefaults: boolean;
  readonly help: string;
  readonly title?: string;
  readonly reset: () => void;
  /** One quiet action of the section's own at the leading edge. */
  readonly leading?: ReactNode;
}

/**
 * The last row of a Settings section: puts that section back to its
 * defaults, says so for a moment afterwards, and stays disabled while there
 * is nothing to reset.
 */
export function ResetToDefaultsRow({ isAtDefaults, help, title, reset, leading }: ResetToDefaultsRowProps) {
  const [didReset, setDidReset] = useState(false);
  useEffect(() => {
    if (!didReset) return;
    const timer = window.setTimeout(() => setDidReset(false), 3000);
    return () => window.clearTimeout(timer);
  }, [didReset]);
  return (
    <div className="settings-reset-row">
      {leading}
      <span className="settings-reset-spacer" />
      {didReset && (
        <span className="settings-reset-done kit-caption kit-secondary">
          <Icon id="checkmark.circle.fill" size={12} />
          <span>{tr("Back to defaults")}</span>
        </span>
      )}
      <SettingsButton
        title={title ?? tr("Reset to Defaults")}
        help={isAtDefaults ? tr("Everything here is already at its default") : help}
        disabled={isAtDefaults}
        onClick={() => {
          reset();
          setDidReset(true);
        }}
      />
    </div>
  );
}

/** A module's icon tile in the Tabs pane, in its own color even in a theme with a key color. */
export function ModuleIcon({ module, size = 24 }: { module: ModuleDescriptor; size?: number }) {
  const theme = useTheme();
  const accent = identityAccentCss(theme, module.accent);
  const style: CSSProperties = {
    width: size,
    height: size,
    borderRadius: Math.round(size / 4),
    background: `linear-gradient(to bottom, color-mix(in srgb, ${accent} 88%, white), ${accent})`,
  };
  return (
    <span className="settings-module-icon" style={style} aria-hidden="true">
      <Icon id={module.symbol} size={Math.round(size / 2)} />
    </span>
  );
}

/** A row of a kit's tabs as small tinted symbols. */
export function TabIcons({ modules, size = 18 }: { modules: readonly ModuleDescriptor[]; size?: number }) {
  const theme = useTheme();
  return (
    <span className="settings-tab-icons">
      {modules.map((module) => {
        const accent = identityAccentCss(theme, module.accent);
        return (
          <Tooltip key={module.id} text={module.title}>
            <span className="settings-tab-icon" style={{ width: size, height: size, color: accent, background: `color-mix(in srgb, ${accent} 16%, transparent)` }}>
              <Icon id={module.symbol} size={Math.round(size / 2)} />
            </span>
          </Tooltip>
        );
      })}
    </span>
  );
}

/** Joins items the way the Mac's ListFormatter does for the user's language ("a, b and c"). */
export function listOf(items: readonly string[], locale: string): string {
  try {
    return new Intl.ListFormat(locale, { style: "long", type: "conjunction" }).format(items);
  } catch {
    return items.join(", ");
  }
}
