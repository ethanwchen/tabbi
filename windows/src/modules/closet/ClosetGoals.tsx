/*
 * Port of ClosetGoals: the Closet's Goals section, with this month's quests,
 * the mastery outfits (earned from badge tiers, never sold) and the badge
 * collection. Like the Wardrobe and Limited sections it scrolls and fades
 * out at the bottom, and the footer details what the pointer rests on.
 */

import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { PetCloset, stateIsOwned, type PetClosetItemState } from "../../core/closet/petCloset";
import { editionMasteryBadge, limitedEditionOf, limitedProgressFraction, type PetLimitedProgress } from "../../core/closet/petLimited";
import { joinSentences } from "../../core/formatting/sentences";
import { tr } from "../../core/localization/tr";
import { itemDisplayName, type PetItem } from "../../core/pets/petItem";
import type { PetProfile } from "../../core/pets/petProfile";
import { BADGE_LARGE_PIXEL_SIZE, BADGE_REGULAR_PIXEL_SIZE, BADGE_SIZE, BADGE_TWINKLE_SECONDS, badgeBitmap, badgeScale, badgeState } from "../../core/progression/badgeArt";
import { BADGE_COUNT, type PetProgression } from "../../core/progression/petProgression";
import {
  monthAt,
  monthFirstDay,
  nextMonth,
  questFraction,
  questIsDone,
  questLabel,
  questTitle,
  type MonthlyQuestProgress,
} from "../../core/progression/monthlyQuests";
import {
  PROGRESS_TIERS,
  PROGRESS_TRACKS,
  badgeDisplayName,
  badgeHowToEarn,
  badgeID,
  howToReach,
  tierDisplayName,
  trackDisplayName,
  trackGoal,
  type ProgressBadge,
  type ProgressTier,
  type ProgressTrack,
} from "../../core/progression/progressTrack";
import { useKit } from "../../ui/kit/context";
import { Icon } from "../../ui/kit/Icon";
import { ProgressRing } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { PetSprite } from "../../ui/kit/PetView";
import { Tooltip } from "../../ui/kit/Tooltip";
import { monthDayShort, monthLong } from "./closetFormat";
import { ClosetFooterDetail } from "./ClosetPanel";
import { ScrollingGrid, TightLabel, thumbnailModel } from "./ClosetWardrobe";
import type { ClosetStore } from "./closetStore";

/** The medallion color of each tier, as the Mac draws it: warm bronze, cool silver, gold and a soft starlight violet. */
export function tierColor(tier: ProgressTier): string {
  switch (tier) {
    case "bronze":
      return "rgb(217 148 92)";
    case "silver":
      return "rgb(199 209 222)";
    case "gold":
      return "rgb(242 194 79)";
    case "starlight":
      return "rgb(189 168 255)";
  }
}

/** The symbol for a track's badge and quests (an SF Symbol name the icon table maps). */
export function trackSymbol(track: ProgressTrack): string {
  switch (track) {
    case "focusHours":
      return "clock.fill";
    case "studyDays":
      return "calendar";
    case "gentleStreak":
      return "flame.fill";
    case "sessions":
      return "timer";
    case "cards":
      return "rectangle.stack.fill";
    case "tasks":
      return "checklist";
    case "breakMoves":
      return "figure.cooldown";
    case "party":
      return "person.2.fill";
    case "methods":
      return "books.vertical.fill";
    case "steadyWeeks":
      return "calendar.badge.checkmark";
    case "water":
      return "drop.fill";
    case "monthlyQuests":
      return "moon.stars.fill";
  }
}

type Hover = { readonly kind: "badge"; readonly track: ProgressTrack } | { readonly kind: "quest"; readonly quest: MonthlyQuestProgress };

