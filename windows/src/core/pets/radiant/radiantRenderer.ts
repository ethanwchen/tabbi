import { pixelFor, type PetCanvas } from "../petCanvas";
import { roleFromSymbol } from "../petPalette";
import type { PetPoint } from "../petPose";
import type { RadiantAnchor, RadiantArt, RadiantParticleMode, RadiantPlacement, RadiantRoles, RadiantZone } from "./radiantArt";

/*
 * Port of RadiantRenderer.swift: the zones around the pet in one frame
 * (RadiantGeometry), one Radiant item's pixels in that frame
 * (RadiantItemScene), what each effect's pieces draw (`radiantLayer`) and how
 * the effects land on the composed frame (`renderRadiant`), in the Mac's
 * exact order of operations, so every frame matches it pixel for pixel.
 *
 * Roles are canvas values here (`pixelFor(role)`, 0 for transparent), and
 * every integer division truncates like Swift's.
 */

const OUTLINE = pixelFor("outline");
const EFFECT_PIXELS: ReadonlySet<number> = new Set([pixelFor("effect"), pixelFor("effectFaint"), pixelFor("heart")]);
const EYE_PIXELS: ReadonlySet<number> = new Set([pixelFor("eye"), pixelFor("pupil"), pixelFor("eyeLight")]);
const FACE_PIXELS: ReadonlySet<number> = new Set([
  pixelFor("eye"),
  pixelFor("pupil"),
  pixelFor("eyeLight"),
  pixelFor("nose"),
  pixelFor("mouth"),
]);

/** Swift's integer division: truncated toward zero. */
function div(a: number, b: number): number {
  return Math.trunc(a / b);
}

/** A rectangle of frame pixels, inclusive. Port of RadiantBox. */
export class RadiantBox {
  constructor(
    readonly minX: number,
    readonly minY: number,
    readonly maxX: number,
    readonly maxY: number,
  ) {}

  get midX(): number {
    return div(this.minX + this.maxX, 2);
  }

  contains(x: number, y: number): boolean {
    return x >= this.minX && x <= this.maxX && y >= this.minY && y <= this.maxY;
  }

  /** The pixel `px` percent across and `py` percent down, rounded down. */
  at(px: number, py: number): PetPoint {
    return { x: this.minX + div((this.maxX - this.minX) * px, 100), y: this.minY + div((this.maxY - this.minY) * py, 100) };
  }

  static around(points: Iterable<PetPoint>): RadiantBox | undefined {
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const p of points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return minX === Infinity ? undefined : new RadiantBox(minX, minY, maxX, maxY);
  }
}

/**
 * Where the pet is in one frame, measured from the bare pet: its bounds, its
 * face, and the zones around it. The head runs from the pet's top row down
 * to the chin (two rows under the lowest eye, nose or mouth pixel); the zones
 * beside it are the columns left and right of the head's widest pixels, and
 * below the chin the columns beside the body's. Port of RadiantGeometry.
 */
export class RadiantGeometry {
  /** The roles of effects drawn around the pet, never part of it. */
  static readonly effectPixels = EFFECT_PIXELS;
  static readonly eyePixels = EYE_PIXELS;
  static readonly facePixels = FACE_PIXELS;
  /** How far around the eyes, nose and mouth nothing may be drawn over the pet. */
  static readonly faceMargin = 3;

  readonly pet: RadiantBox | undefined;
  /** The eyes, nose and mouth. */
  readonly face: RadiantBox | undefined;
  readonly top: number;
  readonly chin: number;
  readonly headMin: number;
  readonly headMax: number;
  readonly bodyMin: number;
  readonly bodyMax: number;

