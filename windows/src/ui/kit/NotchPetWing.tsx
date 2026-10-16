/*
 * The Mac's `NotchPetWing`: the study pet in the closed island's leading
 * wing: typing on its laptop while the user focuses, sipping coffee on
 * breaks, idling while a session ran recently, and curled up asleep once
 * none has for a while. When a focus session finishes it cheers (`PetCheer`):
 * two happy hops with a few sparkles; a crown or a sip hop once. Partway
 * through a long focus block it trots off into the island on a little
 * adventure (`PetAdventure`), leaving a paw print in its spot, and trots
 * back out as the block ends; under Reduce Motion it stays.
 *
 * It owns its own `PetPlayer`, kept for as long as the pet stays on screen,
 * so mood changes play the real fall-asleep and stretch-awake clips instead
 * of cutting between them.
 */

import { useEffect, useMemo, useReducer, useRef, useState } from "react";
import { PetAdventure, phaseDistance, type AdventurePhase } from "../../core/pets/petAdventure";
import { activityForMood, type PetMood } from "../../core/pets/petAnimator";
import { FRAME_SIZE } from "../../core/pets/petComposer";
import type { PetCheer } from "../../core/motion/petCheer";
import type { PetProfile } from "../../core/pets/petProfile";
import type { Instant } from "../../core/time";
import { CelebrationBurstView, makeCelebration } from "./Celebration";
import { useKit } from "./context";
import { Icon } from "./Icon";
import { PetPlayer, petClockNow } from "./petPlayer";
import { PetSprite, PetView } from "./PetView";
import { accentCss } from "./tokens";

/** Points per sprite pixel: the sitting pet fits the 32 px pill. Its clips keep everything below the ceiling row, so nothing is cut off at the top. */
export const PET_WING_PIXEL_SIZE = 1;
export const PET_WING_SIDE = FRAME_SIZE * PET_WING_PIXEL_SIZE;
/** How far the closed pet is lifted off the bar's bottom edge, and the first sprite row at least a pixel below the bar's top (NotchPreviewLayout.petCeilingRow). */
export const PET_WING_LIFT = 1;
export const PET_WING_CEILING_ROW = 2;
/** How far the pet trots toward the island before it is out of sight. */
export const PET_WING_ADVENTURE_TRAVEL = 24;
/** When a cheer's second hop starts: as the first one lands. */
const SECOND_HOP = 1.0;
/* A smooth trot for a three second walk without redrawing every frame. */
const WALK_STEP = 1 / 30;

export interface NotchPetWingProps {
  readonly profile: PetProfile;
  readonly mood: PetMood;
  /** When the running phase began; a pet drawn anew mid-session reads it. */
  readonly moodSince?: Instant | undefined;
  readonly cheer?: PetCheer | undefined;
  readonly adventure?: PetAdventure | undefined;
  /** The app's clock in seconds since 1970, for the cheer and the adventure. */
  readonly now: () => Instant;
  /** The pet module's accent, as CSS, for the cheer's sparkles. */
  readonly accent?: string;
}

/* The animation clock (performance.now) that `instant` on the app clock falls on. */
function onAnimationClock(instant: Instant, now: () => Instant): number {
  return petClockNow() - (now() - instant);
}

