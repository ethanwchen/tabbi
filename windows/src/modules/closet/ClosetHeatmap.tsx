/*
 * Port of ClosetHeatmap: the Closet's first section, a GitHub-style chart
 * of the days studied (`StudyHeatmap`), a column per week ending with today,
 * with the last 30 days' total and the streak above it and a "More ... Less"
 * key beside it. The panel is wide but short, so everything but the chart
 * shares one row or sits to its side, leaving the squares the height to
 * reach GitHub's size. Hovering a day swaps the total for that day's date
 * and time studied, at once and in place, so nothing flickers or clips.
 */

import { useMemo, useRef, useState, type CSSProperties, type PointerEvent, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { HEATMAP_LABELED_WEEKDAYS, HEATMAP_LEVEL_COUNT, HEATMAP_LEVEL_THRESHOLDS, heatmapDayLabel, heatmapLevel, StudyHeatmap, weekMinutes, weekStudiedDays, type HeatmapDay, type HeatmapWeek } from "../../core/closet/studyHeatmap";
import { PetMilestoneProgress } from "../../core/closet/petLimited";
import { durationMinutes } from "../../core/formatting/durationFormat";
import { tr } from "../../core/localization/tr";
import type { StudyStreak } from "../../core/streaks/studyStreak";
import { Icon } from "../../ui/kit/Icon";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useKit } from "../../ui/kit/context";
import { staggerDelay } from "../../ui/kit/motion";
import { textWidth } from "../../ui/shell/measure";
import { dayTitle, monthDayLong, monthShort, weekdayShortNames } from "./closetFormat";
import type { ClosetStore } from "./closetStore";
import { useElementSize } from "./useElementSize";

/* GitHub's gap, as a share of a cell (3 points beside a 10 point square). */
const GAP_RATIO = 0.3;
/* The largest cell, so the tallest panel still reads as GitHub's chart rather than a board of tiles. */
const MAX_CELL = 14;
/* The month names' row, and the space below it. */
const MONTH_ROW = 10;
const MONTH_GAP = 3;
/* The weekday names' column, and the space beside it; left out when they would cost more than a few weeks. */
const WEEKDAY_COLUMN = 20;
const WEEKDAY_GAP = 4;
const LEGEND_CELL = 8;

/** The shades: a faint square for no study, then four steps of the Closet's warm amber. */
export function heatmapColor(level: number): string {
  if (level <= 0) return "color-mix(in srgb, var(--primary-text) 7%, transparent)";
  if (level === 1) return "color-mix(in srgb, var(--accent) 28%, transparent)";
  if (level === 2) return "color-mix(in srgb, var(--accent) 50%, transparent)";
  if (level === 3) return "color-mix(in srgb, var(--accent) 75%, transparent)";
  return "var(--accent)";
}

