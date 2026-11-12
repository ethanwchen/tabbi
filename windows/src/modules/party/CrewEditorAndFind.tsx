/*
 * Port of CrewEditorAndFind: the crest editor (New crew and Edit crew: a
 * live crest preview with the name under it as it will wrap on a tile,
 * Shuffle and the Public or Private toggle, the name and description, and
 * the frame, emblem and color pickers), Find, and the crew report card.
 */

import { useState, type KeyboardEvent, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { CREW_LIMITS, crewColors, crewColorTitle, crewEmblems, crewEmblemTitle, crewFrames, crewFrameTitle } from "../../core/crews/crewCatalog";
import { CREW_CREST_REGULAR_PIXEL_SIZE } from "../../core/crews/crewCrestArt";
import { crewHours, crewMembersOf } from "../../core/crews/crewFormat";
import { CREW_REPORT_REASONS, crewIsFull, crewReportReasonTitle, type CrewReportReason, type CrewSummary } from "../../core/crews/crewModels";
import { cleanCrewText, crewDraftProblemMessage, hasRequested, inCrew, type CrewSection } from "../../core/crews/crewsState";
import { tr } from "../../core/localization/tr";
import { REPORT_NOTE_LIMIT } from "../../core/party/partyModeration";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useElementWidth } from "../../ui/kit/useElementWidth";
import { CrewBoardSkeleton } from "./CrewBoards";
import {
  CrewButton,
  CrewCrestView,
  CrewEmblemView,
  CrewPetView,
  CrewRow,
  CrewRowList,
  CrewRowName,
  CrewStatus,
  CrewSummaryCrest,
  CrewTag,
  CrewTextField,
  FirstThatFits,
  useCrewIsCompact,
  useFitStep,
} from "./CrewComponents";
import { CrewBackPill } from "./CrewsPanel";
import { PartyPillButton, PartyTextButton } from "./PartyComponents";
import { draftProblem, type CrewReportTarget, type CrewsStore } from "./crewsStore";

/* MARK: The crest editor */

