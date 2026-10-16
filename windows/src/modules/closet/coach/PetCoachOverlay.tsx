/*
 * Port of PetCoachOverlayView and PetCoachOverlayWindow: the coach's moment
 * on screen. The Mac draws it in a transparent window hanging below the
 * menu bar at the notch's right edge; Windows has no second window, so it
 * draws in the island's own canvas as the closed overlay: the pet trots out
 * from under the pill's trailing edge, says its line in a bubble hanging
 * below it (beside it would not fit the 560 px canvas), then trots back and
 * the overlay closes. Everything is positioned from `PetCoachStroll`, so the
 * clock fully decides the picture; a snapshot freezes one moment.
 */

import { useEffect, useLayoutEffect, useReducer, useState, type CSSProperties } from "react";
import type { ClosedOverlay, ClosedOverlayFrame } from "../../../app/takeover";
import { awardHeadline, awardUnlockLine, type PetStudyAward } from "../../../core/closet/petStudyCredit";
import { PetCoach } from "../../../core/coach/petCoach";
import { coachMessageText } from "../../../core/coach/petCoachMessages";
import { glanceNextRedraw, strollNextRedraw } from "../../../core/coach/petCoachRedraw";
import { replyHelp, replyTitle, type PetCoachReply } from "../../../core/coach/petCoachReply";
import { tr } from "../../../core/localization/tr";
import { wisdomDisplayText, type CatWisdomLine } from "../../../core/motivation/catWisdom";
import { deliveryMessage, type SurpriseGiftDelivery } from "../../../core/motivation/surpriseGift";
import { itemDisplayName } from "../../../core/pets/petItem";
import type { UnlockProgress } from "../../../core/motivation/unlockProgress";
import type { PetFrame } from "../../../core/pets/petClip";
import { FRAME_SIZE } from "../../../core/pets/petComposer";
import type { Instant } from "../../../core/time";
import { useKit } from "../../../ui/kit/context";
import { Icon } from "../../../ui/kit/Icon";
import { PetSprite } from "../../../ui/kit/PetView";
import { Tooltip } from "../../../ui/kit/Tooltip";
import { useSpringValue } from "../../../ui/kit/useSpringValue";
import { RADIUS, VIRTUAL_NOTCH, type HitRect } from "../../../ui/shell/geometry";
import { lineArrival, lineHasBubble, lineReplies, lineShowsWisdom, lineWisdom, type PetCoachLine, type PetCoachScene } from "./petCoachScene";
import "./coach.css";

/** Points per sprite pixel: a 48 px pet, larger than beside the island so it holds its own over busy windows. */
export const COACH_PIXEL_SIZE = 1.5;
export const COACH_PET_SIDE = FRAME_SIZE * COACH_PIXEL_SIZE;
export const COACH_BUBBLE_WIDTH = 244;
/** The pet's paws sit this far below the pill's bottom edge. */
const PET_TOP = 4;
/** The bubble hangs this far below the pet. */
const BUBBLE_GAP = 6;
/** The pill's hit region reaches past its drawn edge by the hover growth and the slop. */
const PILL_REACH = 12;
/** The glance hangs from the pill's bottom edge, just inside its rounded corner. */
const GLANCE_INSET = RADIUS.closedBottom + 4;

export interface CoachOverlayInput {
  readonly scene: () => PetCoachScene;
  readonly now: () => Instant;
  /** A snapshot: draw `now()` once and never tick. */
  readonly frozen: boolean;
  readonly subscribe: (listener: () => void) => () => void;
  readonly onReply: (reply: PetCoachReply) => void;
  readonly onHover: (over: boolean) => void;
}

/** Where the pet starts from: the pill's drawn trailing edge. */
function pillEdge(frame: ClosedOverlayFrame): number {
  return frame.pill.x + frame.pill.width - PILL_REACH;
}

/** The region the overlay needs: the strip beside and below the pill where the pet and its bubble can be. */
function overlayRect(frame: ClosedOverlayFrame): HitRect {
  const edge = pillEdge(frame);
  const left = Math.min(edge - GLANCE_INSET - COACH_PET_SIDE, frame.canvas.width - 8 - COACH_BUBBLE_WIDTH);
  return { x: Math.max(0, left), y: VIRTUAL_NOTCH.height, width: frame.canvas.width - Math.max(0, left), height: Math.min(frame.canvas.height, 220) - VIRTUAL_NOTCH.height };
}

