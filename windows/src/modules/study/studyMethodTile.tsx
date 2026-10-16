/*
 * Port of StudyMethodTile: one method in the picker, name and rhythm, with
 * its (i) when `info` is set. Onboarding's method step shows the info
 * beside the tiles instead, and previews the hovered method.
 */

import { tr } from "../../core/localization/tr";
import type { StudyMethod, StudyMethodKind } from "../../core/studyMethods/studyMethod";
import { methodInfo, nameIsRhythm } from "../../core/studyMethods/studyMethodInfo";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { StudyInfoButton } from "./studyMethodInfoView";

export interface StudyMethodTileProps {
  readonly method: StudyMethod;
  readonly isCurrent: boolean;
  /** Opens the method's info view; undefined hides the (i). */
  readonly info?: (kind: StudyMethodKind) => void;
  readonly onPick: () => void;
  /** Whether the tile shows the rhythm after the name; onboarding's narrower tiles leave it to the summary beside them. */
  readonly showsRhythm?: boolean;
  /** Reports hover changes, so onboarding can preview the hovered method. */
  readonly onHover?: (hovering: boolean) => void;
}

export function StudyMethodTile({ method, isCurrent, info, onPick, showsRhythm = true, onHover }: StudyMethodTileProps) {
  const text = methodInfo(method);
  return (
    <div className="study-method-tile-row">
      <Tooltip text={isCurrent ? tr("%@ is in use", text.displayName) : tr("Switch to %@: %@", text.displayName, text.displayTagline)}>
        <button
          type="button"
          className="study-method-tile kit-body-emphasis"
          data-current={isCurrent}
          aria-pressed={isCurrent}
          onClick={onPick}
          onPointerEnter={() => onHover?.(true)}
          onPointerLeave={() => onHover?.(false)}
        >
          <MarqueeText text={text.displayName} className="study-method-tile-name" />
          {showsRhythm && !nameIsRhythm(method) && <span className="study-method-tile-rhythm study-rhythm">{method.rhythmLabel}</span>}
        </button>
      </Tooltip>
      {info !== undefined && <StudyInfoButton method={method.kind} onClick={() => info(method.kind)} />}
    </div>
  );
}
