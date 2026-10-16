/*
 * The Mac's `PetView`: draws a `PetPlayer`'s pet as crisp pixel art on a
 * canvas, redrawing only when the frame changes. The view is a fixed square
 * of 32 sprite pixels times `pixelSize` CSS pixels, so placement never jumps
 * between frames (hops and peeks happen inside it); each frame is written at
 * a whole number of device pixels per sprite pixel with smoothing off
 * (drawPet), so 125 and 150 percent displays never get uneven pixels. The
 * sprite sits on the bottom of its box, on the shared baseline.
 *
 * Playback follows the player's own schedule: a timer wakes at the next
 * frame change and the frame is drawn in a requestAnimationFrame, only
 * while the canvas is on screen and the page is visible. Under Reduce
 * Motion the pet holds one pose per state, and a still render draws the
 * frame for its moment once. `PetSprite` is one still picture, for tiles.
 */

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { PetCanvas } from "../../core/pets/petCanvas";
import type { PetPoint } from "../../core/pets/petPose";
import { FRAME_SIZE } from "../../core/pets/petComposer";
import type { PetPalette } from "../../core/pets/petPalette";
import type { PetProfile } from "../../core/pets/petProfile";
import { breedDisplayName } from "../../core/pets/petBreed";
import { drawPet, pixelScale, sizePetCanvas, type PetPixelScale } from "../pets/drawPet";
import { useKit } from "./context";
import { PetPlayer, petClockNow } from "./petPlayer";

/* The "!" speech bubble on the pet's own pixel grid: C cream, K ink, . clear. Its tail tip is the bottom-left pixel. */
const BUBBLE_ROWS = [".CCCCCCC.", "CCCCKCCCC", "CCCCKCCCC", "CCCCKCCCC", "CCCCCCCCC", "CCCCKCCCC", ".CCCCCCC.", "CC.......", "C........"];
export const BUBBLE_WIDTH = BUBBLE_ROWS[0]?.length ?? 9;
export const BUBBLE_HEIGHT = BUBBLE_ROWS.length;
const BUBBLE_CREAM = "rgb(255 245 224)";
const BUBBLE_INK = "rgb(61 38 26)";

