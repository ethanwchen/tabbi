/*
 * Port of CrewBoardCard: the weekly top 3 beside every Crew view (this
 * week's live race with the countdown to the freeze, or last week's winners
 * with the laurels they won; a crew opens its page on click), the New crew
 * and Edit form with its live preview card, and the crew report card.
 */

import { useState, type KeyboardEvent } from "react";
import { useStore } from "../../app/useStore";
import { CREW_COLORS, CREW_LIMITS, crewColorTitle, crewIcons, crewPetColor } from "../../core/crews/crewCatalog";
import { CREW_ICON_COMPACT_PIXEL_SIZE } from "../../core/crews/crewIconArt";
import { crewCountdown, crewHours } from "../../core/crews/crewFormat";
import { CREW_REPORT_REASONS, crewReportReasonTitle, type CrewBoardEntry, type CrewReportReason } from "../../core/crews/crewModels";
import { boardEntries, cleanCrewText, crewDraftProblemMessage } from "../../core/crews/crewsState";
import { tr } from "../../core/localization/tr";
import { REPORT_NOTE_LIMIT } from "../../core/party/partyModeration";
import { Card } from "../../ui/kit/Card";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { CrewIconView, CrewMemberPet, CrewRankBadge, CrewSummaryIcon, CrewTextField, FirstThatFits } from "./CrewComponents";
import { CrewHeader } from "./CrewsPanel";
import { PartyPillButton, PartyTextButton } from "./PartyComponents";
import { draftProblem, type CrewReportTarget, type CrewsStore } from "./crewsStore";

export function CrewBoardCard({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews);
  const crewsState = state.crews;
  const entries = boardEntries(crewsState);
  const lastWeek = crewsState.showsLastWeek;
  const hasFeatured = crewsState.board?.featured !== undefined;
  const header = (showsTitle: boolean) => (
    <div className="crew-board-header">
      {(showsTitle || lastWeek) && (
        <>
          <span className="kit-caption kit-tertiary crew-nowrap">{lastWeek ? tr("Last week") : tr("Top 3")}</span>
          <span className="party-spacer" />
        </>
      )}
      {!lastWeek && (
        <Tooltip text={tr("The week ends Sunday 23:59 UTC. Then the top 3 freeze and win their laurels for next week.")}>
          <span className="crew-countdown kit-caption kit-secondary crew-number crew-nowrap">
            <Icon id="clock" size={9} />
            {crewCountdown(crewsState.week, state.now)}
          </span>
        </Tooltip>
      )}
    </div>
  );
  let rows;
  if (crewsState.board === undefined) rows = <div className="crew-board-rows" />;
  else if (entries.length === 0)
    rows = (
      <div className="crew-board-empty kit-caption kit-secondary">
        {lastWeek ? tr("Last week's winners show here once a week has ended.") : tr("No crew has studied yet this week. Yours could be first.")}
      </div>
    );
  else
    rows = (
      <div className="crew-board-rows">
        {entries.map((entry) => (
          <CrewBoardRow key={entry.crew.id} crews={crews} entry={entry} isMine={entry.crew.id === crewsState.mine?.summary.id} isOpen={entry.crew.id === crewsState.viewing?.summary.id} />
        ))}
      </div>
    );
  return (
    <Card padding={8} className="crew-board">
      <FirstThatFits className="crew-board-header-fits" candidates={[header(true), header(false)]} />
      {rows}
      <div className="crew-board-tabs" role="tablist">
        <Tooltip text={tr("This week's live top 3")}>
          <button type="button" role="tab" aria-selected={!lastWeek} className="crew-board-tab kit-caption" data-selected={!lastWeek || undefined} onClick={() => crews.showLastWeek(false)}>
            {tr("This week")}
          </button>
        </Tooltip>
        <Tooltip text={hasFeatured ? tr("Last week's winners and their laurels") : tr("Last week's winners show here once a week has ended.")}>
          <button type="button" role="tab" aria-selected={lastWeek} disabled={!hasFeatured} className="crew-board-tab kit-caption" data-selected={lastWeek || undefined} onClick={() => crews.showLastWeek(true)}>
            {tr("Last week")}
          </button>
        </Tooltip>
      </div>
    </Card>
  );
}

