/*
 * The Mac's `ModulePlaceholder`: temporary content for a module that has
 * not been built yet, its symbol at 26 px in the module accent over one
 * line of detail, centered in the panel.
 */

import { Icon } from "./Icon";

export interface ModulePlaceholderProps {
  /** The module's symbol (an icon id or SF Symbol name). */
  readonly symbol: string;
  /** The module accent, as CSS; `var(--accent)` by default. */
  readonly accent?: string;
  readonly detail: string;
}

export function ModulePlaceholder({ symbol, accent = "var(--accent)", detail }: ModulePlaceholderProps) {
  return (
    <div className="kit-module-placeholder">
      <Icon id={symbol} size={26} style={{ color: accent }} />
      <div className="kit-module-placeholder-detail">{detail}</div>
    </div>
  );
}
