/*
 * A whole-panel state, the Mac's StatusMessage: the module's glyph in a soft
 * accent badge, a title, and one line of guidance.
 */

import { Icon } from "./icons";
import { accentColor, type ModuleStub } from "./modules";

export function StatusMessage({ module, title, message }: { module: ModuleStub; title: string; message: string }) {
  return (
    <div className="status" role="status">
      <div className="badge" style={{ color: accentColor(module), background: accentColor(module, 0.16) }}>
        <Icon symbol={module.symbol} size={20} />
      </div>
      <div className="status-title">{title}</div>
      <div className="status-message">{message}</div>
    </div>
  );
}