function CrewBoardRow({ crews, entry, isMine, isOpen }: { crews: CrewsStore; entry: CrewBoardEntry; isMine: boolean; isOpen: boolean }) {
  return (
    <Tooltip text={tr("See %@ and its members' pets", entry.crew.name)}>
      <div className="crew-board-row" role="button" tabIndex={0} data-open={isOpen || undefined} onClick={() => crews.openCrew(entry.crew.id)}>
        <CrewRankBadge rank={entry.rank} />
        <CrewSummaryIcon crew={entry.crew} pixelSize={CREW_ICON_COMPACT_PIXEL_SIZE} />
        <div className="crew-board-words">
          <span className="kit-body-emphasis crew-truncate kit-user-text">{entry.crew.name}</span>
          <span className="kit-caption crew-number crew-nowrap" style={{ color: isMine ? "var(--accent)" : "var(--secondary-text)" }}>
            {isMine ? tr("%@ · Your crew", crewHours(entry.minutes)) : crewHours(entry.minutes)}
          </span>
        </div>
      </div>
    </Tooltip>
  );
}

/* MARK: New crew and Edit */

/** The form's fields: name, description, the icon row and the color dots. */
export function CrewFormView({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews);
  const draft = state.draft;
  const editing = state.crews.editing;
  return (
    <div className="crew-form">
      <CrewHeader crews={crews}>
        <span className="kit-body-emphasis crew-nowrap">{editing ? tr("Edit crew") : tr("New crew")}</span>
      </CrewHeader>
      <CrewTextField
        placeholder={tr("Crew name")}
        value={draft.name}
        limit={CREW_LIMITS.nameMaxLength}
        help={tr("Up to %lld characters. Everyone in Party can see it on the board.", CREW_LIMITS.nameMaxLength)}
        onChange={(name) => crews.updateDraft({ name })}
      />
      <CrewTextField
        placeholder={tr("A short description (optional)")}
        value={draft.description}
        limit={CREW_LIMITS.descriptionMaxLength}
        help={tr("One line about your crew, up to %lld characters", CREW_LIMITS.descriptionMaxLength)}
        onChange={(description) => crews.updateDraft({ description })}
      />
      <EdgeFade edge="end" length={12} className="crew-icon-row">
        <div className="crew-icon-row-inner" role="radiogroup">
          {crewIcons().map((icon) => (
            <Tooltip key={icon} text={tr("Use this icon")}>
              <button type="button" role="radio" aria-checked={draft.icon === icon} className="crew-icon-choice" data-selected={draft.icon === icon || undefined} onClick={() => crews.updateDraft({ icon })}>
                <CrewIconView icon={icon} color={draft.color} pixelSize={CREW_ICON_COMPACT_PIXEL_SIZE} />
              </button>
            </Tooltip>
          ))}
        </div>
      </EdgeFade>
      <div className="crew-colors" role="radiogroup">
        {CREW_COLORS.map((color) => {
          const pet = crewPetColor(color);
          const fill = `rgb(${pet.red}, ${pet.green}, ${pet.blue})`;
          const selected = draft.color === color.id;
          return (
            <Tooltip key={color.id} text={crewColorTitle(color)}>
              <button
                type="button"
                role="radio"
                aria-checked={selected}
                aria-label={crewColorTitle(color)}
                className="crew-color-choice"
                data-selected={selected || undefined}
                style={{ ["--crew-color" as string]: fill }}
                onClick={() => crews.updateDraft({ color: color.id })}
              />
            </Tooltip>
          );
        })}
      </div>
    </div>
  );
}

/** Beside the form: how the crew will look on the board, Public or Private, the line saying every crew can be featured with its members' pets, and Create (or Save). */
export function CrewPreviewCard({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews);
  const draft = state.draft;
  const editing = state.crews.editing;
  const problem = draftProblem(draft);
  const name = cleanCrewText(draft.name);
  const busy = crews.isPending("save");
  return (
    <Card padding={8} className="crew-preview">
      <div className="crew-preview-identity">
        <CrewIconView icon={draft.icon} color={draft.color} pixelSize={CREW_ICON_COMPACT_PIXEL_SIZE} />
        <span className={name === "" ? "kit-body-emphasis kit-tertiary crew-wrap" : "kit-body-emphasis crew-wrap kit-user-text"}>{name === "" ? tr("Your crew") : name}</span>
      </div>
      <div className="crew-visibility">
        <div className="crew-visibility-choices" role="radiogroup">
          {(["public", "private"] as const).map((visibility) => {
            const title = visibility === "public" ? tr("Public") : tr("Private");
            return (
              <Tooltip key={visibility} text={title}>
                <button
                  type="button"
                  role="radio"
                  aria-checked={draft.visibility === visibility}
                  className="crew-visibility-choice kit-caption"
                  data-selected={draft.visibility === visibility || undefined}
                  onClick={() => crews.updateDraft({ visibility })}
                >
                  <Icon id={visibility === "public" ? "globe" : "lock.fill"} size={9} />
                  <span>{title}</span>
                </button>
              </Tooltip>
            );
          })}
        </div>
        <span className="kit-caption kit-secondary crew-wrap">{draft.visibility === "public" ? tr("Anyone can find and join it.") : tr("Only people with the invite can join.")}</span>
      </div>
      <span className="kit-caption crew-wrap" style={{ color: problem === undefined || problem === "nameEmpty" ? "var(--secondary-text)" : "var(--warning)" }}>
        {problem === undefined ? tr("Every crew can appear on the weekly top 3 with its members' pets.") : crewDraftProblemMessage(problem)}
      </span>
      <span className="party-spacer" />
      <div className="crew-row">
        <PartyTextButton title={tr("Cancel")} help={tr("Close without saving")} onClick={() => crews.cancelEdit()} />
        <span className="party-spacer" />
        <PartyPillButton
          title={editing ? tr("Save") : tr("Create")}
          prominent
          height={20}
          busy={busy || problem !== undefined}
          help={problem !== undefined ? crewDraftProblemMessage(problem) : editing ? tr("Save your changes") : tr("Create the crew with you as its owner")}
          onClick={() => crews.saveDraft()}
        />
      </div>
    </Card>
  );
}