export function makeCoachOverlay(input: CoachOverlayInput): ClosedOverlay {
  return {
    rect: overlayRect,
    Body: (frame) => <CoachOverlay input={input} frame={frame} />,
  };
}

/* Redraws only when the picture changes (PetCoachRedraw): every walking frame, each clip frame change while standing, peeking or talking. */
function useCoachClock(input: CoachOverlayInput, scene: PetCoachScene, still: boolean): Instant {
  const [, tick] = useReducer((count: number) => count + 1, 0);
  const at = input.now();
  useEffect(() => {
    if (input.frozen || still) return;
    let timer = 0;
    let frame = 0;
    const schedule = () => {
      const now = input.now();
      const line = scene.line;
      const marks = lineWisdom(line) === undefined ? [] : [scene.stroll.dateAfterTalking(PetCoach.celebrationDuration)].filter((mark): mark is number => mark !== undefined);
      const next = line.kind === "glance" ? glanceNextRedraw(line.glance, now, scene.clips) : strollNextRedraw(scene.stroll, now, scene.clips, lineArrival(line), marks);
      if (next === undefined) return;
      timer = window.setTimeout(
        () => {
          frame = requestAnimationFrame(() => {
            tick();
            schedule();
          });
        },
        Math.max(0, (next - now) * 1000),
      );
    };
    schedule();
    return () => {
      window.clearTimeout(timer);
      cancelAnimationFrame(frame);
    };
  }, [input, scene, still]);
  return at;
}

function CoachOverlay({ input, frame }: { input: CoachOverlayInput; frame: ClosedOverlayFrame }) {
  const { reduceMotion, still } = useKit();
  const [scene, setScene] = useState(input.scene);
  useEffect(() => input.subscribe(() => setScene(input.scene())), [input]);
  const date = useCoachClock(input, scene, still);
  const stroll = scene.stroll;
  const edge = pillEdge(frame);
  const line = scene.line;

  if (line.kind === "glance") {
    /* Hanging from the pill's bottom edge by its front paws: the head lowers into view, looks, and pulls back up. Reduce Motion: it just hangs there for the look. */
    const pose = reduceMotion ? (line.glance.pose(date) === undefined ? undefined : { animation: "peekIn" as const, elapsed: line.glance.enter }) : line.glance.pose(date);
    if (pose === undefined) return null;
    const petFrame = drawn(scene.clips.clip(pose.animation).frame(pose.elapsed), date, reduceMotion);
    return (
      <div className="coach-overlay" style={{ clipPath: `inset(${VIRTUAL_NOTCH.height}px 0 0 0)` }}>
        <div className="coach-pet" style={{ left: edge - GLANCE_INSET - COACH_PET_SIDE, top: VIRTUAL_NOTCH.height }} role="img" aria-label={scene.profile.name}>
          <PetSprite canvas={petFrame.canvas} palette={scene.profile.palette} pixelSize={COACH_PIXEL_SIZE} />
        </div>
      </div>
    );
  }

  /* Reduce Motion: no trot, the pet simply shows up at its spot. */
  const offset = reduceMotion && stroll.phase(date) !== "finished" ? stroll.distance : stroll.offset(date);
  const phase = stroll.phase(date);
  let petFrame: PetFrame;
  let mirrored = false;
  switch (phase) {
    case "walkingOut":
      petFrame = scene.clips.clip("walk").frame(date - stroll.startedAt);
      mirrored = true;
      break;
    case "talking": {
      const elapsed = date - stroll.arrivesAt;
      const arrival = scene.clips.clip(lineArrival(line));
      petFrame = elapsed < arrival.duration ? arrival.frame(elapsed) : scene.clips.clip("idle").frame(elapsed - arrival.duration);
      break;
    }
    case "walkingBack":
    case "finished":
      petFrame = scene.clips.clip("walk").frame(date - stroll.turnsBackAt);
      break;
  }
  petFrame = drawn(petFrame, date, reduceMotion);
  const petX = edge + Math.round(offset) - COACH_PET_SIDE;
  const petTop = VIRTUAL_NOTCH.height + PET_TOP;
  const showsBubble = lineHasBubble(line) && stroll.showsBubble(date);
  const bubbleLeft = Math.max(0, Math.min(edge + stroll.distance - COACH_PET_SIDE, frame.canvas.width - 8 - COACH_BUBBLE_WIDTH));
  const tailX = edge + stroll.distance - COACH_PET_SIDE / 2 - bubbleLeft;
  return (
    <div className="coach-overlay" style={{ clipPath: `inset(0 0 0 ${edge}px)` }}>
      <div className="coach-pet" style={{ left: petX, top: petTop, transform: mirrored ? "scaleX(-1)" : undefined }} role="img" aria-label={scene.profile.name}>
        <PetSprite canvas={petFrame.canvas} palette={scene.profile.palette} pixelSize={COACH_PIXEL_SIZE} />
      </div>
      {showsBubble && (
        <PetCoachBubble
          line={line}
          showsWisdom={lineShowsWisdom(line, stroll.talkElapsed(date))}
          animated={!input.frozen && !still}
          style={{ left: bubbleLeft, top: petTop + COACH_PET_SIDE + BUBBLE_GAP, width: COACH_BUBBLE_WIDTH, "--coach-tail-x": `${Math.round(tailX)}px` } as CSSProperties}
          onReply={input.onReply}
          onHover={input.onHover}
        />
      )}
    </div>
  );
}

