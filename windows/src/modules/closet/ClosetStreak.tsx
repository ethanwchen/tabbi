/*
 * Port of ClosetStreak, ClosetStreakStrip and ClosetBuyFreezeButton: the
 * study streak, its length, the last seven days (a snowflake on each day a
 * freeze protected) and the freezes ready, with a button to buy an extra
 * one with points.
 */

import { useRef } from "react";
import { useStore } from "../../app/useStore";
import { PetEconomy } from "../../core/closet/petEconomy";
import { PetMilestoneProgress } from "../../core/closet/petLimited";
import { joinSentences } from "../../core/formatting/sentences";
import { tr } from "../../core/localization/tr";
import { StreakFreezeRules, type StreakDay, type StudyStreak } from "../../core/streaks/studyStreak";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { textWidth } from "../../ui/shell/measure";
import { dayLongTitle, weekdayInitials, weekdayOf } from "./closetFormat";
import type { ClosetStore } from "./closetStore";
import { useElementSize } from "./useElementSize";

/** Snowflakes mark frozen days in an icy blue that reads on every theme. */
export const FROST = "rgb(143 209 255)";

export function ClosetStreak({ store }: { store: ClosetStore }) {
  useStore(store);
  const streak = store.streak;
  return (
    <div className="closet-section closet-streak">
      <StreakSummary streak={streak} />
      <ClosetStreakStrip days={streak.recentDays(7)} />
      <span className="closet-spacer-v" />
      <StreakFooter store={store} streak={streak} />
    </div>
  );
}

function status(streak: StudyStreak): string {
  if (streak.studiedToday) return tr("Studied today");
  if (streak.isActive) return tr("Focus today to keep it going");
  return tr("Focus %lld min to start one", PetMilestoneProgress.minutesForStudyDay);
}

function StreakSummary({ streak }: { streak: StudyStreak }) {
  return (
    <div className="closet-streak-summary">
      <span className="kit-metric" style={{ color: streak.isActive ? "var(--primary-text)" : "var(--tertiary-text)" }}>
        {streak.length}
      </span>
      <span className="kit-body-emphasis kit-secondary">{streak.length === 1 ? tr("day") : tr("days")}</span>
      <MarqueeText text={status(streak)} className="kit-caption kit-tertiary closet-streak-status" />
    </div>
  );
}

/** The last days, oldest first: a filled dot for a study day, a snowflake for a frozen one, a faint ring for a miss, and a dashed ring for today while it is still open. */
function ClosetStreakStrip({ days }: { days: readonly StreakDay[] }) {
  const initials = weekdayInitials();
  return (
    <div className="closet-streak-strip">
      {days.map((day, index) => (
        <Tooltip key={day.day} text={dayHelp(day)}>
          <div className="closet-streak-day" data-last={index === days.length - 1 || undefined}>
            <StreakMark state={day.state} />
            <span className="kit-caption closet-streak-letter">{initials[weekdayOf(day.day) - 1]}</span>
          </div>
        </Tooltip>
      ))}
    </div>
  );
}

function dayHelp(day: StreakDay): string {
  const date = dayLongTitle(day.day);
  switch (day.state) {
    case "studied":
      return `${date}: ${tr("studied")}`;
    case "frozen":
      return `${date}: ${tr("missed, a streak freeze kept the streak")}`;
    case "missed":
      return `${date}: ${tr("no study")}`;
    case "today":
      return tr("Today: no study yet");
  }
}

function StreakMark({ state }: { state: StreakDay["state"] }) {
  switch (state) {
    case "studied":
      return (
        <span className="closet-streak-mark closet-streak-studied">
          <Icon id="checkmark" size={10} fixedDirection />
        </span>
      );
    case "frozen":
      return (
        <span className="closet-streak-mark closet-streak-frozen" style={{ color: FROST }}>
          <Icon id="snowflake" size={11} />
        </span>
      );
    case "missed":
      return <span className="closet-streak-mark closet-streak-missed" />;
    case "today":
      return (
        <span className="closet-streak-mark closet-streak-today">
          <svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
            <circle cx="12" cy="12" r="11.25" fill="none" stroke="var(--accent)" strokeOpacity="0.7" strokeWidth="1.5" strokeDasharray="3 2.5" />
          </svg>
        </span>
      );
  }
}

function freezes(streak: StudyStreak, short: boolean): string {
  const free = streak.freeFreezeAvailable ? (short ? tr("1 free") : tr("1 free this week")) : short ? tr("Free used") : tr("Free freeze used");
  if (streak.extraFreezes <= 0) return free;
  return tr("%@, %lld extra", free, streak.extraFreezes);
}

function StreakFooter({ store, streak }: { store: ClosetStore; streak: StudyStreak }) {
  const row = useRef<HTMLDivElement>(null);
  const { width } = useElementSize(row);
  const help = joinSentences([
    tr("A missed day uses a freeze, so the streak keeps going."),
    tr("You get one free freeze each week, and can hold %lld extra.", StreakFreezeRules.maxHeld),
  ]);
  const long = freezes(streak, false);
  const buttonWidth = 2 * 10 + textWidth(tr("Buy freeze"), 10.5, 500) + 4 + 8 + 2 + textWidth(String(StreakFreezeRules.price()), 10.5, 500);
  const fitsLong = width === 0 || 10 + 4 + textWidth(long, 10.5, 500) + 8 + buttonWidth <= width;
  return (
    <div ref={row} className="closet-streak-footer">
      <Icon id="snowflake" size={10} style={{ color: streak.freezesReady > 0 ? FROST : "var(--tertiary-text)" }} />
      <Tooltip text={help}>
        <span className="closet-streak-freezes kit-caption kit-secondary">
          {fitsLong ? <span>{long}</span> : <MarqueeText text={freezes(streak, true)} help={help} />}
        </span>
      </Tooltip>
      <span className="closet-spacer" />
      <ClosetBuyFreezeButton streak={streak} balance={store.closet.balance} onClick={() => store.buyStreakFreeze()} />
    </div>
  );
}

/** Buys an extra streak freeze for its price in points. Disabled, with a tooltip that says why, when the points are short or the most extras are already held. */
function ClosetBuyFreezeButton({ streak, balance, onClick }: { streak: StudyStreak; balance: number; onClick: () => void }) {
  const price = StreakFreezeRules.price();
  const enabled = streak.canBuyFreeze && balance >= price;
  const missing = price - balance;
  const help = !streak.canBuyFreeze
    ? tr("You hold %lld extra freezes, the most at once", StreakFreezeRules.maxHeld)
    : missing > 0
      ? tr("An extra freeze costs %lld points: %lld more, %@ at a typical study pace", price, missing, PetEconomy.studyToEarn(missing))
      : tr("Buy an extra freeze for %lld points. It protects a missed day once this week's free freeze is used.", price);
  return (
    <Tooltip text={help}>
      <button type="button" className="closet-buy-freeze kit-caption" disabled={!enabled} onClick={onClick}>
        <span>{tr("Buy freeze")}</span>
        <span className="closet-buy-freeze-price">
          <Icon id="star.fill" size={8} />
          <span>{price}</span>
        </span>
      </button>
    </Tooltip>
  );
}
