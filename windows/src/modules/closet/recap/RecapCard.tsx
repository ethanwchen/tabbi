/*
 * Port of RecapCard and RecapViews: the weekly recap card, the pet in its
 * current outfit beside the week's hours focused, a bar per day, the other
 * numbers that week had and one warm line, designed for the open island's
 * panel canvas; and the takeover that fills the island with it: "Your week"
 * in the header, the share button and Done on the right.
 */

import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import type { NotchTakeover } from "../../../app/takeover";
import { durationMinutes } from "../../../core/formatting/durationFormat";
import { currentLanguage, tr } from "../../../core/localization/tr";
import type { PetProfile } from "../../../core/pets/petProfile";
import { recapDayInitials, recapStats, recapWeekTitle, type RecapStat } from "../../../core/recap/recapStats";
import { RECAP_SHARE_FORMATS, recapShareTitle, type RecapShareFormat } from "../../../core/recap/recapShareFormat";
import { recapCheerLine, type RecapCheer, type WeeklyRecap } from "../../../core/recap/weeklyRecap";
import { Card } from "../../../ui/kit/Card";
import { useTheme } from "../../../ui/kit/context";
import { accentVariables } from "../../../ui/kit/tokens";
import { CLOSET_ACCENT } from "../closetDescriptor";
import { Icon } from "../../../ui/kit/Icon";
import { IconButton } from "../../../ui/kit/IconButton";
import { MarqueeText } from "../../../ui/kit/MarqueeText";
import { PetPlayer } from "../../../ui/kit/petPlayer";
import { PetView } from "../../../ui/kit/PetView";
import { Tooltip } from "../../../ui/kit/Tooltip";
import { textWidth } from "../../../ui/shell/measure";
import { useElementSize } from "../useElementSize";
import "./recap.css";

export interface RecapCardProps {
  readonly recap: WeeklyRecap;
  readonly cheer: RecapCheer;
  /** The user's pet as it looks now; undefined when the pet is turned off. */
  readonly pet: PetProfile | undefined;
  readonly timeZone: string;
  /** Demo runs leave out the week's dates, so store screenshots never show a date (the header already says "Your week"). */
  readonly showsWeekDates: boolean;
}

/** The recap's warm gold (the Closet's accent) as the `--accent` pair, since the takeover sits outside any module's panel. */
function RecapAccent({ className, children }: { className: string; children: ReactNode }) {
  const theme = useTheme();
  return (
    <span className={className} style={accentVariables(theme, CLOSET_ACCENT) as CSSProperties}>
      {children}
    </span>
  );
}

export function RecapCard({ recap, cheer, pet, timeZone, showsWeekDates }: RecapCardProps) {
  const locale = currentLanguage();
  const theme = useTheme();
  const stats = useMemo(() => recapStats(recap, locale), [recap, locale]);
  return (
    <div className="recap-card" role="group" aria-label={tr("Your week")} style={accentVariables(theme, CLOSET_ACCENT) as CSSProperties}>
      <RecapPetBadge pet={pet} week={showsWeekDates ? recapWeekTitle(recap.week, locale, timeZone) : undefined} />
      <Card className="recap-body">
        <div className="recap-cheer kit-title">
          <MarqueeText text={recapCheerLine(cheer)} />
        </div>
        <span className="recap-fill" />
        <div className="recap-hero">
          <div className="recap-hours">
            <span className="kit-metric recap-hours-value">{durationMinutes(recap.focusMinutes)}</span>
            <span className="kit-caption kit-tertiary">{tr("focused")}</span>
          </div>
          <span className="recap-fill" />
          <RecapDayBars recap={recap} locale={locale} />
        </div>
        <span className="recap-fill" />
        <RecapStatsRow stats={stats} />
      </Card>
    </div>
  );
}

/** The pet, standing still in its outfit, above the week's dates (if any). */
function RecapPetBadge({ pet, week }: { pet: PetProfile | undefined; week: string | undefined }) {
  return (
    <Card padding={8} className="recap-pet-card">
      <div className="recap-pet-body">
        {pet !== undefined ? (
          <RecapPet profile={pet} />
        ) : (
          <span className="recap-sparkles">
            <Icon id="sparkles" size={28} />
          </span>
        )}
        {pet !== undefined && <span className="kit-body-emphasis recap-pet-name kit-user-text">{pet.name}</span>}
        {week !== undefined && <span className="kit-caption kit-tertiary recap-pet-week">{week}</span>}
      </div>
    </Card>
  );
}

/** The pet, awake and still (64 px at the default pixel size), so the card and its exported image match. A fixed seed keeps snapshots stable. */
export function RecapPet({ profile, pixelSize = 2 }: { profile: PetProfile; pixelSize?: number }) {
  const player = useMemo(() => new PetPlayer(profile, { seed: 7 }), [profile]);
  return <PetView player={player} pixelSize={pixelSize} />;
}

export interface RecapDayBarsProps {
  readonly recap: WeeklyRecap;
  readonly locale: string;
  readonly barWidth?: number;
  readonly maxHeight?: number;
  readonly spacing?: number;
}

/** Scaled to the week's best day; an empty day is a small stub. */
export function barHeight(minutes: number, best: number, maxHeight: number): number {
  if (!(best > 0) || !(minutes > 0)) return 4;
  return Math.max(6, (maxHeight * minutes) / best);
}