  constructor(bare: PetCanvas) {
    const petPoints: PetPoint[] = [];
    const facePoints: PetPoint[] = [];
    for (let y = 0; y < bare.height; y++) {
      for (let x = 0; x < bare.width; x++) {
        const pixel = bare.pixels[y * bare.width + x] ?? 0;
        if (pixel === 0 || EFFECT_PIXELS.has(pixel)) continue;
        petPoints.push({ x, y });
        if (FACE_PIXELS.has(pixel)) facePoints.push({ x, y });
      }
    }
    this.pet = RadiantBox.around(petPoints);
    this.face = RadiantBox.around(facePoints);
    this.top = this.pet?.minY ?? bare.height;
    this.chin = Math.min(bare.height - 1, (this.face?.maxY ?? this.top) + 2);
    let headMin = Infinity;
    let headMax = -Infinity;
    let bodyMin = Infinity;
    let bodyMax = -Infinity;
    for (const p of petPoints) {
      if (p.y <= this.chin) {
        headMin = Math.min(headMin, p.x);
        headMax = Math.max(headMax, p.x);
      } else {
        bodyMin = Math.min(bodyMin, p.x);
        bodyMax = Math.max(bodyMax, p.x);
      }
    }
    this.headMin = headMin === Infinity ? 0 : headMin;
    this.headMax = headMax === -Infinity ? 0 : headMax;
    const noBody = bodyMin === Infinity;
    this.bodyMin = noBody ? this.headMin : bodyMin;
    this.bodyMax = noBody ? this.headMax : bodyMax;
  }

  /** The face grown by `faceMargin`. */
  get faceGuard(): RadiantBox | undefined {
    const face = this.face;
    const m = RadiantGeometry.faceMargin;
    return face && new RadiantBox(face.minX - m, face.minY - m, face.maxX + m, face.maxY + m);
  }

  /** The zone a pixel is in, or undefined on the head itself. */
  zone(x: number, y: number): RadiantZone | undefined {
    if (!this.pet) return undefined;
    if (y < this.top) return x < this.headMin ? "topLeft" : x > this.headMax ? "topRight" : "aboveHead";
    if (y <= this.chin) return x < this.headMin ? "leftOfHead" : x > this.headMax ? "rightOfHead" : undefined;
    return x < this.bodyMin ? "leftOfBody" : x > this.bodyMax ? "rightOfBody" : "chest";
  }
}

/**
 * One Radiant item in a frame: the pixels it drew (the frame with it minus
 * the frame without it) and their bounds. Port of RadiantItemScene.
 */
export class RadiantItemScene {
  /** Per frame pixel, the item's canvas value there, or 0. */
  readonly pixels: Uint8Array;
  readonly width: number;
  /** The item's pixel indices in reading order. */
  readonly ordered: readonly number[];
  /** Bounds of the item's pixels, outline left out. */
  readonly box: RadiantBox | undefined;

  constructor(withItem: PetCanvas, without: PetCanvas) {
    const pixels = new Uint8Array(withItem.pixels.length);
    const ordered: number[] = [];
    const width = withItem.width;
    const lined: PetPoint[] = [];
    for (let i = 0; i < withItem.pixels.length; i++) {
      const pixel = withItem.pixels[i] ?? 0;
      if (pixel === 0 || pixel === without.pixels[i]) continue;
      pixels[i] = pixel;
      ordered.push(i);
      if (pixel !== OUTLINE) lined.push({ x: i % width, y: div(i, width) });
    }
    this.pixels = pixels;
    this.ordered = ordered;
    this.width = width;
    this.box = RadiantBox.around(lined);
  }

  /** Whether the item drew the pixel at frame index `index` (any index, like the Mac's dictionary lookup). */
  has(index: number): boolean {
    return index >= 0 && index < this.pixels.length && this.pixels[index] !== 0;
  }

  point(index: number): PetPoint {
    return { x: index % this.width, y: div(index, this.width) };
  }

  /** The item's pixels of `roles`, in reading order. */
  points(roles: RadiantRoles): PetPoint[] {
    const out: PetPoint[] = [];
    for (const index of this.ordered) if (roles.has(this.pixels[index] ?? 0)) out.push(this.point(index));
    return out;
  }
}

