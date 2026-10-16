/*
 * Album art with continuous corners (the Mac's SpotifyArtworkView): the
 * session's thumbnail when the app published one, the demo track's own
 * drawn cover, a generated gradient cover for a track without artwork, and
 * a quiet glyph with nothing loaded. The glow color behind a thumbnail is
 * read from the image once per track and kept, so reopening the panel never
 * decodes the same cover twice.
 */

import { useEffect, useState } from "react";
import { artworkChoice, type GeneratedCover } from "../../core/nowPlaying/nowPlayingFormat";
import { DEMO_PLAYBACK, type NowPlayingTrack } from "../../core/nowPlaying/nowPlayingPlayback";
import { Icon } from "../../ui/kit/Icon";
import { DEMO_GLOW, generatedGlow, generatedGradient, glowFromAverage } from "./artworkColor";

/** Whether `track` is the demo track, which shows the drawn cover in place of a generated one. */
export function isDemoCover(track: NowPlayingTrack): boolean {
  return track.id === DEMO_PLAYBACK.track?.id;
}

/** Glow colors by track id; thumbnails are decoded once. */
const glows = new Map<string, string>();
const GLOW_CACHE_LIMIT = 24;

function remember(id: string, glow: string): void {
  if (glows.size >= GLOW_CACHE_LIMIT) {
    const oldest = glows.keys().next().value;
    if (oldest !== undefined) glows.delete(oldest);
  }
  glows.set(id, glow);
}

/** Reads the mean color of the image at `url` by drawing it onto a one-pixel canvas. */
function averageGlow(url: string): Promise<string | undefined> {
  return new Promise((resolve) => {
    if (typeof document === "undefined") return resolve(undefined);
    const image = new Image();
    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = 1;
      canvas.height = 1;
      const context = canvas.getContext("2d", { willReadFrequently: true });
      if (!context) return resolve(undefined);
      context.drawImage(image, 0, 0, 1, 1);
      const [r, g, b] = context.getImageData(0, 0, 1, 1).data;
      resolve(r === undefined || g === undefined || b === undefined ? undefined : glowFromAverage(r, g, b));
    };
    image.onerror = () => resolve(undefined);
    image.src = url;
  });
}

/** The glow behind `track`'s cover: known at once for drawn and generated covers, read from a thumbnail when it has decoded. */
export function useArtworkGlow(track: NowPlayingTrack | undefined): string | undefined {
  const [read, setRead] = useState<{ id: string; glow: string | undefined } | undefined>(undefined);
  const choice = track ? artworkChoice(track) : undefined;
  const url = choice?.kind === "thumbnail" ? choice.dataURL : undefined;
  const id = track?.id;
  useEffect(() => {
    if (id === undefined || url === undefined || glows.has(id)) return;
    let live = true;
    void averageGlow(url).then((glow) => {
      if (!live) return;
      if (glow !== undefined) remember(id, glow);
      setRead({ id, glow });
    });
    return () => {
      live = false;
    };
  }, [id, url]);
  if (!track || !choice) return undefined;
  if (isDemoCover(track)) return DEMO_GLOW;
  if (choice.kind === "generated") return generatedGlow(choice.cover);
  return glows.get(track.id) ?? (read?.id === track.id ? read.glow : undefined);
}

export interface ArtworkViewProps {
  readonly track: NowPlayingTrack | undefined;
  readonly size: number;
  readonly cornerRadius: number;
  readonly className?: string;
}

export function ArtworkView({ track, size, cornerRadius, className }: ArtworkViewProps) {
  const choice = track ? artworkChoice(track) : undefined;
  return (
    <div className={["np-artwork", className].filter(Boolean).join(" ")} style={{ width: size, height: size, borderRadius: cornerRadius }}>
      {track && choice?.kind === "thumbnail" ? (
        <img className="np-artwork-image" src={choice.dataURL} alt="" draggable={false} />
      ) : track && isDemoCover(track) ? (
        <DemoAlbumCover />
      ) : track && choice?.kind === "generated" ? (
        <GeneratedCoverView cover={choice.cover} size={size} />
      ) : (
        <div className="np-artwork-empty">
          <Icon id="music.note" size={size * 0.32} />
        </div>
      )}
    </div>
  );
}

