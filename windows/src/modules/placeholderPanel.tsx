/*
 * The stand-in panel every module shows until its own panel is ported: the
 * module's glyph in its accent badge, its title, and one plain line, drawn
 * with the kit's StatusMessage so it reads like any other empty state.
 * Each module's agent replaces its `Panel` and drops this import.
 */

import type { ComponentType } from "react";
import { tr } from "../core/localization/tr";
import type { ModuleDescriptor } from "../core/modules/moduleDescriptor";
import { StatusMessage } from "../ui/kit/StatusMessage";

export function placeholderPanel(descriptor: ModuleDescriptor): ComponentType {
  function PlaceholderPanel() {
    return (
      <div className="panel-placeholder">
        <StatusMessage symbol={descriptor.symbol} title={descriptor.title} message={tr("This tab arrives in a later Windows build.")} />
      </div>
    );
  }
  PlaceholderPanel.displayName = `${descriptor.id}Panel`;
  return PlaceholderPanel;
}