/** `frame` with its worn items at their loop step for `date` (a cape's glint, flapping wings). Reduce Motion keeps the items' still frame. */
function drawn(frame: PetFrame, date: Instant, reduceMotion: boolean): PetFrame {
  return reduceMotion ? frame : frame.atItemTime(date);
}

interface BubbleProps {
  readonly line: PetCoachLine;
  readonly showsWisdom: boolean;
  /** False in snapshots, which show a celebration's count already settled. */
  readonly animated: boolean;
  readonly style: CSSProperties;
  readonly onReply: (reply: PetCoachReply) => void;
  readonly onHover: (over: boolean) => void;
}

/** The speech bubble: the pet's line and its buttons, on the same black as the island so it reads as part of it, over any wallpaper. */
function PetCoachBubble({ line, showsWisdom, animated, style, onReply, onHover }: BubbleProps) {
  const replies = lineReplies(line);
  /* A bubble without buttons closes on a click anywhere on it. */
  const dismissesOnClick = lineHasBubble(line) && replies.length === 0;
  const wisdom = lineWisdom(line);
  const body = (
    <div
      className="coach-bubble"
      data-clickable={dismissesOnClick || undefined}
      style={style}
      role="group"
      onClick={dismissesOnClick ? () => onReply("thanks") : undefined}
      onPointerEnter={() => onHover(true)}
      onPointerLeave={() => onHover(false)}
    >
      <svg className="coach-bubble-tail" width="14" height="8" viewBox="0 0 14 8" aria-hidden="true">
        <path d="M0 8 L7 0.5 L14 8 Z" />
      </svg>
      {line.kind === "nudge" && <div className="kit-body-emphasis coach-nudge-text">{coachMessageText(line.nudge.message)}</div>}
      {line.kind === "celebration" &&
        (showsWisdom && wisdom !== undefined ? (
          <PetWisdomText line={wisdom} />
        ) : (
          <PetCelebrationText award={line.award} progress={line.progress} gift={line.gift} animated={animated} />
        ))}
      {replies.length > 0 && (
        <div className="coach-replies">
          {replies.map((reply, index) => (
            <Tooltip key={reply} text={replyHelp(reply)}>
              <button type="button" className="coach-reply kit-caption" data-primary={index === 0 || undefined} onClick={() => onReply(reply)}>
                {reply === "snooze" && <Icon id="moon.zzz.fill" size={9} />}
                <span>{replyTitle(reply)}</span>
              </button>
            </Tooltip>
          ))}
        </div>
      )}
    </div>
  );
  return dismissesOnClick ? <Tooltip text={tr("Click to send the pet home")}>{body}</Tooltip> : body;
}

