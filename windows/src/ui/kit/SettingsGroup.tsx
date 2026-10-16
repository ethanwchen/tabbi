/*
 * The Settings window's sections and rows in Tabbi's look. A `SettingsGroup`
 * is a titled card of rows separated by hairlines (the Mac's grouped Form
 * section), with an optional footer caption. A `SettingsRow` is one
 * setting: a label (body emphasis) with optional help text (caption,
 * secondary) and an info tooltip on the label, and its control at the
 * trailing edge. A `MoreOptions` group is collapsed by default, the
 * progressive disclosure Settings keeps rare settings under.
 */

import { useId, useState, type ReactNode } from "react";
import { tr } from "../../core/localization/tr";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { Tooltip } from "./Tooltip";

export interface SettingsGroupProps {
  readonly title?: string;
  readonly footer?: string;
  readonly children?: ReactNode;
  readonly className?: string;
}

export function SettingsGroup({ title, footer, children, className }: SettingsGroupProps) {
  const id = useId();
  return (
    <section className={["kit-settings-group", className].filter(Boolean).join(" ")} aria-labelledby={title ? id : undefined}>
      {title && (
        <h3 id={id} className="kit-settings-group-title">
          {title}
        </h3>
      )}
      <div className="kit-card kit-settings-group-card">{children}</div>
      {footer && <p className="kit-settings-group-footer">{footer}</p>}
    </section>
  );
}

export interface SettingsRowProps {
  readonly label: string;
  /** One line under the label saying what the setting does. */
  readonly help?: string;
  /** A tooltip on the label, for the longer explanation. */
  readonly tooltip?: string;
  readonly symbol?: string;
  readonly children?: ReactNode;
  /** Stacks the control under the label, for a wide control such as a hotkey field with a problem line. */
  readonly stacked?: boolean;
  readonly className?: string;
}

export function SettingsRow({ label, help, tooltip, symbol, children, stacked = false, className }: SettingsRowProps) {
  const id = useId();
  const text = (
    <div className="kit-settings-row-text" id={id}>
      <span className="kit-settings-row-label">{label}</span>
      {help && <span className="kit-settings-row-help">{help}</span>}
    </div>
  );
  return (
    <div className={["kit-settings-row", className].filter(Boolean).join(" ")} data-stacked={stacked || undefined} role="group" aria-labelledby={id}>
      {symbol && (
        <span className="kit-settings-row-symbol">
          <Icon id={symbol} size={14} />
        </span>
      )}
      {tooltip ? <Tooltip text={tooltip}>{text}</Tooltip> : text}
      {tooltip && (
        <Tooltip text={tooltip}>
          <span className="kit-settings-row-info" tabIndex={0} role="img" aria-label={tooltip}>
            <Icon id="info" size={12} />
          </span>
        </Tooltip>
      )}
      <div className="kit-settings-row-control">{children}</div>
    </div>
  );
}

export interface MoreOptionsProps {
  readonly children?: ReactNode;
  /** Starts open, for reviews. */
  readonly open?: boolean;
  readonly title?: string;
}

export function MoreOptions({ children, open: initial = false, title }: MoreOptionsProps) {
  const [open, setOpen] = useState(initial);
  const transition = useTransition("snappy", ["transform"]);
  const id = useId();
  const heading = title ?? tr("More options");
  return (
    <section className="kit-settings-group kit-more-options" data-open={open}>
      <button type="button" className="kit-more-options-toggle" aria-expanded={open} aria-controls={id} onClick={() => setOpen((o) => !o)}>
        <Icon id="chevron-forward" size={12} className="kit-more-options-chevron" style={{ transition }} />
        <span>{heading}</span>
      </button>
      {open && (
        <div id={id} className="kit-card kit-settings-group-card">
          {children}
        </div>
      )}
    </section>
  );
}