/** One bar per day, Monday first, the best day in full accent. */
export function RecapDayBars({ recap, locale, barWidth = 10, maxHeight = 40, spacing = 8 }: RecapDayBarsProps) {
  const initials = recapDayInitials(locale);
  const best = Math.max(0, ...recap.minutesByDay);
  return (
    <div className="recap-bars" style={{ gap: spacing }}>
      {recap.minutesByDay.map((minutes, index) => {
        /* Days tied for the best all light up. */
        const isBest = best > 0 && minutes === best;
        return (
          <Tooltip key={index} text={durationMinutes(minutes)}>
            <div className="recap-bar-column">
              <span
                className="recap-bar"
                style={{
                  width: barWidth,
                  height: barHeight(minutes, best, maxHeight),
                  background: isBest ? "var(--accent)" : minutes > 0 ? "color-mix(in srgb, var(--accent) 40%, transparent)" : "var(--stroke)",
                }}
              />
              <span className="recap-bar-initial" style={{ color: isBest ? "var(--secondary-text)" : "var(--tertiary-text)" }}>
                {initials[index]}
              </span>
            </div>
          </Tooltip>
        );
      })}
    </div>
  );
}

/** The week's other numbers side by side, dropping the last ones on a narrow panel rather than squeezing them. */
function RecapStatsRow({ stats }: { stats: readonly RecapStat[] }) {
  const row = useRef<HTMLDivElement>(null);
  const { width } = useElementSize(row);
  const shown = useMemo(() => {
    if (width === 0) return stats;
    for (let count = stats.length; count >= 1; count--) {
      const parts = stats.slice(0, count);
      const total = parts.reduce((sum, stat) => sum + Math.max(textWidth(stat.value, 13, 600), textWidth(stat.label, 10.5, 500)), 0) + 12 * (count - 1);
      if (total <= width) return parts;
    }
    return stats.slice(0, 1);
  }, [stats, width]);
  return (
    <div ref={row} className="recap-stats">
      {shown.map((stat) => (
        <div key={stat.kind} className="recap-stat">
          <span className="kit-metric-small">{stat.value}</span>
          <span className="kit-caption kit-tertiary">{stat.label}</span>
        </div>
      ))}
    </div>
  );
}

/* The takeover */

export interface RecapTakeoverInput {
  readonly recap: WeeklyRecap;
  readonly cheer: RecapCheer;
  readonly pet: () => PetProfile | undefined;
  readonly timeZone: () => string;
  readonly showsWeekDates: boolean;
  readonly done: () => void;
  /** Exports the image: copies it or saves it, and resolves to the line to show for a moment. */
  readonly share: (format: RecapShareFormat, action: "copy" | "save") => Promise<string | undefined>;
}

/** The recap filling the open island: "Your week" in the header, Share and Done on the right, and the card in the panel canvas. Port of RecapViews.takeover. */
export function recapTakeover(input: RecapTakeoverInput): NotchTakeover {
  return {
    Leading: () => (
      <RecapAccent className="recap-title">
        <Icon id="sparkles" size={11} style={{ color: "var(--accent)" }} />
        <span className="kit-title">{tr("Your week")}</span>
      </RecapAccent>
    ),
    Trailing: () => (
      <RecapAccent className="recap-trailing">
        <RecapShareButton share={input.share} />
        <Tooltip text={tr("Put the recap away")}>
          <button type="button" className="recap-done kit-caption" onClick={input.done}>
            {tr("Done")}
          </button>
        </Tooltip>
      </RecapAccent>
    ),
    Body: () => <RecapCard recap={input.recap} cheer={input.cheer} pet={input.pet()} timeZone={input.timeZone()} showsWeekDates={input.showsWeekDates} />,
  };
}

/** The header's share button: a menu with Copy or Save for each shape of the image, and a line that says what happened. Port of RecapShareButton. */
function RecapShareButton({ share }: { share: RecapTakeoverInput["share"] }) {
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (note === undefined) return;
    const timer = window.setTimeout(() => setNote(undefined), 2500);
    return () => window.clearTimeout(timer);
  }, [note]);
  const run = (format: RecapShareFormat, action: "copy" | "save") => {
    setOpen(false);
    void share(format, action).then(setNote);
  };
  return (
    <span className="recap-share">
      {note !== undefined && <span className="kit-caption kit-secondary recap-share-note">{note}</span>}
      <IconButton symbol="square.and.arrow.up" size={22} help={tr("Share your week as an image")} selected={open} onClick={() => setOpen((shown) => !shown)} />
      {open && (
        <>
          <div className="recap-menu-backdrop" onClick={() => setOpen(false)} />
          <div className="recap-menu" role="menu">
            {RECAP_SHARE_FORMATS.map((format) => (
              <button key={`copy-${format}`} type="button" role="menuitem" className="recap-menu-row" onClick={() => run(format, "copy")}>
                {tr("Copy %@", recapShareTitle(format))}
              </button>
            ))}
            <span className="recap-menu-separator" />
            {RECAP_SHARE_FORMATS.map((format) => (
              <button key={`save-${format}`} type="button" role="menuitem" className="recap-menu-row" onClick={() => run(format, "save")}>
                {tr("Save %@ to Pictures", recapShareTitle(format))}
              </button>
            ))}
          </div>
        </>
      )}
    </span>
  );
}