export function NotchPetWing({ profile, mood, moodSince, cheer, adventure, now, accent }: NotchPetWingProps) {
  const { reduceMotion, still, theme } = useKit();
  /* A wing that appears mid-cheer (the ticker switched to the pet for it) starts the hop at the cheer's start, so it never lags. */
  const [start] = useState(() => {
    const showing = cheer !== undefined && cheer.isShowing(now()) ? cheer : undefined;
    const at = showing === undefined ? petClockNow() : onAnimationClock(showing.startedAt, now);
    const made = new PetPlayer(profile, {
      asleep: mood === "asleep",
      activity: activityForMood(mood),
      ...(moodSince === undefined ? {} : { activitySince: onAnimationClock(moodSince, now) }),
      at,
      ceiling: PET_WING_CEILING_ROW,
    });
    if (showing !== undefined) made.send({ kind: "celebrate" }, at);
    return { player: made, cheerID: showing?.id };
  });
  const player = start.player;
  /* The cheer whose first hop has played, so a redraw never restarts it. */
  const cheered = useRef<number | undefined>(start.cheerID);

  useEffect(() => {
    player.update(profile);
  }, [player, profile]);

  const first = useRef(true);
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    player.send({ kind: "activity", activity: activityForMood(mood) });
    player.send({ kind: mood === "asleep" ? "sleep" : "wake" });
  }, [player, mood]);

  /* The cheer's hops: two for a dance, one for a crown or a sip, and only one with Reduce Motion on. */
  useEffect(() => {
    if (cheer === undefined || !cheer.isShowing(now())) return;
    if (cheered.current !== cheer.id) {
      cheered.current = cheer.id;
      player.send({ kind: "celebrate" });
    }
    if (cheer.kind !== "dance" || reduceMotion || still) return;
    const wait = (cheer.startedAt + SECOND_HOP - now()) * 1000;
    if (wait <= 0) return;
    const timer = window.setTimeout(() => player.send({ kind: "celebrate" }), wait);
    return () => window.clearTimeout(timer);
  }, [cheer, now, player, reduceMotion, still]);

  const sparkles = useMemo(() => {
    if (cheer === undefined || cheer.kind === "sip" || reduceMotion || still || !cheer.isShowing(now())) return undefined;
    return makeCelebration({ tier: "burst", style: "sparkles", accent: accent ?? accentCss(theme, { red: 0.98, green: 0.8, blue: 0.3 }), theme, startedAt: onAnimationClock(cheer.startedAt, now) * 1000, seed: cheer.id });
  }, [cheer, reduceMotion, still, now, accent, theme]);

  const home = (
    <span className="kit-pet-wing" style={{ width: PET_WING_SIDE, height: PET_WING_SIDE }}>
      <span className="kit-pet-wing-pet" style={{ transform: `translate(-3px, ${-PET_WING_LIFT}px)` }}>
        <PetView player={player} pixelSize={PET_WING_PIXEL_SIZE} />
      </span>
      {sparkles !== undefined && (
        <span className="kit-pet-wing-sparkles" style={{ width: PET_WING_SIDE + 24, height: PET_WING_SIDE + 8 }}>
          <CelebrationBurstView celebration={sparkles} />
        </span>
      )}
    </span>
  );

  if (adventure === undefined || reduceMotion || still) return home;
  return <AdventureWing adventure={adventure} player={player} profile={profile} now={now} home={home} />;
}

/* Redraws at each phase change and smoothly while the pet walks. */
function useAdventureClock(adventure: PetAdventure, now: () => Instant): Instant {
  const [, tick] = useReducer((count: number) => count + 1, 0);
  const at = now();
  useEffect(() => {
    let timer = 0;
    const schedule = () => {
      const current = now();
      const change = adventure.nextChange(current);
      const phase = adventure.phase(current).kind;
      const walking = phase === "leaving" || phase === "returning";
      const next = walking ? Math.min(change ?? Infinity, current + WALK_STEP) : change;
      if (next === undefined || !Number.isFinite(next)) return;
      timer = window.setTimeout(
        () => {
          tick();
          schedule();
        },
        Math.max(0, (next - current) * 1000),
      );
    };
    schedule();
    return () => window.clearTimeout(timer);
  }, [adventure, now]);
  return at;
}

function AdventureWing({ adventure, player, profile, now, home }: { adventure: PetAdventure; player: PetPlayer; profile: PetProfile; now: () => Instant; home: React.ReactNode }) {
  const date = useAdventureClock(adventure, now);
  const phase = adventure.phase(date);
  switch (phase.kind) {
    case "home":
      return home;
    case "away":
      return (
        <span className="kit-pet-wing kit-pet-wing-away" style={{ width: PET_WING_SIDE, height: PET_WING_SIDE, transform: "translateX(-3px)" }}>
          <Icon id="pawprint.fill" size={10} />
        </span>
      );
    default:
      return <Walker phase={phase} adventure={adventure} player={player} profile={profile} date={date} />;
  }
}

/* Trotting toward the island (the walk clip faces left, so mirrored) on the way out, and back out of it facing left, fading with distance. */
function Walker({ phase, adventure, player, profile, date }: { phase: AdventurePhase; adventure: PetAdventure; player: PetPlayer; profile: PetProfile; date: Instant }) {
  const leaving = phase.kind === "leaving";
  const start = leaving ? adventure.departsAt : adventure.returnsAt;
  const frame = player.clips.clip("walk").frame(date - start).atItemTime(date);
  const distance = phaseDistance(phase);
  const offset = Math.round(distance * PET_WING_ADVENTURE_TRAVEL);
  return (
    <span className="kit-pet-wing" style={{ width: PET_WING_SIDE, height: PET_WING_SIDE }} role="img" aria-label={profile.name}>
      <span className="kit-pet-wing-pet" style={{ transform: `translate(${offset - 3}px, ${-PET_WING_LIFT}px) scaleX(${leaving ? -1 : 1})`, opacity: 1 - distance }}>
        <PetSprite canvas={frame.canvas} palette={player.palette} pixelSize={PET_WING_PIXEL_SIZE} />
      </span>
    </span>
  );
}
