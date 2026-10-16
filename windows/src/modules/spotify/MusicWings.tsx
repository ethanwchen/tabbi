/*
 * The closed pill's wings while music plays (the Mac's SpotifyCompactLeading
 * and SpotifyCompactTrailing): the current cover at 20 px on the left, four
 * equalizer bars in the module accent on the right. On screen the bars run
 * a keyframe loop of the core's SpotifyEqualizer that the compositor plays
 * by itself, so a playing track costs the app nothing per frame; pausing
 * springs them down to their resting heights. In a still render they stand
 * at one moment of the loop.
 */

import { useEffect, useRef } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { Equalizer } from "../../core/nowPlaying/nowPlayingFormat";
import { statusPlayback } from "../../core/nowPlaying/nowPlayingSource";
import { useKit } from "../../ui/kit/context";
import { Tooltip } from "../../ui/kit/Tooltip";
import { ArtworkView } from "./Artwork";
import type { NowPlayingStore } from "./nowPlayingStore";

export const EQUALIZER = {
  barWidth: 3,
  maxHeight: 14,
  spacing: 2,
  /** How long the bars' motion runs before it repeats. */
  loopDuration: 30,
  frameRate: 30,
  /** The moment of the loop a still render shows. */
  stillTime: 1.25,
} as const;

/** The bars' keyframes, the same for every view, built once. */
const LOOPS: readonly (readonly number[])[] = Array.from({ length: Equalizer.barCount }, (_, bar) =>
  Equalizer.loop(bar, EQUALIZER.loopDuration, EQUALIZER.frameRate, 1).map((level) => EQUALIZER.maxHeight * level),
);

/** Short, staggered heights shown while paused. */
const RESTING: readonly number[] = Equalizer.restingLevels();

export function MusicLeading({ store }: { store: NowPlayingStore }) {
  const track = useStore(store, (state) => statusPlayback(state.status)?.track);
  const help = track ? [track.title, track.artist].filter((part) => part.length > 0).join(" · ") : store.sourceName;
  return (
    <Tooltip text={help}>
      <span className="np-wing-art">
        <ArtworkView track={track} size={20} cornerRadius={5} />
      </span>
    </Tooltip>
  );
}

export function MusicTrailing({ store }: { store: NowPlayingStore }) {
  const isPlaying = useStore(store, (state) => state.isPlaying);
  const help = isPlaying ? tr("Playing in %@", store.sourceName) : tr("Paused");
  return (
    <Tooltip text={help}>
      <span className="np-wing-bars">
        <EqualizerBars isPlaying={isPlaying} />
      </span>
    </Tooltip>
  );
}

export function EqualizerBars({ isPlaying }: { isPlaying: boolean }) {
  const { still, reduceMotion } = useKit();
  const bars = useRef<(HTMLSpanElement | null)[]>([]);

  useEffect(() => {
    const elements = bars.current;
    if (still) {
      const levels = isPlaying ? Equalizer.levels(EQUALIZER.stillTime) : RESTING;
      elements.forEach((bar, index) => {
        if (bar) bar.style.height = `${EQUALIZER.maxHeight * (levels[index] ?? Equalizer.minimumLevel)}px`;
      });
      return;
    }
    const animations: Animation[] = [];
    elements.forEach((bar, index) => {
      if (!bar) return;
      const loop = LOOPS[index];
      if (isPlaying && loop !== undefined && typeof bar.animate === "function") {
        /* The spring to rest must not fight the loop: the loop owns the height while it plays. */
        bar.style.transition = "none";
        animations.push(bar.animate(loop.map((height) => ({ height: `${height}px` })), { duration: EQUALIZER.loopDuration * 1000, iterations: Infinity, easing: "linear" }));
      } else {
        /* Spring down from wherever the bar is now; under Reduce Motion it lands at once. */
        const from = bar.getBoundingClientRect().height;
        bar.style.transition = "none";
        bar.style.height = `${from}px`;
        void bar.offsetHeight;
        bar.style.transition = reduceMotion ? "none" : "height var(--spring-snappy)";
        bar.style.height = `${EQUALIZER.maxHeight * (RESTING[index] ?? Equalizer.minimumLevel)}px`;
      }
    });
    return () => {
      for (const animation of animations) animation.cancel();
    };
  }, [isPlaying, still, reduceMotion]);

  return (
    <span className="np-equalizer" style={{ gap: EQUALIZER.spacing, height: EQUALIZER.maxHeight }} aria-hidden="true">
      {RESTING.map((level, index) => (
        <span
          key={index}
          ref={(element) => {
            bars.current[index] = element;
          }}
          className="np-equalizer-bar"
          style={{ width: EQUALIZER.barWidth, height: EQUALIZER.maxHeight * level }}
        />
      ))}
    </span>
  );
}
