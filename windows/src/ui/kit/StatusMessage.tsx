/*
 * The Mac's `StatusMessage`: a panel's empty, loading, unavailable or error
 * state. A glyph (or a spinner while something is on its way) in a soft
 * accent badge (32 px), a title, one line of guidance and at most a row of
 * actions, centered in the room it gets, so every tab's states read alike.
 * With a `pet`, the user's pet sits in the badge's place with the glyph
 * tucked at its paws, so "No music app is open" reads like Tabbi.
 */

import type { CSSProperties, ReactNode } from "react";
import type { PetProfile } from "../../core/pets/petProfile";
import { Icon } from "./Icon";
import { Spinner } from "./Loading";
import { PetView } from "./PetView";

export const STATUS_BADGE_SIZE = 32;

export interface StatusMessageProps {
  /** An icon id or SF Symbol name; null shows a spinner instead. */
  readonly symbol: string | null;
  /** The accent, as CSS; `var(--accent)` by default. */
  readonly tint?: string;
  readonly title: string;
  readonly message: string;
  readonly actions?: ReactNode;
  /** The user's pet, shown in place of the badge in empty and error states. */
  readonly pet?: PetProfile;
  readonly className?: string;
}

export function StatusMessage({ symbol, tint = "var(--accent)", title, message, actions, pet, className }: StatusMessageProps) {
  return (
    <div className={["kit-status", className].filter(Boolean).join(" ")} role="status" style={{ "--status-tint": tint } as CSSProperties}>
      {symbol !== null && pet ? (
        <div className="kit-status-pet">
          <PetView profile={pet} pixelSize={1} />
          <span className="kit-status-pet-badge">
            <Icon id={symbol} size={7} />
          </span>
        </div>
      ) : (
        <div className="kit-status-badge">{symbol === null ? <Spinner tint={tint} size={14} lineWidth={2} /> : <Icon id={symbol} size={15} />}</div>
      )}
      <div className="kit-status-text">
        <div className="kit-status-title">{title}</div>
        <div className="kit-status-message">{message}</div>
      </div>
      {actions !== undefined && actions !== null && <div className="kit-status-actions">{actions}</div>}
    </div>
  );
}
