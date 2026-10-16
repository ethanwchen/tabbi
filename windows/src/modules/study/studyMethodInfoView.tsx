/*
 * Port of StudyMethodInfoView: a method's info view, drawn inside the
 * island in place of the timer (a popover would pop outside it): the name,
 * rhythm and evidence badge on top, then how to do it beside what the
 * evidence does and doesn't show. Also the small (i) that opens it and the
 * evidence badge the setup step reuses.
 */

import { tr } from "../../core/localization/tr";
import type { StudyMethod, StudyMethodKind } from "../../core/studyMethods/studyMethod";
import { evidenceLevelLabel, methodInfo, nameIsRhythm, StudyMethodInfo, type StudyEvidenceLevel } from "../../core/studyMethods/studyMethodInfo";
import { Card } from "../../ui/kit/Card";
import { IconButton } from "../../ui/kit/IconButton";
import { Pill } from "../../ui/kit/Pill";
import { Tooltip } from "../../ui/kit/Tooltip";

export interface StudyMethodInfoViewProps {
  readonly method: StudyMethod;
  /** Whether the session already uses this method. */
  readonly isCurrent: boolean;
  /** Starts a fresh session with this method. */
  readonly use: () => void;
  readonly close: () => void;
}

export function StudyMethodInfoView({ method, isCurrent, use, close }: StudyMethodInfoViewProps) {
  const info = methodInfo(method);
  return (
    <div className="study-info">
      <div className="study-info-header">
        <span className="kit-title">{info.displayName}</span>
        {!nameIsRhythm(method) && <span className="kit-title study-accent study-tabular">{method.rhythmLabel}</span>}
        {info.evidenceLevel !== undefined && <StudyEvidenceBadge level={info.evidenceLevel} />}
        <span className="study-spacer" />
        {!isCurrent && <Pill title={tr("Use %@", info.displayName)} help={tr("Start a fresh session with %@", info.displayName)} accent onClick={use} />}
        <IconButton symbol="xmark" help={tr("Close")} onClick={close} />
      </div>
      <div className="study-info-body">
        <Card className="study-info-section">
          <span className="kit-caption kit-tertiary">{tr("How to")}</span>
          <p className="kit-body study-info-text">{info.howTo}</p>
        </Card>
        {info.evidenceLevel !== undefined && (
          <Tooltip text={StudyMethodInfo.footnote}>
            <Card className="study-info-section study-info-evidence">
              <span className="kit-caption kit-tertiary">{tr("Evidence")}</span>
              <p className="kit-caption kit-secondary study-info-text">{info.evidence}</p>
            </Card>
          </Tooltip>
        )}
      </div>
    </div>
  );
}

/** How well supported a method is, as a small tinted capsule. */
export function StudyEvidenceBadge({ level, help }: { level: StudyEvidenceLevel; help?: string }) {
  const label = evidenceLevelLabel(level);
  return (
    <Tooltip text={help ?? tr("Evidence: %@", label)}>
      <span className="study-evidence kit-caption" data-level={level}>
        {label}
      </span>
    </Tooltip>
  );
}

/** A small (i) that opens a method's info view. */
export function StudyInfoButton({ method, onClick }: { method: StudyMethodKind; onClick: () => void }) {
  return <IconButton symbol="info.circle" size={20} className="study-quiet-button" help={tr("How %@ works", StudyMethodInfo.info(method).displayName)} onClick={onClick} />;
}