export function ClosetHeatmapSection({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const [hovered, setHovered] = useState<HeatmapDay | undefined>(undefined);
  const summary = useMemo(() => new StudyHeatmap(state.milestones.minutesByDay, 1, store.now(), store.calendar), [state, store]);
  return (
    <div className="closet-heatmap-section">
      <HeatmapHeader summary={summary} streak={store.streak} hovered={hovered} />
      <div className="closet-heatmap-row">
        <ClosetHeatmapGrid store={store} hovered={hovered} onHover={setHovered} animatesIn={!store.isSnapshot} />
        <ClosetHeatmapLegend />
      </div>
    </div>
  );
}

function HeatmapHeader({ summary, streak, hovered }: { summary: StudyHeatmap; streak: StudyStreak; hovered: HeatmapDay | undefined }) {
  const row = useRef<HTMLDivElement>(null);
  const { width } = useElementSize(row);
  const help = hovered === undefined && summary.bestDay !== undefined
    ? `${tr("Best day %@", durationMinutes(summary.bestDay.minutes))} · ${tr("Your most studied day: %@", dayTitle(summary.bestDay.key, true))}`
    : "";
  let content: ReactNode;
  if (hovered !== undefined) {
    content = (
      <>
        <span className="kit-body-emphasis closet-heatmap-date">{dayTitle(hovered.key)}</span>
        <span className={`kit-caption ${hovered.minutes > 0 ? "kit-secondary" : "kit-tertiary"}`}>{heatmapDayLabel(hovered)}</span>
        <span className="closet-spacer" />
        <StreakLabel streak={streak} short={false} />
      </>
    );
  } else if (summary.bestDay === undefined) {
    const long = tr("Every focused minute fills in today's square");
    const shortText = tr("Focus to fill in today's square");
    const streakWidth = streakLabelWidth(streak, false);
    const fitsLong = width === 0 || textWidth(long, 12, 500) + 4 + streakWidth <= width;
    content = (
      <>
        <span className="kit-body-emphasis kit-secondary closet-heatmap-empty">{fitsLong ? long : shortText}</span>
        <span className="closet-spacer" />
        <StreakLabel streak={streak} short={false} />
      </>
    );
  } else {
    /* Longer languages would cut the caption off, so the streak first shortens to its flame and count, and only then does the caption step aside. */
    const total = durationMinutes(summary.lastThirtyDaysMinutes);
    const caption = tr("in the last 30 days");
    const totalWidth = textWidth(total, 12, 500);
    const captionWidth = 4 + textWidth(caption, 10.5, 500);
    const fits = (withCaption: boolean, short: boolean) => width === 0 || totalWidth + (withCaption ? captionWidth : 0) + 8 + streakLabelWidth(streak, short) <= width;
    const variant = fits(true, false) ? { caption: true, short: false } : fits(true, true) ? { caption: true, short: true } : { caption: false, short: false };
    content = (
      <>
        <span className="kit-body-emphasis closet-heatmap-total">{total}</span>
        {variant.caption && <span className="kit-caption kit-secondary">{caption}</span>}
        <span className="closet-spacer" />
        <StreakLabel streak={streak} short={variant.short} />
      </>
    );
  }
  return (
    <Tooltip text={help}>
      <div ref={row} className="closet-heatmap-header" role="status">
        {content}
      </div>
    </Tooltip>
  );
}

function streakText(streak: StudyStreak): string {
  return streak.isActive ? tr("%lld-day streak", streak.length) : tr("No streak yet");
}

function streakLabelWidth(streak: StudyStreak, short: boolean): number {
  const text = short && streak.isActive ? String(streak.length) : streakText(streak);
  return 10 + 4 + textWidth(text, 10.5, 500);
}

/** The streak with its flame; `short` keeps only the count, for the rare row too narrow for the words (the tooltip still says them). */
function StreakLabel({ streak, short }: { streak: StudyStreak; short: boolean }) {
  return (
    <Tooltip text={tr("Your study streak: days in a row with at least %lld focused minutes", PetMilestoneProgress.minutesForStudyDay)}>
      <span className="closet-streak-label kit-caption kit-secondary">
        <Icon id="flame.fill" size={10} style={{ color: streak.isActive ? "var(--accent)" : "var(--tertiary-text)" }} />
        <span>{short && streak.isActive ? String(streak.length) : streakText(streak)}</span>
      </span>
    </Tooltip>
  );
}

interface Metrics {
  readonly cell: number;
  readonly gap: number;
}

/**
 * The chart, laid out like GitHub's: squares a little taller than the
 * labels with gaps three tenths of a square, month names over the columns
 * where a month starts and Monday, Wednesday and Friday beside their rows.
 * The squares take all the height there is, up to GitHub's proportions at
 * most, and as many weeks as fit the width follow. Each column fades in a
 * moment after the one before it when the section appears, still under
 * Reduce Motion.
 */
function ClosetHeatmapGrid({ store, hovered, onHover, animatesIn }: { store: ClosetStore; hovered: HeatmapDay | undefined; onHover: (day: HeatmapDay | undefined) => void; animatesIn: boolean }) {
  const state = useStore(store);
  const { reduceMotion, pace, still } = useKit();
  const frame = useRef<HTMLDivElement>(null);
  const size = useElementSize(frame);
  const cell = Math.min(MAX_CELL, Math.max(4, Math.floor((size.height - MONTH_ROW - MONTH_GAP) / (7 + 6 * GAP_RATIO))));
  const gap = Math.max(2, Math.round(cell * GAP_RATIO));
  const showsWeekdays = size.width >= 240;
  const gridWidth = size.width - (showsWeekdays ? WEEKDAY_COLUMN + WEEKDAY_GAP : 0);
  const count = Math.max(1, Math.floor((gridWidth + gap) / (cell + gap)));
  const metrics: Metrics = { cell, gap };
  const heatmap = useMemo(() => new StudyHeatmap(state.milestones.minutesByDay, count, store.now(), store.calendar), [state, count, store]);
  const pitch = cell + gap;
  const weekdays = weekdayShortNames();
  const animated = animatesIn && !still && !reduceMotion;

  /* The day under the pointer, from one hover area over the whole grid, so moving between cells never flickers through "no day". */
  const onMove = (event: PointerEvent<HTMLDivElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
    const x = rtl ? bounds.right - event.clientX : event.clientX - bounds.left;
    const y = event.clientY - bounds.top;
    const column = Math.floor(x / pitch);
    const row = Math.floor(y / pitch);
    if (x < 0 || y < 0 || column >= heatmap.weeks.length || row > 6) return;
    const day = heatmap.weeks[column]?.days[row];
    if (day !== undefined) onHover(day);
  };

  return (
    <div ref={frame} className="closet-heatmap-frame">
      {size.height > 0 && (
        <div className="closet-heatmap-layout" style={{ gap: WEEKDAY_GAP }}>
          {showsWeekdays && (
            <div className="closet-heatmap-weekdays" style={{ paddingTop: MONTH_ROW + MONTH_GAP, width: WEEKDAY_COLUMN }} aria-hidden="true">
              {heatmap.weekdays.map((weekday, index) => (
                <span key={index} style={{ height: pitch, lineHeight: `${pitch}px` }}>
                  {HEATMAP_LABELED_WEEKDAYS.has(weekday) ? weekdays[weekday - 1] : ""}
                </span>
              ))}
            </div>
          )}
          <div className="closet-heatmap-columns" style={{ gap: MONTH_GAP }}>
            <div className="closet-heatmap-months" style={{ height: MONTH_ROW, width: heatmap.weeks.length * pitch - gap }} aria-hidden="true">
              {heatmap.monthLabels(Math.ceil(26 / pitch)).map((label) => (
                <span key={label.week} style={{ insetInlineStart: label.week * pitch }}>
                  {monthShort(label.start)}
                </span>
              ))}
            </div>
            <div className="closet-heatmap-cells" style={{ gap }} onPointerMove={onMove} onPointerLeave={() => onHover(undefined)}>
              {heatmap.weeks.map((week, index) => (
                <HeatmapColumn
                  key={week.start}
                  week={week}
                  metrics={metrics}
                  hovered={hovered}
                  style={animated ? { animation: `closet-column-in var(--content-fade-in) ease-out ${staggerDelay(index, reduceMotion, pace) / 3}ms both` } : undefined}
                />
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function weekLabel(week: HeatmapWeek): string {
  const start = monthDayLong(week.start);
  const minutes = weekMinutes(week);
  if (!(minutes > 0)) return tr("Week of %@: no study", start);
  return tr("Week of %@: %@ studied over %@", start, durationMinutes(minutes), tr("%lld days", weekStudiedDays(week)));
}

function HeatmapColumn({ week, metrics, hovered, style }: { week: HeatmapWeek; metrics: Metrics; hovered: HeatmapDay | undefined; style: CSSProperties | undefined }) {
  return (
    <div className="closet-heatmap-column" style={{ gap: metrics.gap, ...style }} role="img" aria-label={weekLabel(week)}>
      {week.days.map((day, row) =>
        day === undefined ? (
          <span key={row} style={{ width: metrics.cell, height: metrics.cell }} />
        ) : (
          <HeatmapCell key={row} day={day} size={metrics.cell} isHovered={hovered?.key === day.key} />
        ),
      )}
    </div>
  );
}

/** One day's square, shaded by its level, outlined while hovered and, more faintly, when it is today. Today moving up a level after a session swells once. */
function HeatmapCell({ day, size, isHovered }: { day: HeatmapDay; size: number; isHovered: boolean }) {
  const level = heatmapLevel(day.minutes);
  const [seen, setSeen] = useState(level);
  const { reduceMotion, still } = useKit();
  const swell = day.isToday && level > seen && !reduceMotion && !still;
  if (level !== seen && !swell) setSeen(level);
  return (
    <span
      className="closet-heatmap-cell"
      data-today={day.isToday || undefined}
      data-hovered={isHovered || undefined}
      data-swell={swell || undefined}
      onAnimationEnd={() => setSeen(level)}
      style={{ width: size, height: size, borderRadius: Math.min(2, size * 0.25), background: heatmapColor(level) }}
    />
  );
}

/** GitHub's "Less ... More" key, stood on end beside the chart. Port of ClosetHeatmapLegend. */
function ClosetHeatmapLegend() {
  const [first = 15, second = 45, third = 90] = HEATMAP_LEVEL_THRESHOLDS;
  const help = tr("No study, under %lld min, under %lld min, under %lld min, and %lld min or more", first, second, third, third);
  return (
    <Tooltip text={help}>
      <div className="closet-heatmap-legend" style={{ paddingTop: MONTH_ROW + MONTH_GAP }} role="img" aria-label={tr("Darker squares mean more time studied")}>
        <span className="closet-heatmap-legend-more">{tr("More")}</span>
        {Array.from({ length: HEATMAP_LEVEL_COUNT }, (_, index) => HEATMAP_LEVEL_COUNT - 1 - index).map((level) => (
          <span key={level} className="closet-heatmap-legend-cell" style={{ width: LEGEND_CELL, height: LEGEND_CELL, background: heatmapColor(level) }} />
        ))}
        <span className="closet-heatmap-legend-less">{tr("Less")}</span>
      </div>
    </Tooltip>
  );
}
