/*
 * The Mac's `FoundingBadge`: a small gold seal (the pet palette's gold,
 * #F2C14E, so it matches the Founder's Pin) for people who signed in during
 * Tabbi's first 100 days. `seal` is the bare 8 px icon beside a name in the
 * panel; `label` adds the words for Settings' Account row. Both explain
 * themselves in a tooltip, about the user (`isMe`) or about someone else.
 */

import { tr } from "../../core/localization/tr";
import { Icon } from "./Icon";
import { Tooltip } from "./Tooltip";

export const FOUNDING_GOLD = "#F2C14E";

export function foundingExplanation(isMe: boolean): string {
  return isMe
    ? tr("Founding Member: you joined Tabbi in its first 100 days.")
    : tr("Founding Member: joined Tabbi in its first 100 days.");
}

export interface FoundingBadgeProps {
  readonly style?: "seal" | "label";
  readonly isMe: boolean;
  readonly tooltipOpen?: boolean;
}

export function FoundingBadge({ style = "seal", isMe, tooltipOpen }: FoundingBadgeProps) {
  const explanation = foundingExplanation(isMe);
  if (style === "seal") {
    return (
      <Tooltip text={explanation} open={tooltipOpen}>
        <span className="kit-founding kit-founding-seal" role="img" aria-label={explanation} tabIndex={0}>
          <Icon id="verified-filled" size={10} />
        </span>
      </Tooltip>
    );
  }
  return (
    <Tooltip text={explanation} open={tooltipOpen}>
      <span className="kit-founding kit-founding-label" role="img" aria-label={explanation} tabIndex={0}>
        <Icon id="verified-filled" size={12} />
        <span>{tr("Founding Member")}</span>
      </span>
    </Tooltip>
  );
}
