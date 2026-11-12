/*
 * Port of ClosetLevelCard: the Study Level at the top of the Goals
 * section. The rank's emblem, the level and rank, a bar toward the next
 * level ("230 of 242 h to Level 13"), the next unlock, and the nameplate
 * colors to pick from (locked ones dimmed until their level). Calm on
 * purpose: the level only ever grows, and it pays no points.
 */

import { useStore } from "../../app/useStore";
import { joinSentences } from "../../core/formatting/sentences";
import { tr } from "../../core/localization/tr";
import {
  NAMEPLATES,
  hoursToReach,
  levelFraction,
  levelLabel,
  nameplateName,
  nameplateUnlockLevel,
  nextNameplate,
  unlockedNameplates,
  nextRank,
  rankFirstLevel,
  rankForLevel,
  rankName,
  standingHelp,
  type Nameplate,
} from "../../core/progression/studyLevel";
import { StudyRankEmblem, VariantsThatFit, nameplateTint } from "../../ui/kit/StudyLevel";
import { TextThatFits } from "../../ui/kit/TextThatFits";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { ClosetStore } from "./closetStore";

/** The dot rows the picker tries, as the Mac's ViewThatFits: dot size and gap in px, and whether only the reachable colors show. */
const DOT_LAYOUTS = [
  { size: 10, gap: 4, reachableOnly: false },
  { size: 10, gap: 2, reachableOnly: false },
  { size: 8, gap: 2, reachableOnly: false },
  { size: 8, gap: 2, reachableOnly: true },
] as const;

export function ClosetLevelCard({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const progression = state.progression;
  const level = progression.studyLevel;
  const rank = rankForLevel(level);
  const minutes = progression.focusMinutes;
  const hoursDone = Math.trunc(minutes / 60);
  const hoursGoal = hoursToReach(level + 1);

  /* The next thing a level brings: a rank, or else a nameplate color, whichever comes first (the rank when both come together). */
  const upcomingRank = nextRank(rank);
  const upcomingColor = nextNameplate(level);
  const next =
    upcomingColor !== undefined && nameplateUnlockLevel(upcomingColor) < rankFirstLevel(upcomingRank)
      ? { level: nameplateUnlockLevel(upcomingColor), name: tr("%@ name color", nameplateName(upcomingColor)) }
      : { level: rankFirstLevel(upcomingRank), name: rankName(upcomingRank) };

  const help = joinSentences([
    standingHelp(progression.standing),
    tr("Your Study Level grows with every hour you focus and never goes down."),
    tr("Every 5 levels bring a name color and every 10 a new rank. Levels never give points."),
  ]);

  return (
    <Tooltip text={help}>
      <div className="closet-level-card">
        <span className="closet-level-emblem">
          <StudyRankEmblem rank={rank} pixelSize={1.5} />
        </span>
        <div className="closet-level-text">
          <div className="closet-level-title-row">
            <span className="closet-level-title">
              <span className="closet-level-level">{levelLabel(level)}</span>
              <span className="kit-secondary">{`  ${rankName(rank)}`}</span>
            </span>
            <TextThatFits
              className="closet-level-next kit-caption kit-tertiary"
              candidates={[tr("Next: %@ at Lv %lld", next.name, next.level), tr("Lv %lld: %@", next.level, next.name), ""]}
            />
          </div>
          <div className="closet-level-progress-row">
            <span className="closet-level-bar">
              <span style={{ width: `${levelFraction(level, minutes) * 100}%` }} />
            </span>
            <TextThatFits
              className="closet-level-hours kit-caption kit-secondary"
              candidates={[tr("%lld of %lld h to Level %lld", hoursDone, hoursGoal, level + 1), tr("%lld/%lld h", hoursDone, hoursGoal)]}
            />
          </div>
          {/*
           * All thirteen where they fit; then closer and smaller; and in the
           * narrowest card the unlocked ones and the next, so no dot is ever
           * pushed out of the card. Port of ClosetNameplatePicker.
           */}
          <VariantsThatFit
            count={DOT_LAYOUTS.length}
            fitKey={`${level}|${progression.nameplate}`}
            render={(index) => {
              const layout = DOT_LAYOUTS[index] ?? DOT_LAYOUTS[DOT_LAYOUTS.length - 1];
              const upcoming = nextNameplate(level);
              const shown = layout?.reachableOnly ? [...unlockedNameplates(level), ...(upcoming === undefined ? [] : [upcoming])] : NAMEPLATES;
              return (
                <div className="closet-nameplates" style={{ gap: layout?.gap, ["--dot-size" as string]: `${layout?.size ?? 10}px` }}>
                  {shown.map((nameplate) => (
                    <ClosetNameplateDot
                      key={nameplate}
                      nameplate={nameplate}
                      isUnlocked={nameplateUnlockLevel(nameplate) <= level}
                      isPicked={progression.nameplate === nameplate}
                      onPick={() => store.pickNameplate(nameplate)}
                    />
                  ))}
                </div>
              );
            }}
          />
        </div>
      </div>
    </Tooltip>
  );
}

function ClosetNameplateDot({ nameplate, isUnlocked, isPicked, onPick }: { nameplate: Nameplate; isUnlocked: boolean; isPicked: boolean; onPick: () => void }) {
  const help = isUnlocked
    ? tr("%@ name color", nameplateName(nameplate))
    : tr("%@ name color, unlocks at Level %lld", nameplateName(nameplate), nameplateUnlockLevel(nameplate));
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className="closet-nameplate-dot"
        data-locked={!isUnlocked || undefined}
        data-picked={isPicked || undefined}
        aria-label={help}
        aria-pressed={isPicked}
        onClick={onPick}
        style={{ ["--nameplate" as string]: nameplateTint(nameplate) }}
      >
        <span />
      </button>
    </Tooltip>
  );
}