/** One drawn pixel of a particle: where and which canvas value. */
export interface RadiantDot {
  readonly x: number;
  readonly y: number;
  readonly pixel: number;
}

export interface RadiantParticle {
  readonly pixels: readonly RadiantDot[];
  readonly mode: RadiantParticleMode;
  /** For an orbit: the near side, drawn in front of the pet. */
  readonly near: boolean;
}

/** What one effect draws in a frame before it is placed. Port of RadiantLayer. */
export interface RadiantLayer {
  /** Item pixels recolored, by frame index (point `y * width + x`), in the order set. */
  readonly recolor: Map<string, RadiantDot>;
  /** Item pixels moved over the fur (a swinging tassel). */
  readonly moves: { readonly from: readonly PetPoint[]; readonly to: readonly RadiantDot[] }[];
  readonly particles: RadiantParticle[];
}

/**
 * What `renderRadiant` did, for the tests: which effect drew each pixel,
 * and how many particle pixels another effect's pixels kept out.
 */
export interface RadiantRenderReport {
  /** Per frame pixel, the index of the job that drew it, or -1. */
  owner: Int32Array;
  collisions: number;
}

export function newRadiantReport(): RadiantRenderReport {
  return { owner: new Int32Array(0), collisions: 0 };
}

/** One effect to draw: its placement, the tick of its own loop, and its item in this frame. */
export interface RadiantJob {
  readonly placement: RadiantPlacement;
  readonly tick: number;
  readonly item: RadiantItemScene;
}

/**
 * Draws `jobs` in order onto `dressed` (the pet in all its items, with its
 * effects). Recolors land only on each effect's own item; moved pixels only
 * on fur outside the face; particles only in their placement's zones, in
 * the free air (or, for an orbit's near side, over fur outside the face),
 * never on or beside a pixel another effect drew, inside a one-pixel margin
 * and below `ceiling`. Nothing floats while the pet hangs from the notch.
 * Port of RadiantRenderer.render.
 */
