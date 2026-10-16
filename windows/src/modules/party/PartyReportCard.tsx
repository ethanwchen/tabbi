/*
 * Port of PartyReportCard: reports a friend or party member to the Tabbi
 * team: a reason, an optional note, and an offer to block them as well. It
 * covers the panel while open, so the person stays in view and nothing
 * else competes.
 */

import { useState, type KeyboardEvent } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import type { PartyProfile } from "../../core/party/partyModels";
import { PARTY_REPORT_REASONS, REPORT_NOTE_LIMIT, reportReasonTitle, type PartyReportReason } from "../../core/party/partyModeration";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { PartyPet, PartyPillButton, PartyTextButton } from "./PartyComponents";
import type { PartyStore } from "./partyStore";

export function PartyReportCard({ profile, store }: { profile: PartyProfile; store: PartyStore }) {
  const pending = useStore(store, (state) => state.pending);
  const [reason, setReason] = useState<PartyReportReason | undefined>(undefined);
  const [note, setNote] = useState("");
  const [alsoBlock, setAlsoBlock] = useState(true);
  const sending = pending?.kind === "report";
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      store.cancelReport();
    }
  };
  return (
    <Card className="party-report" onKeyDown={onKeyDown}>
      <div className="party-report-header">
        <PartyPet profile={profile} />
        <div className="party-report-words">
          <MarqueeText text={tr("Report %@", profile.name)} className="kit-body-emphasis" />
          <MarqueeText text={tr("The Tabbi team reviews it. %@ isn't told.", profile.name)} className="kit-caption kit-secondary" />
        </div>
      </div>
      <div className="party-report-reasons" role="radiogroup" aria-label={tr("Report %@", profile.name)}>
        {PARTY_REPORT_REASONS.map((option) => (
          <Tooltip key={option} text={tr("Report %@ for %@", profile.name, reportReasonTitle(option).toLowerCase())}>
            <button type="button" role="radio" aria-checked={reason === option} className="party-chip" data-selected={reason === option || undefined} onClick={() => setReason(option)}>
              {reportReasonTitle(option)}
            </button>
          </Tooltip>
        ))}
      </div>
      <Tooltip text={tr("What happened, in a sentence or two")}>
        <input
          className="party-note"
          aria-label={tr("Add a note (optional)")}
          placeholder={tr("Add a note (optional)")}
          value={note}
          maxLength={REPORT_NOTE_LIMIT}
          onChange={(event) => setNote(event.target.value)}
        />
      </Tooltip>
      <div className="party-spacer" />
      <div className="party-report-footer">
        <Tooltip text={tr("Hide each other everywhere in Party. You can unblock in Party options.")}>
          <button type="button" role="checkbox" aria-checked={alsoBlock} className="party-checkbox kit-caption" onClick={() => setAlsoBlock((on) => !on)}>
            <Icon id={alsoBlock ? "checkmark.square.fill" : "square"} size={12} style={{ color: alsoBlock ? "var(--accent)" : "var(--tertiary-text)" }} />
            <span>{tr("Also block %@", profile.name)}</span>
          </button>
        </Tooltip>
        <span className="party-spacer" />
        <PartyTextButton title={tr("Cancel")} busy={sending} help={tr("Close without reporting (Esc)")} onClick={() => store.cancelReport()} />
        <PartyPillButton
          title={tr("Send Report")}
          prominent
          height={20}
          busy={sending || reason === undefined}
          help={reason === undefined ? tr("Pick a reason first") : tr("Send this report to the Tabbi team")}
          onClick={() => {
            if (reason !== undefined) store.sendReport(reason, note, alsoBlock);
          }}
        />
      </div>
    </Card>
  );
}
