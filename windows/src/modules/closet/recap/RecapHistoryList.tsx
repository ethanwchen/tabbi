/*
 * Port of RecapHistoryList: the past weekly recaps as a tiny list, newest
 * first: each week's dates and hours focused, a star on the best one.
 * Clicking a week shows its card in the open island again. Lives in the
 * Closet beside the pet.
 */

import { useStore } from "../../../app/useStore";
import { durationMinutes } from "../../../core/formatting/durationFormat";
import { currentLanguage, tr } from "../../../core/localization/tr";
import { recapWeekTitle } from "../../../core/recap/recapStats";
import type { WeeklyRecap } from "../../../core/recap/weeklyRecap";
import { EdgeFade } from "../../../ui/kit/EdgeFade";
import { Icon } from "../../../ui/kit/Icon";
import { Tooltip } from "../../../ui/kit/Tooltip";
import type { RecapStore } from "./recapStore";
import "./recap.css";

export function RecapHistoryList({ store, timeZone }: { store: RecapStore; timeZone?: string }) {
  const archive = useStore(store, (state) => state.archive);
  const recaps = archive.recaps;
  const zone = timeZone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (recaps.length === 0) return <RecapHistoryEmpty />;
  const best = Math.max(0, ...recaps.map((recap) => recap.focusMinutes));
  return (
    <EdgeFade edge="bottom" className="recap-history-fade">
      <div className="recap-history-scroll">
        {recaps.map((recap) => (
          <RecapHistoryRow key={recap.week} recap={recap} timeZone={zone} isBest={recaps.length > 1 && best > 0 && recap.focusMinutes === best} onClick={() => store.reopen(recap)} />
        ))}
      </div>
    </EdgeFade>
  );
}

/** One past week: its dates, its hours focused and a chevron to open it. */
function RecapHistoryRow({ recap, timeZone, isBest, onClick }: { recap: WeeklyRecap; timeZone: string; isBest: boolean; onClick: () => void }) {
  const title = recapWeekTitle(recap.week, currentLanguage(), timeZone);
  return (
    <Tooltip text={tr("Open your recap for %@", title)}>
      <button type="button" className="recap-history-row" onClick={onClick}>
        <span className="kit-body-emphasis recap-history-title">{title}</span>
        {isBest && (
          <Tooltip text={tr("Your best week")}>
            <span className="recap-history-star">
              <Icon id="star.fill" size={9} />
            </span>
          </Tooltip>
        )}
        <span className="closet-spacer" />
        <span className="kit-caption kit-secondary recap-history-minutes">{durationMinutes(recap.focusMinutes)}</span>
        <Icon id="chevron.forward" size={9} className="recap-history-chevron" />
      </button>
    </Tooltip>
  );
}

/** Before the first Sunday evening: what will show up here, and when. */
function RecapHistoryEmpty() {
  return (
    <div className="recap-history-empty">
      <Icon id="calendar" size={18} style={{ color: "var(--accent)" }} />
      <span className="kit-body-emphasis kit-secondary">{tr("Your first recap arrives Sunday evening.")}</span>
      <span className="kit-caption kit-tertiary">{tr("Each week you focus shows up here.")}</span>
    </div>
  );
}