export function renderRadiant(
  jobs: readonly RadiantJob[],
  dressed: PetCanvas,
  bare: PetCanvas,
  options: {
    geometry?: RadiantGeometry;
    hanging: boolean;
    ceiling: number | undefined;
    art: RadiantArt;
    report: RadiantRenderReport;
  },
): PetCanvas {
  const geometry = options.geometry ?? new RadiantGeometry(bare);
  const { hanging, art, report } = options;
  const out = dressed.copy();
  const width = dressed.width;
  const height = dressed.height;
  const top = Math.max(1, options.ceiling ?? 1);
  const index = (x: number, y: number) => y * width + x;
  const inBounds = (x: number, y: number) => x >= 1 && x <= width - 2 && y >= top && y <= height - 2;
  /** The dressed pixel, 0 when transparent or off the frame. */
  const at = (x: number, y: number) => dressed.pixel(x, y);
  if (report.owner.length !== width * height) report.owner = new Int32Array(width * height).fill(-1);
  const owner = report.owner;
  const ownerAt = (x: number, y: number) => (x >= 0 && y >= 0 && x < width && y < height ? (owner[y * width + x] ?? -1) : -1);
  /** The owner at a raw index, like the Mac's array subscript (the index is always in the frame there). */
  const ownerIndex = (i: number) => owner[i] ?? -1;
  const faceGuard = geometry.faceGuard;
  const inFace = (x: number, y: number) => faceGuard?.contains(x, y) ?? false;
  /** Fur: part of the bare pet, not covered by an item or effect. */
  const isFur = (x: number, y: number) => {
    const pixel = at(x, y);
    if (pixel === 0) return false;
    return bare.pixel(x, y) === pixel && !FACE_PIXELS.has(pixel) && !EFFECT_PIXELS.has(pixel);
  };
  const emptyAround = (x: number, y: number) => at(x - 1, y) === 0 && at(x + 1, y) === 0 && at(x, y - 1) === 0 && at(x, y + 1) === 0;
  const filledAround = (x: number, y: number) => at(x - 1, y) !== 0 && at(x + 1, y) !== 0 && at(x, y - 1) !== 0 && at(x, y + 1) !== 0;

  jobs.forEach((job, n) => {
    const layer = radiantLayer(job, geometry, art);
    const item = job.item;
    const mine = (o: number) => o === -1 || o === n;
    /** Free of every other effect's pixels, and of the space beside them. */
    const clearOfOthers = (x: number, y: number) =>
      mine(ownerAt(x, y)) && mine(ownerAt(x - 1, y)) && mine(ownerAt(x + 1, y)) && mine(ownerAt(x, y - 1)) && mine(ownerAt(x, y + 1));
    const claim = (x: number, y: number, pixel: number) => {
      out.setPixel(x, y, pixel);
      owner[index(x, y)] = n;
    };
    for (const dot of layer.recolor.values()) {
      if (item.has(index(dot.x, dot.y))) claim(dot.x, dot.y, dot.pixel);
    }
    for (const move of layer.moves) {
      /* Onto fur or the item's own pixels (inner lines included), never onto the silhouette's edge. */
      const fits = move.to.every((p) => {
        const own = item.has(index(p.x, p.y));
        return (
          inBounds(p.x, p.y) &&
          (isFur(p.x, p.y) || own) &&
          !inFace(p.x, p.y) &&
          mine(ownerIndex(index(p.x, p.y))) &&
          filledAround(p.x, p.y)
        );
      });
      if (!fits) continue;
      for (const p of move.from) {
        if (!item.has(index(p.x, p.y))) continue;
        out.setPixel(p.x, p.y, bare.pixel(p.x, p.y));
        owner[index(p.x, p.y)] = n;
      }
      for (const p of move.to) claim(p.x, p.y, p.pixel);
    }
    if (hanging) return;
    const zones = job.placement.zones;
    const inZone = (x: number, y: number) => {
      const zone = geometry.zone(x, y);
      return zone !== undefined && zones.has(zone);
    };
    const free = (x: number, y: number) => inBounds(x, y) && inZone(x, y) && at(x, y) === 0 && emptyAround(x, y);
    const besideItem = (x: number, y: number) => at(x, y) === 0 || item.has(index(x, y));
    const freeBesideItem = (x: number, y: number) =>
      inBounds(x, y) &&
      inZone(x, y) &&
      at(x, y) === 0 &&
      besideItem(x - 1, y) &&
      besideItem(x + 1, y) &&
      besideItem(x, y - 1) &&
      besideItem(x, y + 1);
    for (const particle of layer.particles) {
      const kind = particle.mode === "air" || (particle.mode === "orbit" && !particle.near) ? "whole" : particle.mode === "orbit" ? "front" : "pixels";
      if (kind === "whole") {
        if (!particle.pixels.every((p) => free(p.x, p.y))) continue;
        if (!particle.pixels.every((p) => clearOfOthers(p.x, p.y))) {
          report.collisions += particle.pixels.length;
          continue;
        }
        for (const p of particle.pixels) claim(p.x, p.y, p.pixel);
      } else if (kind === "pixels") {
        const beside = particle.mode === "behindItem";
        for (const p of particle.pixels) {
          if (!(beside ? freeBesideItem(p.x, p.y) : free(p.x, p.y))) continue;
          if (!clearOfOthers(p.x, p.y)) {
            report.collisions += 1;
            continue;
          }
          claim(p.x, p.y, p.pixel);
        }
      } else {
        const own = new Set(particle.pixels.map((p) => index(p.x, p.y)));
        const ringIndices = new Set<number>();
        for (const p of particle.pixels) {
          for (const [x, y] of [
            [p.x - 1, p.y],
            [p.x + 1, p.y],
            [p.x, p.y - 1],
            [p.x, p.y + 1],
          ] as const) {
            if (!own.has(index(x, y)) && at(x, y) !== 0) ringIndices.add(index(x, y));
          }
        }
        const ring = [...ringIndices].sort((a, b) => a - b).map((i) => ({ x: i % width, y: div(i, width) }));
        const fits =
          particle.pixels.every((p) => inBounds(p.x, p.y) && inZone(p.x, p.y) && !inFace(p.x, p.y) && (at(p.x, p.y) === 0 || isFur(p.x, p.y))) &&
          ring.every((p) => inBounds(p.x, p.y) && inZone(p.x, p.y) && !inFace(p.x, p.y) && isFur(p.x, p.y));
        if (!fits) continue;
        if (!particle.pixels.every((p) => clearOfOthers(p.x, p.y)) || !ring.every((p) => clearOfOthers(p.x, p.y))) {
          report.collisions += particle.pixels.length;
          continue;
        }
        for (const p of particle.pixels) claim(p.x, p.y, p.pixel);
        for (const p of ring) claim(p.x, p.y, OUTLINE);
      }
    }
  });
  return out;
}