/* MARK: Reports */

/** Reports a crew, or one of its members, to the Tabbi team: a reason, an optional note, and for a member an offer to block them too. */
export function CrewReportCard({ target, crews }: { target: CrewReportTarget; crews: CrewsStore }) {
  const pending = useStore(crews, (state) => state.pending);
  const [reason, setReason] = useState<CrewReportReason | undefined>(undefined);
  const [note, setNote] = useState("");
  const [alsoBlock, setAlsoBlock] = useState(true);
  const sending = pending?.kind === "report";
  const name = target.member?.name ?? target.crew.name;
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      crews.cancelReport();
    }
  };
  const reasons = (tight: boolean) => (
    <div className="party-report-reasons" data-tight={tight || undefined} role="radiogroup" aria-label={tr("Report %@", name)}>
      {CREW_REPORT_REASONS.map((option) => (
        <Tooltip key={option} text={tr("Report %@: %@", name, crewReportReasonTitle(option))}>
          <button type="button" role="radio" aria-checked={reason === option} className="party-chip" data-selected={reason === option || undefined} onClick={() => setReason(option)}>
            {crewReportReasonTitle(option)}
          </button>
        </Tooltip>
      ))}
    </div>
  );
  return (
    <Card className="party-report" onKeyDown={onKeyDown}>
      <div className="party-report-header">
        {target.member !== undefined ? <CrewMemberPet member={target.member} /> : <CrewSummaryIcon crew={target.crew} pixelSize={CREW_ICON_COMPACT_PIXEL_SIZE} />}
        <div className="party-report-words">
          <MarqueeText text={tr("Report %@", name)} userText className="kit-body-emphasis" />
          <MarqueeText text={tr("The Tabbi team reviews it. %@ isn't told.", name)} userText className="kit-caption kit-secondary" />
        </div>
      </div>
      <FirstThatFits candidates={[reasons(false), reasons(true)]} />
      <Tooltip text={tr("What happened, in a sentence or two")}>
        <input className="party-note" aria-label={tr("Add a note (optional)")} placeholder={tr("Add a note (optional)")} value={note} maxLength={REPORT_NOTE_LIMIT} onChange={(event) => setNote(event.target.value)} />
      </Tooltip>
      <div className="party-spacer" />
      <div className="party-report-footer">
        {target.member !== undefined && (
          <Tooltip text={tr("Hide each other everywhere in Party. You can unblock in Party options.")}>
            <button type="button" role="checkbox" aria-checked={alsoBlock} className="party-checkbox kit-caption" onClick={() => setAlsoBlock((on) => !on)}>
              <Icon id={alsoBlock ? "checkmark.square.fill" : "square"} size={12} style={{ color: alsoBlock ? "var(--accent)" : "var(--tertiary-text)" }} />
              <span className="kit-user-text">{tr("Also block %@", name)}</span>
            </button>
          </Tooltip>
        )}
        <span className="party-spacer" />
        <PartyTextButton title={tr("Cancel")} busy={sending} help={tr("Close without reporting (Esc)")} onClick={() => crews.cancelReport()} />
        <PartyPillButton
          title={tr("Send Report")}
          prominent
          height={20}
          busy={sending || reason === undefined}
          help={reason === undefined ? tr("Pick a reason first") : tr("Send this report to the Tabbi team")}
          onClick={() => {
            if (reason !== undefined) crews.sendReport(reason, note, target.member !== undefined && alsoBlock);
          }}
        />
      </div>
    </Card>
  );
}
