/*
 * Port of DayPlanView.swift: Plan my day, shown in place of the checklist.
 * A header with the plan's actions over the proposed blocks, a shimmer
 * while the AI thinks, or a short message with Retry when something went
 * wrong. On Windows accepted blocks stay in Today (there is no calendar to
 * write to), so the copy says "Today" where the Mac says "your calendar".
 */

import { useLayoutEffect, useRef, useState } from "react";
import { useStore } from "../../app/useStore";
import { displayName, requiresAPIKey } from "../../core/ai/aiProviderID";
import { tr } from "../../core/localization/tr";
import type { DateInterval } from "../../core/planner/dateInterval";
import type { PlanBlock, PlanBlockKind } from "../../core/planner/dayPlan";
import type { DayPlanProposal } from "../../core/planner/dayPlanProposal";
import { viewedDayPlanTitle } from "../../core/planner/plannerViewedDay";
import { eventStartTime } from "../../core/planner/upcomingEvent";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { Shimmer, SkeletonLine } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { DayPlanFailure, DayPlanStore } from "./dayPlanStore";
import { blockRange, breakLength, planningHelp } from "./plannerFormat";
import { PlannerGlyphButton, PlannerMessage, PlannerPillButton, PlannerTextButton } from "./plannerControls";

/** Fits "10:45-11:30" in the caption font. */
const RANGE_WIDTH = 76;

export interface DayPlanViewProps {
  readonly plan: DayPlanStore;
  readonly locale: string;
  readonly timeZone: string;
  readonly openConnections: () => void;
}

function failureTitle(failure: DayPlanFailure): string {
  switch (failure.kind) {
    case "aiNotSetUp":
      return failure.provider === undefined ? tr("Choose an AI to plan with") : tr("%@ isn't set up yet", displayName(failure.provider));
    case "aiFailed":
      return tr("Couldn't plan your day");
  }
}

function failureDetail(failure: DayPlanFailure): string {
  switch (failure.kind) {
    case "aiNotSetUp":
      if (failure.provider === undefined) return tr("Plan my day asks the AI you pick in Settings.");
      return requiresAPIKey(failure.provider)
        ? tr("Add your %@ key in Settings.", displayName(failure.provider))
        : tr("Install %@ to plan with it.", displayName(failure.provider));
    case "aiFailed":
      return tr("%@ didn't send back a usable plan. Try again in a moment.", failure.assistant);
  }
}

/** The caption under the rows: where blocks go, then what happened to the ones accepted so far. */
function footerText(proposal: DayPlanProposal, assistant: string): string {
  const parts: string[] = [];
  if (proposal.addedCount > 0) parts.push(tr("%lld added to Today", proposal.addedCount));
  if (proposal.skippedCount > 0) parts.push(tr("%lld no longer fit", proposal.skippedCount));
  if (parts.length > 0) return parts.join(" · ");
  switch (proposal.refinement) {
    case "changed":
      return tr("Refined with %@.", assistant);
    case "unchanged":
      return tr("%@ suggests no changes.", assistant);
    case undefined:
      return tr("Blocks go to Today.");
  }
}

/** Review and study blocks get a symbol; the AI's focus blocks don't. */
function kindSymbol(kind: PlanBlockKind): string | undefined {
  switch (kind) {
    case "focus":
      return undefined;
    case "reviews":
      return "rectangle.stack.fill";
    case "study":
      return "book.fill";
  }
}

