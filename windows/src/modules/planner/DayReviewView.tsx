/*
 * Port of DayReviewView.swift: the End-of-Day Review, shown in place of
 * the checklist. A header with Done, the AI's short summary (a shimmer
 * until it arrives) over today's focus time, and what got done beside what
 * carries over to tomorrow.
 */

import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { reviewStats, type DayReview } from "../../core/planner/dayReview";
import { Icon } from "../../ui/kit/Icon";
import { Shimmer, SkeletonLine } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { DayReviewStore } from "./dayReviewStore";
import { PlannerPillButton } from "./plannerControls";

const VISIBLE_ROWS = 3;

export interface DayReviewViewProps {
  readonly store: DayReviewStore;
  readonly locale: string;
}

export function DayReviewView({ store, locale }: DayReviewViewProps) {
  const state = useStore(store);
  const review = state.review;
  if (review === undefined) return null;
  const stats = reviewStats(review, locale);
  return (
    <div className="dayreview">
      <div className="dayplan-header">
        <span className="dayplan-sparkle" data-pulse={review.summary === undefined}>
          <Icon id="moon.stars.fill" size={12} />
        </span>
        <span className="dayplan-title">{tr("Wrap-up")}</span>
        <span className="dayplan-spacer" />
        {state.saveFailed && (
          <Tooltip text={tr("The review couldn't be written to disk. Try Done again.")}>
            <span className="planner-warning">
              <Icon id="exclamationmark.triangle.fill" size={10} />
              <span>{tr("Not saved")}</span>
            </span>
          </Tooltip>
        )}
        <PlannerPillButton title={tr("Done")} isProminent help={tr("Save today's review and show the checklist")} onClick={() => void store.done()} />
      </div>
      <div className="dayreview-summary-area">
        {review.summary === undefined ? (
          <Tooltip text={tr("Writing a short summary of your day")}>
            <div role="img" aria-label={tr("Writing a summary")}>
              <Shimmer className="dayreview-shimmer">
                <SkeletonLine fraction={0.92} />
                <SkeletonLine fraction={0.6} />
              </Shimmer>
            </div>
          </Tooltip>
        ) : (
          <div className="dayreview-summary" title={review.summary}>
            {review.summary}
          </div>
        )}
        <div className="dayreview-stats">
          {stats.map((stat, index) => (
            <Tooltip key={index} text={stat.help}>
              <span className="dayreview-stat" data-first={index === 0}>
                <Icon id={stat.symbol} size={10} />
                <span>{stat.text}</span>
              </span>
            </Tooltip>
          ))}
        </div>
      </div>
      <div className="dayreview-lists">
        <DayReviewList title={tr("Done")} titles={review.done} isDone emptyText={tr("Nothing checked off")} />
        <DayReviewList title={tr("Tomorrow")} titles={review.carryingOver} isDone={false} emptyText={tr("Nothing carries over")} />
      </div>
    </div>
  );
}

/** A short titled list of task names. Shows up to three rows, ending in "+N more" when there are more, with the full list in the tooltip. */
function DayReviewList({ title, titles, isDone, emptyText }: { title: string; titles: DayReview["done"]; isDone: boolean; emptyText: string }) {
  const limit = titles.length > VISIBLE_ROWS ? VISIBLE_ROWS - 1 : VISIBLE_ROWS;
  const shown = titles.slice(0, limit);
  const hidden = titles.length - shown.length;
  return (
    <Tooltip text={titles.length === 0 ? emptyText : titles.join("\n")}>
      <div className="dayreview-list">
        <div className="dayreview-list-head">
          <span>{title}</span>
          <span className="dayreview-list-count">{titles.length}</span>
        </div>
        {titles.length === 0 ? (
          <div className="dayreview-empty">{emptyText}</div>
        ) : (
          shown.map((item, index) => (
            <div key={index} className="dayreview-item" data-done={isDone}>
              <span className="dayreview-item-glyph">
                <Icon id={isDone ? "checkmark.circle.fill" : "arrow.turn.down.right"} size={9.5} />
              </span>
              <MarqueeText text={item} />
            </div>
          ))
        )}
        {hidden > 0 && <div className="dayreview-more">{tr("+%lld more", hidden)}</div>}
      </div>
    </Tooltip>
  );
}
