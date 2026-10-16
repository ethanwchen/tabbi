/*
 * Port of SpotifyPanel: album art on the left; title, track bar and
 * transport on the right. Every non-playing status gets its own designed
 * state. Windows sessions offer no seek, volume or "like", so the track bar
 * is a plain progress bar and the panel shows neither a volume control nor
 * a heart; a transport control the app does not accept is left out rather
 * than drawn dead. The cover is not a button either: Windows gives no way
 * to bring the playing app forward.
 */

import { useEffect, type CSSProperties } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { playbackTime, remainingTime } from "../../core/nowPlaying/nowPlayingFormat";
import { isPlaying, isRepeating, type NowPlayingPlayback, progress, repeatModeAfter } from "../../core/nowPlaying/nowPlayingPlayback";
import type { NowPlayingControls } from "../../core/nowPlaying/nowPlayingSource";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { ProgressBar } from "../../ui/kit/ProgressBar";
import { StatusMessage } from "../../ui/kit/StatusMessage";
import { Tooltip } from "../../ui/kit/Tooltip";
import { ArtworkView, useArtworkGlow } from "./Artwork";
import { type NowPlayingStore, REPEAT_ORDER } from "./nowPlayingStore";
import "./nowPlaying.css";

const ARTWORK_SIZE = 112;
const BADGE_SIZE = 24;

export function NowPlayingPanel({ store }: { store: NowPlayingStore }) {
  const state = useStore(store);
  useEffect(() => {
    store.setPanelVisible(true);
    return () => store.setPanelVisible(false);
  }, [store]);

  if (state.status.kind === "notRunning") {
    return (
      <div className="np-panel">
        <StatusMessage symbol="music.note" title={tr("Nothing playing")} message={tr("Play something in Spotify, a browser or another app with media controls, and it shows up here.")} />
      </div>
    );
  }
  const playback = state.status.playback;
  if (!playback.track) {
    return (
      <div className="np-panel">
        <StatusMessage symbol="music.note.list" title={tr("Nothing playing")} message={tr("Start something in %@ and it shows up here.", store.sourceName)} />
      </div>
    );
  }
  return <NowPlayingView store={store} playback={playback} controls={state.controls} />;
}

function NowPlayingView({ store, playback, controls }: { store: NowPlayingStore; playback: NowPlayingPlayback; controls: NowPlayingControls }) {
  const track = playback.track;
  const glow = useArtworkGlow(track);
  const title = track && track.title.length > 0 ? track.title : tr("Unknown track");
  const subtitle = [track?.artist, track?.album].filter((part): part is string => part !== undefined && part.length > 0).join(" · ");
  const help = [title, subtitle].filter((part) => part.length > 0).join(" · ");
  const sourceName = store.sourceName;
  /* The Mac's halo: half-opaque at a quarter of the cover, gone by 0.6 of it; the web's gradient is drawn a touch wider so the same halo shows past the cover's shadow. */
  const glowStyle: CSSProperties = {
    width: ARTWORK_SIZE * 1.5,
    height: ARTWORK_SIZE * 1.5,
    background: glow
      ? `radial-gradient(circle, color-mix(in srgb, ${glow} 55%, transparent) ${ARTWORK_SIZE * 0.25}px, transparent ${ARTWORK_SIZE * 0.72}px)`
      : "transparent",
  };
  return (
    <div className="np-panel np-playing">
      <div className="np-artwork-slot" style={{ width: ARTWORK_SIZE, height: ARTWORK_SIZE }}>
        {/* A radial fade (not a blur) reaches zero before the panel's clip edge, so the halo never shows a hard cut-off. */}
        <div className="np-glow" style={glowStyle} aria-hidden="true" />
        <Tooltip text={tr("Playing in %@", sourceName)}>
          <div className="np-artwork-frame" style={{ width: ARTWORK_SIZE, height: ARTWORK_SIZE }}>
            <ArtworkView track={track} size={ARTWORK_SIZE} cornerRadius={14} />
            <span className="np-badge" style={{ width: BADGE_SIZE, height: BADGE_SIZE }} role="img" aria-label={tr("Playing in %@", sourceName)}>
              <Icon id="music.note" size={BADGE_SIZE * 0.45} />
            </span>
          </div>
        </Tooltip>
      </div>
      <div className="np-column" style={{ height: ARTWORK_SIZE }}>
        <div className="np-titles">
          <MarqueeText className="np-title kit-title" text={title} help={help} />
          {subtitle.length > 0 && <MarqueeText className="np-subtitle kit-body kit-secondary" text={subtitle} help={help} />}
        </div>
        <TrackBar playback={playback} />
        <Transport store={store} playback={playback} controls={controls} />
      </div>
    </div>
  );
}

/** The position through the track with the elapsed and remaining times. Time runs left to right in every language, as the transport's arrows say. */
function TrackBar({ playback }: { playback: NowPlayingPlayback }) {
  const duration = playback.track?.duration ?? 0;
  const position = playbackTime(playback.position);
  return (
    <div className="np-track" dir="ltr">
      <div className="np-track-bar">
        <ProgressBar value={progress(playback)} tint="var(--primary-text)" height={4} help={position} label={tr("Playback position")} valueText={position} still />
      </div>
      <div className="np-times kit-caption kit-tertiary">
        <span>{position}</span>
        {/* A left-to-right mark keeps the minus in front in an Arabic locale, where a line of digits and signs reads right to left. */}
        {duration > 0 && <span>{"‎" + remainingTime(playback.position, duration)}</span>}
      </div>
    </div>
  );
}

/** Shuffle and repeat on the left, the transport centered, as on the Mac; each only when the app accepts it. */
function Transport({ store, playback, controls }: { store: NowPlayingStore; playback: NowPlayingPlayback; controls: NowPlayingControls }) {
  const playing = isPlaying(playback);
  const repeatNext = repeatModeAfter(playback.repeatMode, REPEAT_ORDER);
  const repeatHelp = repeatNext === "off" ? tr("Turn repeat off") : repeatNext === "all" ? tr("Turn repeat on") : tr("Repeat this song");
  return (
    <div className="np-transport" dir="ltr">
      <div className="np-modes">
        {controls.shuffle && (
          <IconButton
            className="np-mode"
            symbol="shuffle"
            size={24}
            help={playback.isShuffling ? tr("Turn shuffle off") : tr("Turn shuffle on")}
            selected={playback.isShuffling}
            data-on={playback.isShuffling || undefined}
            onClick={() => store.toggleShuffle()}
          />
        )}
        {controls.repeat && (
          <IconButton
            className="np-mode"
            symbol={playback.repeatMode === "one" ? "repeat.1" : "repeat"}
            size={24}
            help={repeatHelp}
            selected={isRepeating(playback)}
            data-on={isRepeating(playback) || undefined}
            onClick={() => store.cycleRepeat()}
          />
        )}
      </div>
      <div className="np-buttons">
        {controls.previous && <IconButton className="np-skip" symbol="backward.fill" size={32} help={tr("Previous track")} onClick={() => store.previous()} />}
        {controls.playPause && (
          <IconButton className="np-play" symbol={playing ? "pause.fill" : "play.fill"} size={36} help={playing ? tr("Pause") : tr("Play")} lifts onClick={() => store.playPause()} />
        )}
        {controls.next && <IconButton className="np-skip" symbol="forward.fill" size={32} help={tr("Next track")} onClick={() => store.next()} />}
      </div>
    </div>
  );
}
