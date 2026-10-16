/*
 * Port of StudyMethodSetupView: onboarding's study method step. The kit's
 * methods as one-tap tiles on the left, and on the right what the hovered
 * (or chosen) method asks of you and how well it is supported, so the pick
 * is an informed one. A tap sets the Study timer's method right away.
 */

import { useState } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import type { StudyMethod, StudyMethodKind } from "../../core/studyMethods/studyMethod";
import { methodInfo, nameIsRhythm, StudyMethodInfo } from "../../core/studyMethods/studyMethodInfo";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { RowsThatFit } from "../../ui/kit/RowsThatFit";
import { Tooltip } from "../../ui/kit/Tooltip";
import { StudyEvidenceBadge } from "./studyMethodInfoView";
import { StudyMethodTile } from "./studyMethodTile";
import type { StudyStore } from "./studyStore";
import "./study.css";

export function StudyMethodSetupView({ store }: { store: StudyStore }) {
  const { session } = useStore(store);
  const [hovered, setHovered] = useState<StudyMethodKind | undefined>(undefined);
  const methods = store.methods;
  const current = session.method.kind;
  const shown = methods.find((method) => method.kind === (hovered ?? current)) ?? session.method;
  return (
    <div className="study-setup">
      <div className="study-setup-grid">
        {methods.map((method) => (
          <StudyMethodTile
            key={method.kind}
            method={method}
            isCurrent={method.kind === current}
            showsRhythm={false}
            onPick={() => store.choose(method.kind)}
            onHover={(hovering) => setHovered((last) => (hovering ? method.kind : last === method.kind ? undefined : last))}
          />
        ))}
      </div>
      <StudyMethodSummaryCard method={shown} isCurrent={shown.kind === current} />
    </div>
  );
}

/** One method in brief: name, rhythm and evidence on top, then how to do it. */
function StudyMethodSummaryCard({ method, isCurrent }: { method: StudyMethod; isCurrent: boolean }) {
  const info = methodInfo(method);
  /* As many whole sentences as fit, never a cut-off one: every sentence is a row, and the rows that fit show. */
  const sentences = info.howToSentencePrefixes.map((prefix, index, all) => (index === 0 ? prefix : prefix.slice((all[index - 1] ?? "").length).trimStart()));
  return (
    <Card className="study-setup-summary">
      <div className="study-setup-summary-header kit-body-emphasis">
        <span className="study-setup-summary-name">{info.displayName}</span>
        {!nameIsRhythm(method) && <span className="study-accent study-rhythm">{method.rhythmLabel}</span>}
        <span className="study-spacer" />
        {isCurrent && (
          <Tooltip text={tr("The timer starts with %@", info.displayName)}>
            <span className="study-accent study-setup-check">
              <Icon id="checkmark.circle.fill" size={12} />
            </span>
          </Tooltip>
        )}
      </div>
      <Tooltip text={info.howTo}>
        <RowsThatFit className="study-setup-sentences" data={sentences} keyOf={(_, index) => index} row={(sentence) => <span className="kit-caption kit-secondary study-setup-sentence kit-user-text" dir="auto">{sentence}</span>} />
      </Tooltip>
      {info.evidenceLevel !== undefined && <StudyEvidenceBadge level={info.evidenceLevel} help={`${info.evidence} ${StudyMethodInfo.footnote}`} />}
    </Card>
  );
}