export function DayPlanView({ plan, locale, timeZone, openConnections }: DayPlanViewProps) {
  const state = useStore(plan);
  const phase = state.phase;
  const tomorrow = state.target === "tomorrow";
  const isFinal = phase.kind === "noFreeTime";
  const title =
    phase.kind === "planning"
      ? tomorrow
        ? tr("Planning tomorrow…")
        : tr("Planning your day…")
      : phase.kind === "proposal"
        ? tomorrow
          ? tr("Tomorrow")
          : tr("Your plan")
        : viewedDayPlanTitle(state.target);
  /*
   * The Mac's ViewThatFits over the header row: the Add all pill keeps its
   * glyph while the title shows whole, then drops it, and in a language
   * longer still Cancel becomes a round glyph. Measured after layout: a
   * title still cut moves to the next level, and a new title starts over.
   */
  const addAllTitle = tr("Add all");
  const cancelTitle = isFinal ? tr("Done") : tr("Cancel");
  const header = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState<{ title: string; level: number }>({ title, level: 0 });
  const level = fit.title === title ? fit.level : 0;
  useLayoutEffect(() => {
    const element = header.current;
    if (!element || level >= 2) return;
    const line = element.querySelector<HTMLElement>(".dayplan-title .kit-marquee-line");
    const box = element.querySelector<HTMLElement>(".dayplan-title");
    if (!line || !box) return;
    if (line.getBoundingClientRect().width > box.getBoundingClientRect().width + 0.5) setFit({ title, level: level + 1 });
  }, [title, level, phase.kind]);
  const addAllSymbol = level === 0 ? "calendar.badge.plus" : undefined;
  const compactCancel = level >= 2;
  return (
    <div className="dayplan">
      <div ref={header} className="dayplan-header">
        <span className="dayplan-sparkle" data-pulse={phase.kind === "planning" || state.isRefining}>
          <Icon id="sparkles" size={12} />
        </span>
        <MarqueeText text={title} className="dayplan-title" />
        <span className="dayplan-spacer" />
        {state.writeFailed && (
          <Tooltip text={tr("Today couldn't keep the blocks. Try again.")}>
            <span className="planner-warning">
              <Icon id="exclamationmark.triangle.fill" size={10} />
              <span>{tr("Not added")}</span>
            </span>
          </Tooltip>
        )}
        {compactCancel ? (
          <IconButton symbol={isFinal ? "checkmark" : "xmark"} size={20} help={isFinal ? tr("Back to the checklist") : tr("Discard the plan and show the checklist")} onClick={() => plan.cancel()} />
        ) : (
          <PlannerTextButton title={cancelTitle} help={isFinal ? tr("Back to the checklist") : tr("Discard the plan and show the checklist")} onClick={() => plan.cancel()} />
        )}
        {phase.kind === "proposal" && (
          <PlannerPillButton
            title={addAllTitle}
            symbol={addAllSymbol}
            isProminent
            disabled={state.isRefining}
            help={tr("Add every block to Today")}
            onClick={() => void plan.add()}
          />
        )}
      </div>
      <div className="dayplan-content">
        {phase.kind === "planning" && <DayPlanShimmer help={planningHelp(plan.settings.planMode === "claude", state.assistant, tomorrow)} />}
        {phase.kind === "proposal" && (
          <div className="dayplan-rows" data-refining={state.isRefining}>
            {phase.proposal.pending.map((block) => (
              <DayPlanBlockRow
                key={block.id}
                block={block}
                rest={phase.proposal.breakAfter(block)}
                locale={locale}
                timeZone={timeZone}
                add={() => void plan.add(block.id)}
                dismiss={() => plan.dismiss(block.id)}
              />
            ))}
            <div className="dayplan-footer">
              <span className="dayplan-caption" data-failed={state.refineFailed}>
                {state.isRefining
                  ? tr("%@ is looking over this plan…", state.assistant)
                  : state.refineFailed
                    ? tr("%@ couldn't refine it. This plan still works.", state.assistant)
                    : footerText(phase.proposal, state.assistant)}
              </span>
              {state.canRefine && !state.isRefining && !state.refineFailed && phase.proposal.refinement === undefined && (
                <PlannerPillButton
                  title={tr("Refine")}
                  symbol="wand.and.stars"
                  help={tr("Refine with %@: ask for suggestions on this plan (optional)", state.assistant)}
                  onClick={() => plan.refine()}
                />
              )}
            </div>
          </div>
        )}
        {phase.kind === "noFreeTime" && (
          <PlannerMessage
            symbol="moon.stars.fill"
            tint="var(--accent)"
            title={tr("Nothing left to plan")}
            detail={tomorrow ? tr("Tomorrow has no free time worth a block before the evening.") : tr("There's no free time worth a block before the evening.")}
          />
        )}
        {phase.kind === "failed" && (
          <PlannerMessage
            symbol="exclamationmark.triangle.fill"
            tint="var(--warning)"
            title={failureTitle(phase.failure)}
            detail={failureDetail(phase.failure)}
            action={
              phase.failure.kind === "aiFailed" ? (
                <PlannerPillButton title={tr("Retry")} symbol="arrow.clockwise" help={tr("Ask %@ again", state.assistant)} onClick={() => plan.retry()} />
              ) : (
                <PlannerPillButton title={tr("Set up AI")} symbol="link" help={tr("Open Connections to finish setting this up")} onClick={openConnections} />
              )
            }
          />
        )}
      </div>
    </div>
  );
}