export function CrewEditorScreen({ crews, editing, from }: { crews: CrewsStore; editing: boolean; from: CrewSection }) {
  const store = useStore(crews);
  const compact = useCrewIsCompact();
  const draft = store.draft;
  const problem = draftProblem(draft);
  const name = cleanCrewText(draft.name);
  const isPublic = draft.visibility === "public";
  const warning = problem !== undefined && problem !== "nameEmpty";
  const note = warning ? crewDraftProblemMessage(problem) : tr("Every crew can appear on the weekly top 3 with its members' pets.");
  /* Nothing in the side column is cut: a name that wraps to two lines where the column has no room for it gives up its preview under the crest. */
  const [side, step] = useFitStep<HTMLDivElement>(1, `${compact}|${name}`);
  const actions = (titled: boolean) => (
    <div className="crew-editor-actions">
      <CrewButton title={tr("Shuffle")} symbol="shuffle" titled={titled} help={tr("A random frame, emblem and color")} onClick={() => crews.shuffleCrest()} />
      <CrewButton
        title={isPublic ? tr("Public") : tr("Private")}
        symbol={isPublic ? "globe" : "lock.fill"}
        titled={titled}
        role="switch"
        checked={isPublic}
        help={isPublic ? tr("Anyone can find it and ask to join. Click to make it private.") : tr("Only people with the invite link can join. Click to make it public.")}
        onClick={() => crews.updateDraft({ visibility: isPublic ? "private" : "public" })}
      />
    </div>
  );
  return (
    <>
      <div className="crews-head">
        <CrewBackPill crews={crews} from={from} />
        <span className="kit-title crews-head-title crew-nowrap">{editing ? tr("Edit crew") : tr("New crew")}</span>
        <span className="crews-head-trail">
          <CrewButton
            title={editing ? tr("Save") : tr("Create")}
            style="prominent"
            enabled={problem === undefined}
            busy={store.pending?.kind === "save"}
            help={problem !== undefined ? crewDraftProblemMessage(problem) : editing ? tr("Save your changes") : tr("Create the crew with you as its owner")}
            onClick={() => crews.saveDraft()}
          />
        </span>
      </div>
      <div className="crews-body crew-editor">
        <div ref={side} className="crew-editor-side">
          <div className="crew-editor-preview">
            <div className="crew-editor-crest" data-named={(!compact && step < 1) || undefined}>
              <CrewCrestView crest={draft.crest} pixelSize={CREW_CREST_REGULAR_PIXEL_SIZE} />
              {!compact && step < 1 && (
                <span className="crew-tile-name kit-caption kit-user-text" data-empty={name === "" || undefined}>
                  {name === "" ? tr("Crew name") : name}
                </span>
              )}
            </div>
            {/* A long word for Shuffle or Public gives way to the glyphs alone, with the words in their tooltips. */}
            <FirstThatFits className="crew-editor-actions-fits" candidates={[actions(true), actions(false)]} />
          </div>
          <CrewTextField
            placeholder={tr("Crew name")}
            value={draft.name}
            limit={CREW_LIMITS.nameMaxLength}
            help={tr("Up to %lld characters. Everyone in Party can see it on the board.", CREW_LIMITS.nameMaxLength)}
            onChange={(value) => crews.updateDraft({ name: value })}
            onSubmit={() => crews.saveDraft()}
          />
          <CrewTextField
            placeholder={tr("What you study")}
            value={draft.description}
            limit={CREW_LIMITS.descriptionMaxLength}
            help={tr("One line about your crew, up to %lld characters", CREW_LIMITS.descriptionMaxLength)}
            onChange={(value) => crews.updateDraft({ description: value })}
            onSubmit={() => crews.saveDraft()}
          />
        </div>
        <div className="crew-editor-pickers">
          <CrewPicker title={tr("Frame")}>
            <div className="crew-options crew-options-frames" role="radiogroup" aria-label={tr("Frame")}>
              {crewFrames().map((frame) => (
                <CrewOption key={frame} selected={draft.crest.frame === frame} help={crewFrameTitle(frame)} kind="frame" onClick={() => crews.updateCrest({ frame })}>
                  <CrewCrestView
                    crest={{
                      frame,
                      emblem: draft.crest.emblem,
                      color: draft.crest.color,
                    }}
                  />
                </CrewOption>
              ))}
            </div>
          </CrewPicker>
          <CrewPicker title={tr("Emblem")}>
            {/* One row that scrolls by whole tiles, so the line under the pickers always has room. */}
            <CrewChoiceRow label={tr("Emblem")} side={24} spacing={4}>
              {crewEmblems().map((emblem) => (
                <CrewOption key={emblem} selected={draft.crest.emblem === emblem} help={crewEmblemTitle(emblem)} kind="emblem" onClick={() => crews.updateCrest({ emblem })}>
                  <CrewEmblemView emblem={emblem} color={draft.crest.color} />
                </CrewOption>
              ))}
            </CrewChoiceRow>
          </CrewPicker>
          <CrewPicker title={tr("Color")}>
            <div className="crew-options crew-options-colors" role="radiogroup" aria-label={tr("Color")}>
              {crewColors().map((color) => (
                <CrewOption key={color.id} selected={draft.crest.color === color.id} help={crewColorTitle(color)} kind="color" onClick={() => crews.updateCrest({ color: color.id })}>
                  <i className="crew-swatch" style={{ background: color.hex }} />
                </CrewOption>
              ))}
            </div>
          </CrewPicker>
          {/* The owner's promise in the create flow: any crew can be featured. */}
          <div className="kit-caption crew-editor-note" data-warning={warning || undefined}>
            {note}
          </div>
        </div>
      </div>
    </>
  );
}

/** A row of picker options that scrolls sideways by whole options and shows only whole options, with the rest a scroll away. */
function CrewChoiceRow({ label, side, spacing, children }: { label: string; side: number; spacing: number; children: ReactNode[] }) {
  const [row, width] = useElementWidth<HTMLDivElement>();
  const visible = Math.max(1, Math.floor((width + spacing) / (side + spacing)));
  const shown = Math.min(visible, children.length);
  return (
    <div ref={row} className="crew-choice-row">
      <div
        className="crew-options crew-options-row"
        role="radiogroup"
        aria-label={label}
        data-scrolls={(width > 0 && children.length > visible) || undefined}
        style={{ gap: spacing, width: width > 0 ? shown * (side + spacing) - spacing : undefined }}
      >
        {children}
      </div>
    </div>
  );
}