export function ClosetGoals({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const [hovered, setHovered] = useState<Hover | undefined>(undefined);
  /* Tiers reached since the section was last open, captured as it appears so they keep their dot while it shows. */
  const [fresh] = useState<ReadonlySet<string>>(() => new Set(store.state.progression.unseen.map(badgeID)));
  useEffect(() => {
    store.markGoalsSeen();
    return () => store.tryOn(undefined);
  }, [store]);
  const progression = state.progression;
  const closet = state.closet;
  const model = thumbnailModel(state.profile);
  const now = store.now();
  const quests = progression.quests(now, store.calendar);
  const month = monthAt(now, store.calendar);

  const hoverOutfit = (item: PetItem, inside: boolean) => {
    if (inside) {
      setHovered(undefined);
      store.tryOn(item);
    } else if (state.tryingOn === item) store.tryOn(undefined);
  };

  const tryingOn = state.tryingOn !== undefined && PetCloset.masteryShelf.includes(state.tryingOn) ? state.tryingOn : undefined;
  const owned = PetCloset.masteryShelf.filter((item) => stateIsOwned(closet.state(item))).length;
  const counts = `${tr("%lld of %lld outfits", owned, PetCloset.masteryShelf.length)} · ${tr("%lld of %lld badges", progression.reachedCount, BADGE_COUNT)}`;
  const shortCounts = `${owned}/${PetCloset.masteryShelf.length} · ${progression.reachedCount}/${BADGE_COUNT}`;

  let footer: ReactNode;
  if (hovered?.kind === "badge") {
    footer = <ClosetFooterDetail name={trackDisplayName(hovered.track)} detail={badgeDetail(hovered.track, progression)} />;
  } else if (hovered?.kind === "quest") {
    footer = (
      <ClosetFooterDetail
        name={questTitle(hovered.quest.quest)}
        detail={questIsDone(hovered.quest) ? tr("Done this month.") : tr("%@ this month.", questLabel(hovered.quest))}
      />
    );
  } else if (tryingOn !== undefined) {
    footer = <ClosetFooterDetail name={itemDisplayName(tryingOn)} detail={outfitDetail(tryingOn, closet.state(tryingOn), progression)} />;
  } else {
    footer = <GoalsCounts counts={counts} shortCounts={shortCounts} />;
  }

  return (
    <div className="closet-section closet-goals" onPointerLeave={() => setHovered(undefined)}>
      <ScrollingGrid store={store}>
        <div className="closet-shelves">
          <ClosetQuestBanner month={monthFirstDay(month)} next={monthFirstDay(nextMonth(month))} quests={quests} onHover={(quest) => setHovered(quest ? { kind: "quest", quest } : undefined)} />
          <div className="closet-shelf">
            <Tooltip text={tr("Mastery outfits: each unlocks with a badge tier, never with points")}>
              <div className="closet-shelf-title">{tr("Outfits to earn")}</div>
            </Tooltip>
            <div className="closet-grid">
              {PetCloset.masteryShelf.map((item) => {
                const edition = limitedEditionOf(item);
                const badge = edition === undefined ? undefined : editionMasteryBadge(edition);
                return (
                  <ClosetGoalTile
                    key={item}
                    item={item}
                    state={closet.state(item)}
                    progress={badge === undefined ? undefined : progression.progress(badge)}
                    badge={badge}
                    isFresh={badge !== undefined && fresh.has(badgeID(badge))}
                    model={model}
                    onClick={() => store.tap(item)}
                    onHover={(inside) => hoverOutfit(item, inside)}
                  />
                );
              })}
            </div>
          </div>
          <div className="closet-shelf">
            <Tooltip text={tr("One badge for each habit, from Bronze to Starlight")}>
              <div className="closet-shelf-title">{tr("Badges")}</div>
            </Tooltip>
            <div className="closet-badges">
              {PROGRESS_TRACKS.map((track) => (
                <ClosetBadgeMedallion
                  key={track}
                  track={track}
                  progression={progression}
                  isFresh={[...fresh].some((id) => id.startsWith(`${track}.`))}
                  still={store.isSnapshot}
                  onHover={(inside) => setHovered(inside ? { kind: "badge", track } : (current) => (current?.kind === "badge" && current.track === track ? undefined : current))}
                />
              ))}
            </div>
          </div>
        </div>
      </ScrollingGrid>
      <div className="closet-footer kit-caption">{footer}</div>
    </div>
  );
}

/* The counts never cut off: the line first drops the words before them, then shortens them to bare numbers. */
function GoalsCounts({ counts, shortCounts }: { counts: string; shortCounts: string }) {
  const row = useRef<HTMLDivElement>(null);
  /* The fullest line is tried first whenever the counts change, and shortened once it measures wider than its room. */
  const [fitted, setFitted] = useState({ key: counts, variant: 0 });
  if (fitted.key !== counts) setFitted({ key: counts, variant: 0 });
  const variant = fitted.variant;
  useLayoutEffect(() => {
    const element = row.current;
    if (!element || variant >= 2) return;
    if (element.scrollWidth > element.clientWidth + 1) setFitted({ key: counts, variant: variant + 1 });
  }, [variant, counts]);
  const lead = tr("Earned by studying, never sold");
  return (
    <Tooltip text={`${lead} ${counts}`}>
      <div ref={row} className="closet-goals-counts">
        {variant === 0 && <span className="kit-secondary">{lead}</span>}
        <span className="kit-tertiary closet-footer-count">{variant === 2 ? shortCounts : counts}</span>
      </div>
    </Tooltip>
  );
}

function outfitDetail(item: PetItem, state: PetClosetItemState, progression: PetProgression): string {
  if (state.kind === "wearing") return tr("Earned. Click to take off.");
  if (state.kind === "owned") return tr("Earned. Click to wear.");
  const edition = limitedEditionOf(item);
  const badge = edition === undefined ? undefined : editionMasteryBadge(edition);
  if (badge === undefined) return "";
  return tr("%@ %@ so far.", badgeHowToEarn(badge), progression.progress(badge).label);
}

/** The footer line for a badge: its tier and what the next asks. */
export function badgeDetail(track: ProgressTrack, progression: PetProgression): string {
  const tier = progression.tier(track);
  const next = progression.nextTier(track);
  if (next === undefined) return tr("Starlight, every tier earned");
  const progress = progression.progress({ track, tier: next });
  if (tier === undefined) return tr("%@ to %@", progress.label, tierDisplayName(next));
  return tr("%@, %@ to %@", tierDisplayName(tier), progress.label, tierDisplayName(next));
}

function badgeHelp(track: ProgressTrack, progression: PetProgression): string {
  const next = progression.nextTier(track);
  if (next === undefined) return tr("%@: Starlight, every tier earned", trackDisplayName(track));
  return joinSentences([tr("%@: %@", trackDisplayName(track), badgeDetail(track, progression)), howToReach(track, trackGoal(track, next))]);
}

/* Quests */

/** This month's three quests: the month, how many are done, the next one to do and a ring for each. */
function ClosetQuestBanner({ month, next, quests, onHover }: { month: string; next: string; quests: MonthlyQuestProgress[]; onHover: (quest: MonthlyQuestProgress | undefined) => void }) {
  const done = quests.filter(questIsDone).length;
  const monthName = monthLong(month);
  const nextQuest = quests.find((quest) => !questIsDone(quest));
  const help = joinSentences([
    tr("Three small goals each month. They are optional, and a month you miss costs nothing."),
    tr("Finish all three to count the month toward the Monthly quests badge."),
  ]);
  /* Each line shortens before it would scroll: the title drops "quests", the next quest its "Next:", then its progress. */
  const titles = [tr("%@ quests", monthName), monthName];
  const lines =
    nextQuest === undefined
      ? [tr("All done. New quests on %@.", monthDayShort(next)), tr("All done")]
      : [
          tr("Next: %@, %@", questTitle(nextQuest.quest), questLabel(nextQuest)),
          tr("%@, %@", questTitle(nextQuest.quest), questLabel(nextQuest)),
          questTitle(nextQuest.quest),
        ];
  return (
    <Tooltip text={help}>
      <div className="closet-event-banner closet-quest-banner">
        <Icon id="moon.stars.fill" size={11} className="closet-event-sparkle" />
        <div className="closet-event-text">
          <div className="closet-event-row closet-quest-title-row">
            <FittingLine options={titles} className="closet-event-name" help={help} />
            <span className="kit-caption kit-tertiary closet-footer-count">{tr("%lld of %lld done", done, quests.length)}</span>
          </div>
          <FittingLine options={lines} className="kit-caption kit-secondary" help={help} />
        </div>
        <div className="closet-quest-rings">
          {quests.map((quest) => (
            <ClosetQuestRing key={quest.quest.track} quest={quest} onHover={onHover} />
          ))}
        </div>
      </div>
    </Tooltip>
  );
}

/** The first of `options` that fits whole; the last one scrolls when none does. */
function FittingLine({ options, className, help }: { options: readonly string[]; className?: string; help: string }) {
  const probe = useRef<HTMLSpanElement>(null);
  const key = options.join("|");
  const [fitted, setFitted] = useState({ key, index: 0 });
  if (fitted.key !== key) setFitted({ key, index: 0 });
  const index = fitted.index;
  useLayoutEffect(() => {
    const element = probe.current;
    if (!element || index >= options.length - 1) return;
    if (element.scrollWidth > element.clientWidth + 1) setFitted({ key, index: index + 1 });
  }, [index, key, options.length]);
  const text = options[index] ?? "";
  if (index >= options.length - 1) return <MarqueeText text={text} help={help} className={["closet-fitting-line", className].filter(Boolean).join(" ")} />;
  return (
    <span ref={probe} className={["closet-fitting-line", className].filter(Boolean).join(" ")}>
      {text}
    </span>
  );
}

/** One quest's ring: its track's symbol inside a ring that fills with this month's progress, filled with a check once done. */
function ClosetQuestRing({ quest, onHover }: { quest: MonthlyQuestProgress; onHover: (quest: MonthlyQuestProgress | undefined) => void }) {
  const title = questTitle(quest.quest);
  const isDone = questIsDone(quest);
  const help = isDone ? tr("%@: done this month", title) : tr("%@: %@ this month", title, questLabel(quest));
  return (
    <Tooltip text={help}>
      <span
        className="closet-quest-ring"
        data-done={isDone || undefined}
        role="img"
        aria-label={`${title}, ${isDone ? tr("Done") : questLabel(quest)}`}
        onPointerEnter={() => onHover(quest)}
        onPointerLeave={() => onHover(undefined)}
      >
        {isDone ? (
          <Icon id="checkmark" size={8} />
        ) : (
          <ProgressRing progress={questFraction(quest)} track="var(--surface-hover)" lineWidth={2} size={20}>
            <Icon id={trackSymbol(quest.quest.track)} size={8} />
          </ProgressRing>
        )}
      </span>
    </Tooltip>
  );
}

/* Outfits */

interface GoalTileProps {
  readonly item: PetItem;
  readonly state: PetClosetItemState;
  readonly progress: PetLimitedProgress | undefined;
  readonly badge: ProgressBadge | undefined;
  readonly isFresh: boolean;
  readonly model: PetProfile;
  readonly onClick: () => void;
  readonly onHover: (inside: boolean) => void;
}

/** A mastery outfit's tile: greyed until earned, a rosette in the color of the tier that unlocks it, and On, Owned or the goal's progress with a thin bar. */
function ClosetGoalTile({ item, state, progress, badge, isFresh, model, onClick, onHover }: GoalTileProps) {
  const owned = stateIsOwned(state);
  const name = itemDisplayName(item);
  let label: ReactNode;
  if (state.kind === "wearing") {
    label = (
      <TightLabel symbol="checkmark" className="closet-tile-on">
        {tr("On")}
      </TightLabel>
    );
  } else if (state.kind === "owned") {
    label = <span className="kit-secondary">{tr("Owned")}</span>;
  } else {
    label = (
      <TightLabel symbol={badge === undefined ? "lock.fill" : trackSymbol(badge.track)} className="kit-secondary">
        {progress?.label ?? ""}
      </TightLabel>
    );
  }
  const help =
    state.kind === "wearing"
      ? tr("%@, earned: click to take off", name)
      : state.kind === "owned"
        ? tr("%@, earned: click to wear", name)
        : badge === undefined
          ? name
          : tr("%@ unlocks with %@. %@", name, badgeDisplayName(badge), badgeHowToEarn(badge));
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className="closet-tile closet-tile-limited"
        data-item={item}
        data-wearing={state.kind === "wearing" || undefined}
        aria-label={name}
        onClick={onClick}
        onPointerEnter={() => onHover(true)}
        onPointerLeave={() => onHover(false)}
      >
        <span className="closet-tile-sprite" style={{ opacity: owned ? 1 : 0.45, filter: owned ? undefined : "saturate(0.3)" }}>
          <PetSprite profile={PetCloset.wearing(item, model)} pixelSize={1} />
        </span>
        <span className="closet-tile-label">{label}</span>
        <span className="closet-bar closet-tile-bar" style={{ width: 40, opacity: owned ? 0 : 1 }}>
          <span style={{ width: `${(progress === undefined ? 0 : limitedProgressFraction(progress)) * 100}%` }} />
        </span>
        <Icon id="rosette" size={8} className="closet-tile-sparkle" style={{ color: badge === undefined ? "var(--tertiary-text)" : tierColor(badge.tier), opacity: owned ? 1 : 0.55 }} />
        {isFresh && owned && <span className="closet-tile-new closet-goals-new" />}
      </button>
    </Tooltip>
  );
}