interface DayPlanBlockRowProps {
  readonly block: PlanBlock;
  /** The planned rest before the next block, if any. */
  readonly rest: DateInterval | undefined;
  readonly locale: string;
  readonly timeZone: string;
  readonly add: () => void;
  readonly dismiss: () => void;
}

/** One proposed block: a kind marker, the time range, the title, the break that follows it, and buttons to keep it or drop it. */
function DayPlanBlockRow({ block, rest, locale, timeZone, add, dismiss }: DayPlanBlockRowProps) {
  const symbol = kindSymbol(block.kind);
  return (
    <div className="dayplan-row">
      <span className="dayplan-marker">
        {symbol === undefined ? (
          <span className="dayplan-stripe" />
        ) : (
          <Tooltip text={block.kind === "reviews" ? tr("Review block") : tr("Study block")}>
            <span className="dayplan-kind">
              <Icon id={symbol} size={10} />
            </span>
          </Tooltip>
        )}
      </span>
      <span className="dayplan-range" style={{ width: RANGE_WIDTH }}>
        {blockRange(block, locale, timeZone)}
      </span>
      <span className="dayplan-block-title kit-user-text" title={block.title}>
        {block.title}
      </span>
      {rest !== undefined && (
        <Tooltip text={tr("Then a break until %@", eventStartTime(rest.end, locale, timeZone))}>
          <span className="dayplan-break">
            <Icon id="cup.and.saucer.fill" size={9} />
            <span>{breakLength(rest)}</span>
          </span>
        </Tooltip>
      )}
      <span className="dayplan-row-buttons">
        <PlannerGlyphButton symbol="checkmark" isTinted glyphSize={9} help={tr("Add this block to Today")} onClick={add} />
        <PlannerGlyphButton symbol="xmark" tint="var(--danger)" glyphSize={9} help={tr("Leave this block out")} onClick={dismiss} />
      </span>
    </div>
  );
}

const SHIMMER_WIDTHS = [0.72, 0.54, 0.64];

/** Placeholder rows shaped like proposal rows (stripe, time, title), with the shared skeleton shimmer while the AI plans. */
function DayPlanShimmer({ help }: { help: string }) {
  return (
    <Tooltip text={help}>
      <div role="img" aria-label={tr("Planning")}>
        <Shimmer className="dayplan-shimmer">
          {SHIMMER_WIDTHS.map((fraction, index) => (
            <div key={index} className="dayplan-shimmer-row">
              <span className="dayplan-marker">
                <SkeletonLine width={3} height={14} />
              </span>
              <SkeletonLine width={RANGE_WIDTH - 8} />
              <span className="dayplan-shimmer-title">
                <SkeletonLine fraction={fraction} />
              </span>
            </div>
          ))}
        </Shimmer>
      </div>
    </Tooltip>
  );
}