function CrewPicker({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="crew-picker">
      <span className="crew-picker-label kit-caption kit-tertiary">{title}</span>
      {children}
    </div>
  );
}

/** One option in the editor's pickers: accent tint and ring when chosen. */
function CrewOption({ selected, help, kind, onClick, children }: { selected: boolean; help: string; kind: "frame" | "emblem" | "color"; onClick: () => void; children: ReactNode }) {
  return (
    <Tooltip text={help}>
      <button type="button" role="radio" aria-checked={selected} aria-label={help} className="crew-option" data-kind={kind} onClick={onClick}>
        {children}
      </button>
    </Tooltip>
  );
}

/* MARK: Find */

export function CrewFindScreen({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (store) => store.crews);
  const results = state.results;
  let body;
  if (results === undefined) body = <CrewBoardSkeleton />;
  else if (results.length === 0)
    body = (
      <CrewStatus
        symbol="magnifyingglass"
        title={tr("No crews match")}
        detail={tr("Try another word, or create one.")}
        actions={!inCrew(state) ? <CrewButton title={tr("Create a crew")} height={24} help={tr("Make a crew and invite friends")} onClick={() => crews.openEditor(false)} /> : undefined}
      />
    );
  else body = <CrewRowList count={results.length} row={(index) => <CrewFindRow crews={crews} crew={results[index] as CrewSummary} />} />;
  return (
    <div className="crew-find">
      <CrewTextField
        placeholder={tr("Search public crews")}
        value={state.query}
        limit={CREW_LIMITS.nameMaxLength}
        symbol="magnifyingglass"
        help={tr("Search public crews by name")}
        onChange={(query) => crews.search(query)}
      />
      <div className="crew-find-body">{body}</div>
    </div>
  );
}

function CrewFindRow({ crews, crew }: { crews: CrewsStore; crew: CrewSummary }) {
  const store = useStore(crews);
  const state = store.crews;
  const mine = state.mine?.summary.id === crew.id;
  let trailing;
  if (mine) trailing = <CrewTag title={tr("Your crew")} accent />;
  else if (hasRequested(state, crew.id)) trailing = <CrewTag title={tr("Requested")} symbol="checkmark" />;
  else if (crewIsFull(crew)) trailing = <CrewTag title={tr("Full")} />;
  else if (!inCrew(state))
    trailing = <CrewButton title={tr("Join")} busy={store.pending?.kind === "join"} help={tr("Ask to join %@. Its owner lets you in.", crew.name)} onClick={() => crews.requestToJoin(crew)} />;
  return (
    <CrewRow mine={mine} help={crew.description === "" ? crew.name : crew.description} onClick={() => crews.openCrew(crew.id)}>
      <CrewSummaryCrest crew={crew} />
      <CrewRowName name={crew.name} caption={tr("%@ · %@ this week", crewMembersOf(crew.memberCount, crew.maxMembers), crewHours(crew.weekMinutes))} />
      {trailing !== undefined && (
        <span className="crew-row-trail" onClick={(event) => event.stopPropagation()}>
          {trailing}
        </span>
      )}
    </CrewRow>
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
        {target.member !== undefined ? <CrewPetView pet={target.member.pet} name={target.member.name} /> : <CrewSummaryCrest crew={target.crew} />}
        <div className="party-report-words">
          <MarqueeText text={tr("Report %@", name)} userText className="kit-body-emphasis" />
          <MarqueeText text={tr("The Tabbi team reviews it. %@ isn't told.", name)} userText className="kit-caption kit-secondary" />
        </div>
      </div>
      <FirstThatFits candidates={[reasons(false), reasons(true)]} />
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
        {target.member !== undefined && (
          <Tooltip text={tr("Hide each other everywhere in Party. You can unblock in Party options.")}>
            <button type="button" role="checkbox" aria-checked={alsoBlock} className="party-checkbox kit-caption" onClick={() => setAlsoBlock((on) => !on)}>
              <Icon
                id={alsoBlock ? "checkmark.square.fill" : "square"}
                size={12}
                style={{
                  color: alsoBlock ? "var(--accent)" : "var(--tertiary-text)",
                }}
              />
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