/* MARK: Pieces */

function pointKey(p: PetPoint): string {
  return `${p.x},${p.y}`;
}

/** What one effect's pieces draw in a frame. Port of RadiantRenderer.layer. */
export function radiantLayer(job: RadiantJob, geometry: RadiantGeometry, art: RadiantArt): RadiantLayer {
  const recolor = new Map<string, RadiantDot>();
  const moves: { from: PetPoint[]; to: RadiantDot[] }[] = [];
  const particles: RadiantParticle[] = [];
  const { tick, item } = job;
  const loop = art.loop;
  const slot = tick % loop;
  const setColor = (p: PetPoint, pixel: number) => {
    const key = pointKey(p);
    /* A Swift dictionary keeps a key's place when it is set again; so does a Map. */
    recolor.set(key, { x: p.x, y: p.y, pixel });
  };
  const anchorPoint = (anchor: RadiantAnchor): PetPoint | undefined => {
    let base: PetPoint | undefined;
    switch (anchor.origin) {
      case "item":
        base = item.box?.at(anchor.x, anchor.y);
        break;
      case "itemTip": {
        let topY = Infinity;
        let tip: PetPoint | undefined;
        for (const i of item.ordered) {
          if (item.pixels[i] === OUTLINE) continue;
          const p = item.point(i);
          if (p.y < topY) {
            topY = p.y;
            tip = p;
          } else if (p.y === topY && tip && p.x > tip.x) {
            tip = p;
          }
        }
        base = tip;
        break;
      }
      case "pet":
        base = geometry.pet?.at(anchor.x, anchor.y);
        break;
      case "itemRole":
        base = RadiantBox.around(item.points(new Set([anchor.role ?? 0])))?.at(anchor.x, anchor.y);
        break;
    }
    return base && { x: base.x + anchor.dx, y: base.y + anchor.dy };
  };
  const shape = (name: string, center: PetPoint): RadiantDot[] =>
    (art.shapes.get(name)?.pixels ?? []).map((pixel) => ({ x: center.x + pixel.dx, y: center.y + pixel.dy, pixel: pixel.pixel }));

  for (const piece of job.placement.pieces) {
    switch (piece.type) {
      case "glint": {
        const position = piece.positions[slot];
        if (position === null || position === undefined) break;
        const points = item.points(piece.roles);
        if (points.length === 0) break;
        const minX = Math.min(...points.map((p) => p.x));
        const minY = Math.min(...points.map((p) => p.y));
        const mid = item.box?.midX ?? minX;
        for (const p of points) {
          if (piece.rows !== undefined && p.y - minY >= piece.rows) continue;
          if (piece.near !== undefined && Math.abs(p.x - mid) > piece.near) continue;
          const diagonal = piece.slant * (p.x - minX) + piece.slope * (p.y - minY);
          if (diagonal >= position && diagonal < position + piece.width) setColor(p, piece.color);
        }
        break;
      }
      case "blink": {
        if (!piece.ticks.has(slot)) break;
        const points = item.points(piece.roles);
        for (const n of piece.which) {
          const i = n < 0 ? points.length + n : n;
          const p = points[i];
          if (i >= 0 && p) setColor(p, piece.color);
        }
        break;
      }
      case "hop": {
        const g = piece.groups[slot];
        const box = item.box;
        if (g === null || g === undefined || !box) break;
        const limit = box.minY + div((box.maxY - box.minY) * piece.abovePercent, 100);
        const points = item.points(piece.roles).filter((p) => p.y <= limit);
        const runs: number[][] = [];
        for (const x of [...new Set(points.map((p) => p.x))].sort((a, b) => a - b)) {
          const last = runs[runs.length - 1];
          const lastX = last?.[last.length - 1];
          if (last && lastX !== undefined && x === lastX + 1) last.push(x);
          else runs.push([x]);
        }
        if (runs.length === 0) break;
        const run = runs[g % runs.length] ?? [];
        const tops: PetPoint[] = [];
        for (const x of run) {
          let best: PetPoint | undefined;
          for (const p of points) if (p.x === x && (!best || p.y < best.y)) best = p;
          if (best) {
            setColor(best, piece.color);
            tops.push(best);
          }
        }
        if (piece.spark !== undefined && tops.length > 0) {
          let highest = tops[0] as PetPoint;
          for (const p of tops) if (p.y < highest.y || (p.y === highest.y && p.x < highest.x)) highest = p;
          const center = { x: run[div(run.length, 2)] ?? 0, y: highest.y - 2 };
          particles.push({ pixels: shape(piece.spark, center), mode: "air", near: false });
        }
        break;
      }
      case "particles": {
        const origin = anchorPoint(piece.anchor);
        if (!origin) break;
        piece.starts.forEach((start, n) => {
          const age = (((tick - start) % loop) + loop) % loop;
          const look = piece.looks[age];
          const step = piece.path[age];
          if (age >= piece.path.length || look === null || look === undefined || !step) return;
          let pixels = shape(look, { x: origin.x + (step[0] ?? 0), y: origin.y + (step[1] ?? 0) });
          let axis: number | undefined;
          if (piece.mirror === "alternate") {
            const box = geometry.face ?? geometry.pet;
            axis = n % 2 === 1 && box ? box.minX + box.maxX : undefined;
          } else if (piece.mirror === "item") {
            axis = item.box ? item.box.minX + item.box.maxX : undefined;
          }
          if (axis !== undefined) {
            const mirrorAxis = axis;
            pixels = pixels.map((p) => ({ x: mirrorAxis - p.x, y: p.y, pixel: p.pixel }));
          }
          particles.push({ pixels, mode: piece.mode, near: step.length > 2 && step[2] === 1 });
        });
        break;
      }
      case "fixed": {
        const look = piece.looks[slot];
        const origin = look === null || look === undefined ? undefined : anchorPoint(piece.anchor);
        if (look === null || look === undefined || !origin) break;
        const center = { x: origin.x + (piece.offset[0] ?? 0), y: origin.y + (piece.offset.length > 1 ? (piece.offset[1] ?? 0) : 0) };
        particles.push({ pixels: shape(look, center), mode: piece.mode, near: false });
        break;
      }
      case "swing": {
        const dx = piece.steps[slot] ?? 0;
        const box = item.box;
        if (dx === 0 || !box) break;
        const from = box.midX + piece.fromMid;
        const to = Math.max(from, box.maxX + piece.toMax);
        const pieceAt = item.points(piece.roles).filter((p) => p.x >= from && p.x <= to);
        if (pieceAt.length === 0) break;
        const pieceTop = Math.min(...pieceAt.map((p) => p.y));
        const moving = pieceAt.filter((p) => p.y >= pieceTop + piece.fromRow);
        if (moving.length === 0) break;
        moves.push({
          from: moving,
          to: moving.map((p) => ({ x: p.x + dx, y: p.y, pixel: item.pixels[p.y * item.width + p.x] ?? 0 })),
        });
        break;
      }
      case "grid": {
        const shown = piece.columns[slot];
        if (!shown || shown.length !== 2) break;
        const origin = anchorPoint(piece.anchor);
        if (!origin) break;
        const [first = 0, last = 0] = shown;
        const pixels: RadiantDot[] = [];
        piece.rows.forEach((row, y) => {
          [...row].forEach((symbol, x) => {
            if (x < first || x >= last) return;
            const pixel = symbolPixel(symbol);
            if (pixel !== 0) pixels.push({ x: origin.x + x, y: origin.y + y, pixel });
          });
        });
        particles.push({ pixels, mode: piece.mode, near: false });
        break;
      }
      case "trace": {
        const pen = piece.pens[slot];
        const pet = geometry.pet;
        if (pen === null || pen === undefined || !pet) break;
        const base = pet.minY + piece.baseline;
        const start = pet.minX + piece.left;
        const pixels: RadiantDot[] = [];
        for (let i = Math.max(0, pen - piece.window); i <= pen; i++) {
          if (i >= piece.pulse.length) continue;
          const y = base + (piece.pulse[i] ?? 0);
          const previous = i > 0 ? base + (piece.pulse[i - 1] ?? 0) : y;
          const pixel = i === pen ? piece.pen : i < pen - div(piece.window, 2) ? piece.fade : piece.line;
          for (let row = Math.min(y, previous); row <= Math.max(y, previous); row++) pixels.push({ x: start + i, y: row, pixel });
        }
        particles.push({ pixels, mode: "behind", near: false });
        break;
      }
      case "surfaceTrace": {
        const pen = piece.pens[slot];
        const box = item.box;
        if (pen === null || pen === undefined || !box) break;
        const base = box.minY + div((box.maxY - box.minY) * piece.rowPercent, 100);
        const start = box.minX + 1;
        const surface = new Set(item.points(piece.roles).map(pointKey));
        for (let i = Math.max(0, pen - piece.window); i <= pen; i++) {
          if (i >= piece.pulse.length) continue;
          const y = base + (piece.pulse[i] ?? 0);
          const previous = i > 0 ? base + (piece.pulse[i - 1] ?? 0) : y;
          for (let row = Math.min(y, previous); row <= Math.max(y, previous); row++) {
            const p = { x: start + i, y: row };
            if (surface.has(pointKey(p))) setColor(p, i === pen ? piece.pen : piece.line);
          }
        }
        break;
      }
      case "satellite": {
        const center = anchorPoint(piece.anchor);
        if (!center) break;
        const planet = shape(piece.body, center);
        const step = piece.moon[slot] ?? [0, 0, 0];
        const spot = { x: center.x + (step[0] ?? 0), y: center.y + (step[1] ?? 0) };
        const covered = planet.some((p) => p.x === spot.x && p.y === spot.y);
        particles.push({ pixels: planet, mode: "air", near: false });
        if (step[2] === 1) particles.push({ pixels: [{ ...spot, pixel: piece.near }], mode: "air", near: false });
        else if (!covered) particles.push({ pixels: [{ ...spot, pixel: piece.far }], mode: "air", near: false });
        break;
      }
    }
  }
  return { recolor, moves, particles };
}

const SYMBOL_PIXELS = new Map<string, number>();

/** A grid symbol's canvas value, 0 for `.` or an unknown symbol. */
function symbolPixel(symbol: string): number {
  let pixel = SYMBOL_PIXELS.get(symbol);
  if (pixel === undefined) {
    const role = roleFromSymbol(symbol);
    pixel = role === undefined ? 0 : pixelFor(role);
    SYMBOL_PIXELS.set(symbol, pixel);
  }
  return pixel;
}