/** How a pet lays out in its box: the whole-pixel canvas size and where it sits (bottom aligned, centered). */
export interface PetLayout extends PetPixelScale {
  readonly boxSize: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

/** The layout for a pet at `pixelSize` CSS pixels per sprite pixel on a display with `devicePixelRatio`. */
export function petLayout(pixelSize: number, devicePixelRatio: number, frameSize = FRAME_SIZE): PetLayout {
  const boxSize = frameSize * pixelSize;
  let size = pixelScale(boxSize, boxSize, devicePixelRatio, frameSize, frameSize);
  if (size.scale < 1) {
    /*
     * A box smaller than one device pixel per sprite pixel (a 24 px pet on a
     * 100 percent display) cannot be even; it draws at one pixel per sprite
     * pixel and the browser scales it down, pixelated, to the box.
     */
    size = { scale: 1, deviceWidth: frameSize, deviceHeight: frameSize, cssWidth: boxSize, cssHeight: boxSize };
  }
  return {
    ...size,
    boxSize,
    offsetX: (boxSize - size.cssWidth) / 2,
    offsetY: boxSize - size.cssHeight,
  };
}

/** Draws the bubble at device-pixel `scale` with its tail tip one sprite pixel up and right of `anchor`. */
export function drawBubble(context: CanvasRenderingContext2D, anchor: PetPoint, scale: number): void {
  const left = (anchor.x + 1) * scale;
  const top = (anchor.y - BUBBLE_HEIGHT) * scale;
  for (const fill of [BUBBLE_CREAM, BUBBLE_INK]) {
    context.fillStyle = fill;
    const wanted = fill === BUBBLE_CREAM ? "C" : "K";
    BUBBLE_ROWS.forEach((row, y) => {
      for (let x = 0; x < row.length; x++) {
        if (row[x] === wanted) context.fillRect(left + x * scale, top + y * scale, scale, scale);
      }
    });
  }
}

/** Draws one composed canvas (and its bubble) onto `element`, sized by `layout`. */
export function paintPet(element: HTMLCanvasElement, layout: PetLayout, canvas: PetCanvas | undefined, palette: PetPalette, bubble?: PetPoint): void {
  if (element.width !== layout.deviceWidth || element.height !== layout.deviceHeight) sizePetCanvas(element, layout);
  const context = element.getContext("2d");
  if (!context) return;
  context.clearRect(0, 0, element.width, element.height);
  if (!canvas || layout.scale < 1) return;
  drawPet(context, canvas, palette, layout.scale);
  if (bubble) drawBubble(context, bubble, layout.scale);
}

export interface PetViewProps {
  /** The pet to play; a player is made for a bare profile. */
  readonly player?: PetPlayer;
  readonly profile?: PetProfile;
  /** CSS pixels per sprite pixel: 1 makes a 32 px pet, 0.75 a 24 px one. */
  readonly pixelSize?: number;
  readonly className?: string;
}

export function PetView({ player, profile, pixelSize = 1, className }: PetViewProps) {
  const { reduceMotion, still } = useKit();
  const owned = useMemo(() => (player ? undefined : profile ? new PetPlayer(profile) : undefined), [player, profile]);
  const active = player ?? owned;
  const canvas = useRef<HTMLCanvasElement>(null);
  const [ratio, setRatio] = useState(() => (typeof window === "undefined" ? 1 : window.devicePixelRatio || 1));
  const [revision, setRevision] = useState(0);
  const [visible, setVisible] = useState(true);
  const layout = useMemo(() => petLayout(pixelSize, ratio), [pixelSize, ratio]);

  useEffect(() => {
    if (!active) return;
    return active.subscribe(() => setRevision((r) => r + 1));
  }, [active]);

  useEffect(() => {
    if (owned && profile) owned.update(profile);
  }, [owned, profile]);

  /* A display change (the window moved to another monitor) changes the whole-pixel scale. */
  useEffect(() => {
    const query = window.matchMedia(`(resolution: ${ratio}dppx)`);
    const update = () => setRatio(window.devicePixelRatio || 1);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, [ratio]);

  useEffect(() => {
    const element = canvas.current;
    if (!element || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) setVisible(entry.isIntersecting);
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useLayoutEffect(() => {
    const element = canvas.current;
    if (!element || !active) return;
    const holdStill = reduceMotion || still;
    const draw = (at: number) => {
      const frame = holdStill ? active.stillFrame(at) : active.frame(at);
      paintPet(element, layout, frame?.canvas, active.palette, frame?.bubbleAnchor);
    };
    draw(petClockNow());
    if (still || !visible) return;
    let timer = 0;
    let frame = 0;
    const scheduleNext = () => {
      const now = petClockNow();
      const next = active.nextChange(now, holdStill);
      if (next === undefined) return;
      /* A hair after the change, so rounding can't show the old frame. */
      const wait = Math.max(0, (next - now) * 1000 + 1);
      timer = window.setTimeout(() => {
        frame = requestAnimationFrame(() => {
          if (document.visibilityState === "hidden") return;
          draw(petClockNow());
          scheduleNext();
        });
      }, wait);
    };
    scheduleNext();
    const onVisibility = () => {
      window.clearTimeout(timer);
      cancelAnimationFrame(frame);
      if (document.visibilityState !== "hidden") {
        draw(petClockNow());
        scheduleNext();
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.clearTimeout(timer);
      cancelAnimationFrame(frame);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [active, layout, reduceMotion, still, visible, revision]);

  const name = active ? `${active.profile.name}, ${breedDisplayName(active.profile.breed)}` : "";
  return (
    <div
      className={["kit-pet", className].filter(Boolean).join(" ")}
      role="img"
      aria-label={name}
      style={{ width: layout.boxSize, height: layout.boxSize }}
    >
      <canvas ref={canvas} className="kit-pet-canvas" style={{ left: layout.offsetX, top: layout.offsetY }} />
    </div>
  );
}

export interface PetSpriteProps {
  readonly canvas?: PetCanvas;
  readonly palette?: PetPalette;
  /** The profile sitting in its own outfit, when no canvas is given. */
  readonly profile?: PetProfile;
  readonly pixelSize?: number;
  readonly className?: string;
}

/** One still pet picture (no animation), for thumbnails such as wardrobe tiles. */
export function PetSprite({ canvas, palette, profile, pixelSize = 1, className }: PetSpriteProps) {
  const element = useRef<HTMLCanvasElement>(null);
  const picture = useMemo(() => canvas ?? profile?.sittingCanvas(), [canvas, profile]);
  const colors = useMemo(() => palette ?? profile?.palette, [palette, profile]);
  const [ratio, setRatio] = useState(() => (typeof window === "undefined" ? 1 : window.devicePixelRatio || 1));
  const layout = useMemo(() => petLayout(pixelSize, ratio, picture?.width ?? FRAME_SIZE), [pixelSize, ratio, picture]);
  useEffect(() => {
    const query = window.matchMedia(`(resolution: ${ratio}dppx)`);
    const update = () => setRatio(window.devicePixelRatio || 1);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, [ratio]);
  useLayoutEffect(() => {
    if (!element.current || !colors) return;
    paintPet(element.current, layout, picture, colors);
  }, [layout, picture, colors]);
  return (
    <div className={["kit-pet", className].filter(Boolean).join(" ")} aria-hidden="true" style={{ width: layout.boxSize, height: layout.boxSize }}>
      <canvas ref={element} className="kit-pet-canvas" style={{ left: layout.offsetX, top: layout.offsetY }} />
    </div>
  );
}