/** A deterministic gradient cover with a soft highlight and a note glyph (the Mac's SpotifyGeneratedCoverView). */
function GeneratedCoverView({ cover, size }: { cover: GeneratedCover; size: number }) {
  const [start, end] = generatedGradient(cover);
  return (
    <div className="np-artwork-generated" style={{ background: `linear-gradient(135deg, ${start}, ${end})` }}>
      <div className="np-artwork-highlight" style={{ background: `radial-gradient(circle at 28% 24%, rgb(255 255 255 / 0.32), transparent ${size * 0.7}px)` }} />
      <Icon id="music.note" size={size * 0.3} className="np-artwork-note" />
    </div>
  );
}

/* The demo cover's palette, the Mac's DemoAlbumCover hex values. */
const SKY = ["#2E1F4F", "#A8466A", "#F08A5D", "#F9C784"];
const SUN_TOP = "#FFE7A3";
const SUN_BOTTOM = "#F7A74F";
const HILL_FAR = "#8C3D5E";
const HILL_NEAR = "#4A2545";
const ROAD = "#2A1830";
const STARS: [number, number, number][] = [
  [0.14, 0.1, 0.012],
  [0.3, 0.2, 0.008],
  [0.46, 0.07, 0.01],
  [0.68, 0.15, 0.012],
  [0.86, 0.08, 0.009],
  [0.8, 0.26, 0.007],
  [0.22, 0.32, 0.007],
];

/** A rolling ridge across the bottom of the cover: `peaks` are the ridge's heights (as a fraction of the side from the top), evenly spaced. */
function hills(peaks: readonly number[]): string {
  const step = 1 / (peaks.length - 1);
  const points = peaks.map((peak, index) => ({ x: index * step, y: peak }));
  const first = points[0];
  if (first === undefined) return "";
  let path = `M 0 1 L ${first.x} ${first.y}`;
  for (let index = 1; index < points.length; index++) {
    const previous = points[index - 1];
    const point = points[index];
    if (previous === undefined || point === undefined) continue;
    const middle = (previous.x + point.x) / 2;
    path += ` C ${middle} ${previous.y}, ${middle} ${point.y}, ${point.x} ${point.y}`;
  }
  return `${path} L 1 1 Z`;
}

/**
 * Original cover art for the made-up demo track ("Golden Hour Drive" by
 * Maple Avenue): a road running into a setting sun between dusky hills.
 * Drawn in code, so store screenshots never show a real album's art and
 * demo mode needs no image file or network. Port of the Mac's drawing, in
 * a unit square.
 */
export function DemoAlbumCover() {
  return (
    <svg className="np-demo-cover" viewBox="0 0 1 1" preserveAspectRatio="none" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id="np-demo-sky" x1="0" y1="0" x2="0" y2="0.62">
          {SKY.map((color, index) => (
            <stop key={color} offset={index / (SKY.length - 1)} stopColor={color} />
          ))}
        </linearGradient>
        <radialGradient id="np-demo-halo" cx="0.5" cy="0.6" r="0.42" gradientUnits="userSpaceOnUse">
          <stop offset="0.24" stopColor="#F9C784" stopOpacity={0.55} />
          <stop offset="1" stopColor="#F9C784" stopOpacity={0} />
        </radialGradient>
        <linearGradient id="np-demo-sun" x1="0" y1="0.39" x2="0" y2="0.81">
          <stop offset="0" stopColor={SUN_TOP} />
          <stop offset="1" stopColor={SUN_BOTTOM} />
        </linearGradient>
      </defs>
      <rect width="1" height="1" fill="url(#np-demo-sky)" />
      {STARS.map(([x, y, r]) => (
        <circle key={`${x}-${y}`} cx={x} cy={y} r={r / 2} fill="white" fillOpacity={0.85} />
      ))}
      <circle cx="0.5" cy="0.6" r="0.42" fill="url(#np-demo-halo)" />
      <circle cx="0.5" cy="0.6" r="0.21" fill="url(#np-demo-sun)" />
      <path d={hills([0.52, 0.6, 0.5, 0.58, 0.54])} fill={HILL_FAR} />
      <path d={hills([0.62, 0.66, 0.6, 0.68, 0.62])} fill={HILL_NEAR} />
      <path d="M 0.47 0.64 L 0.53 0.64 L 0.86 1 L 0.14 1 Z" fill={ROAD} />
      <line x1="0.5" y1="1" x2="0.5" y2="0.67" stroke="#F9C784" strokeOpacity={0.9} strokeWidth={0.018} strokeLinecap="round" strokeDasharray="0.05 0.045" />
    </svg>
  );
}