/**
 * A celebration's words: the headline with the points pill beside it,
 * counting up from zero, then a bar filling toward the next unlock with
 * what it still asks. Without a goal left, a level-up names the item now
 * within reach. A surprise gift gets one quiet line at the bottom.
 */
function PetCelebrationText({ award, progress, gift, animated }: { award: PetStudyAward; progress: UnlockProgress | undefined; gift: SurpriseGiftDelivery | undefined; animated: boolean }) {
  const [settled, setSettled] = useState(!animated);
  useLayoutEffect(() => {
    if (!animated) return;
    const timer = window.setTimeout(() => setSettled(true), 250);
    return () => window.clearTimeout(timer);
  }, [animated]);
  const points = useSpringValue(settled ? award.points : 0, "content", { immediate: !animated });
  const fraction = useSpringValue(progress === undefined ? 0 : settled ? progress.fraction : progress.fractionBefore, "content", { immediate: !animated });
  const unlock = awardUnlockLine(award);
  return (
    <div className="coach-celebration" role="group">
      <div className="coach-celebration-head">
        <span className="kit-body-emphasis coach-headline">{awardHeadline(award)}</span>
        <Tooltip text={tr("Points earned for this session")}>
          <span className="coach-points">
            <Icon id="star.fill" size={8} />
            <span>{`+${Math.min(award.points, Math.max(0, Math.round(points)))}`}</span>
          </span>
        </Tooltip>
      </div>
      {progress !== undefined ? (
        <Tooltip text={progress.isReady ? tr("%@ is ready in the Closet", itemDisplayName(progress.item)) : tr("%lld more points for %@", progress.missing, itemDisplayName(progress.item))}>
          <div className="coach-unlock">
            <span className="coach-unlock-bar">
              <span style={{ width: `max(4px, ${Math.min(1, Math.max(0, fraction)) * 100}%)` }} />
            </span>
            <span className="kit-caption coach-unlock-line" style={{ color: progress.isReady ? "var(--accent)" : "var(--secondary-text)" }}>
              {progress.line}
            </span>
          </div>
        </Tooltip>
      ) : (
        unlock !== undefined && <span className="kit-caption kit-secondary coach-unlock-line">{unlock}</span>
      )}
      {gift !== undefined && <PetGiftLine delivery={gift} />}
    </div>
  );
}

/** The gift the pet brought back, under the bar. */
function PetGiftLine({ delivery }: { delivery: SurpriseGiftDelivery }) {
  const gift = delivery.gift;
  const kindHelp =
    gift.kind === "bonusPoints"
      ? tr("Bonus points from your pet, added to your balance")
      : gift.kind === "rareFur"
        ? tr("A rare fur color from your pet. Try it in the Closet under Look.")
        : tr("Bonus minutes toward this event's limited items");
  const help = delivery.adventure === undefined ? kindHelp : tr("Your pet found this on its adventure. %@", kindHelp);
  return (
    <Tooltip text={help}>
      <div className="coach-gift kit-caption">
        <Icon id="gift.fill" size={9} className="coach-gift-icon" />
        <span className="coach-gift-text">{deliveryMessage(delivery)}</span>
        {gift.kind === "rareFur" && <span className="coach-gift-fur" style={{ background: `rgb(${gift.fur.color.red} ${gift.fur.color.green} ${gift.fur.color.blue})` }} />}
      </div>
    </Tooltip>
  );
}

/** A Cat wisdom line: a small label, then the line itself in up to three short lines. */
function PetWisdomText({ line }: { line: CatWisdomLine }) {
  return (
    <Tooltip text={tr("A line from your pet. Hover to keep it, click to send the pet home. Turn it off in Settings › General.")}>
      <div className="coach-wisdom" role="group">
        <span className="kit-caption kit-tertiary coach-wisdom-label">
          <Icon id="sparkle" size={8} className="coach-wisdom-sparkle" />
          <span>{tr("Cat wisdom")}</span>
        </span>
        <span className="kit-body-emphasis coach-wisdom-text">{wisdomDisplayText(line)}</span>
      </div>
    </Tooltip>
  );
}

export const COACH_OVERLAY_GEOMETRY = { pillEdge, overlayRect };