/* Badges */

/**
 * A badge as a sprite (badgeArt.ts): the state's frame with the track's
 * glyph, drawn on a canvas at a whole number of device pixels per sprite
 * pixel (1.5 CSS px per pixel, 2 on the large panel, whose content scale
 * the box divides out), never smoothed. A badge with no tier yet is the
 * quiet gray coin. Starlight's sparkle blinks slowly; it holds still under
 * Reduce Motion and in snapshots. Port of ClosetBadgeArt.
 */
export function ClosetBadgeArt({ track, tier, still = false }: { track: ProgressTrack; tier: ProgressTier | undefined; still?: boolean }) {
  const kit = useKit();
  const element = useRef<HTMLCanvasElement>(null);
  const state = badgeState(tier);
  const animate = state === "starlight" && !still && !kit.still && !kit.reduceMotion;
  const [tick, setTick] = useState(0);
  /* The sparkle's frame: the bright one whenever the badge holds still. */
  const twinkle = animate && tick % 2 === 1;
  const [ratio, setRatio] = useState(() => (typeof window === "undefined" ? 1 : window.devicePixelRatio || 1));

  useEffect(() => {
    if (!animate) return;
    const timer = window.setInterval(() => setTick((count) => count + 1), BADGE_TWINKLE_SECONDS * 1000);
    return () => window.clearInterval(timer);
  }, [animate]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const update = () => setRatio(window.devicePixelRatio || 1);
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  useLayoutEffect(() => {
    const canvas = element.current;
    if (!canvas) return;
    /* The large panel scales its content as a whole (--panel-scale); the box divides that out so the badge lands at 2 CSS px per sprite pixel. */
    const panelScale = Number.parseFloat(getComputedStyle(canvas).getPropertyValue("--panel-scale")) || 1;
    const shown = panelScale > 1 ? BADGE_LARGE_PIXEL_SIZE : BADGE_REGULAR_PIXEL_SIZE;
    const scale = badgeScale(shown, ratio);
    /* The box is sized before the panel's transform, so after it the badge lands on whole device pixels. */
    const css = (BADGE_SIZE * scale) / ratio / panelScale;
    canvas.width = BADGE_SIZE * scale;
    canvas.height = BADGE_SIZE * scale;
    canvas.style.width = `${css}px`;
    canvas.style.height = `${css}px`;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.imageSmoothingEnabled = false;
    const bitmap = badgeBitmap(track, state, twinkle, scale);
    const image = context.createImageData(bitmap.width, bitmap.height);
    image.data.set(bitmap.data);
    context.putImageData(image, 0, 0);
  }, [track, state, twinkle, ratio]);

  return (
    <span className="closet-badge-art" data-state={state}>
      <canvas ref={element} className="closet-badge-canvas" aria-hidden="true" />
    </span>
  );
}

/** A badge: the track's sprite in its state's frame over four pips for the tiers earned; the progress to the next tier is in the footer and tooltip, never on the badge. */
function ClosetBadgeMedallion({ track, progression, isFresh, still, onHover }: { track: ProgressTrack; progression: PetProgression; isFresh: boolean; still: boolean; onHover: (inside: boolean) => void }) {
  const tier = progression.tier(track);
  return (
    <Tooltip text={badgeHelp(track, progression)}>
      <div
        className="closet-badge"
        role="img"
        aria-label={`${trackDisplayName(track)}, ${badgeDetail(track, progression)}`}
        data-tier={tier}
        style={{ ["--tier" as string]: tier === undefined ? "var(--tertiary-text)" : tierColor(tier) }}
        onPointerEnter={() => onHover(true)}
        onPointerLeave={() => onHover(false)}
      >
        <span className="closet-badge-medal">
          <ClosetBadgeArt track={track} tier={tier} still={still} />
          {isFresh && <span className="closet-goals-new closet-badge-new" />}
        </span>
        <span className="closet-badge-pips">
          {PROGRESS_TIERS.map((pip) => (
            <span key={pip} style={{ background: progression.isReached({ track, tier: pip }) ? tierColor(pip) : "var(--surface-hover)" }} />
          ))}
        </span>
      </div>
    </Tooltip>
  );
}
