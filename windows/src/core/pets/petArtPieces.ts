import { petArt } from "./petArt";
import type { PetEyes, PetMouth, PetPoint } from "./petPose";
import { EMPTY_CELL, SpriteGrid, roleCell, zoneCell } from "./spriteGrid";

/*
 * Ports of the Mac's art namespaces (CatArt, DogArt, EffectArt, PawArt,
 * PropArt, TailArt, WalkArt): named grids from the JSON art, plus the
 * procedural pieces (legs, wrapped tails, eye states) the Swift generates.
 * Everything here is a pure function of the art, so results are memoized:
 * the composer asks for the same pieces thousands of times.
 */

const cells = {
  eye: roleCell("eye"),
  pupil: roleCell("pupil"),
  eyeLight: roleCell("eyeLight"),
  outline: roleCell("outline"),
  blush: roleCell("blush"),
  nose: roleCell("nose"),
  furBase: roleCell("furBase"),
  furShade: roleCell("furShade"),
  paws: zoneCell("paws"),
  stripes: zoneCell("stripes"),
  tailTip: zoneCell("tailTip"),
};

function memo<Value>(make: () => Value): () => Value {
  let value: Value | undefined;
  return () => {
    if (value === undefined) value = make();
    return value;
  };
}

/** Port of CatArt: the cat heads, faces and sitting bodies. */
export const CatArt = {
  head: memo(() => petArt("cat").grid("head")),
  headRound: memo(() => petArt("cat").grid("headRound")),
  faceRound: memo(() => petArt("cat").grid("faceRound")),
  faceOpen: memo(() => petArt("cat").grid("faceOpen")),
  bodySit: memo(() => petArt("cat").grid("bodySit")),
  bodyRound: memo(() => petArt("cat").grid("bodyRound")),
  headSphynx: memo(() => petArt("cat").grid("headSphynx")),
  faceSphynx: memo(() => petArt("cat").grid("faceSphynx")),
  bodySphynx: memo(() => petArt("cat").grid("bodySphynx")),
  headFold: memo(() => petArt("cat").grid("headFold")),
  bodyFold: memo(() => petArt("cat").grid("bodyFold")),
  headLonghair: memo(() => petArt("cat").grid("headLonghair")),
  faceLonghair: memo(() => petArt("cat").grid("faceLonghair")),
  bodyLonghair: memo(() => petArt("cat").grid("bodyLonghair")),
};

/** Port of DogArt. */
export const DogArt = {
  headFloppy: memo(() => petArt("dog").grid("headFloppy")),
  headFluffy: memo(() => petArt("dog").grid("headFluffy")),
  headBatEared: memo(() => petArt("dog").grid("headBatEared")),
  headPointyEared: memo(() => petArt("dog").grid("headPointyEared")),
  headLong: memo(() => petArt("dog").grid("headLong")),
  faceOpen: memo(() => petArt("dog").grid("faceOpen")),
  faceLongSnout: memo(() => petArt("dog").grid("faceLongSnout")),
  bodySit: memo(() => petArt("dog").grid("bodySit")),
  tailUp: memo(() => petArt("dog").grid("tailUp")),
  bodyLong: memo(() => petArt("dog").grid("bodyLong")),
  headPoodle: memo(() => petArt("dog").grid("headPoodle")),
  bodyPoodle: memo(() => petArt("dog").grid("bodyPoodle")),
  tailPom: memo(() => petArt("dog").grid("tailPom")),
  headShihTzu: memo(() => petArt("dog").grid("headShihTzu")),
  faceShihTzu: memo(() => petArt("dog").grid("faceShihTzu")),
  bodyShihTzu: memo(() => petArt("dog").grid("bodyShihTzu")),
  tailPlume: memo(() => petArt("dog").grid("tailPlume")),
};

/** Port of PropArt: the laptop, mug and toys of the study moments. */
export const PropArt = {
  laptop: memo(() => petArt("prop").grid("laptop")),
  paw: memo(() => petArt("prop").grid("paw")),
  mug: memo(() => petArt("prop").grid("mug")),
  mugPaw: memo(() => petArt("prop").grid("mugPaw")),
  steam: memo(() => petArt("prop").sequence("steam")),
  yarn: memo(() => petArt("prop").sequence("yarn")),
  ball: memo(() => petArt("prop").sequence("ball")),
};

/** Port of EffectArt: eye states, mouths, the "z", heart, sparkle and dust. */
export const EffectArt = {
  eyesClosed: memo(() => petArt("effect").grid("eyesClosed")),
  eyesSleepy: memo(() => petArt("effect").grid("eyesSleepy")),
  eyesSqueezed: memo(() => petArt("effect").grid("eyesSqueezed")),
  eyesHappy: memo(() => petArt("effect").grid("eyesHappy")),
  dustLeft: memo(() => petArt("effect").grid("dustLeft")),
  dustRight: memo(() => petArt("effect").grid("dustRight")),
  mouthOpen: memo(() => petArt("effect").grid("mouthOpen")),
  mouthWide: memo(() => petArt("effect").grid("mouthWide")),
  mouthOpenBelowNose: memo(() => petArt("effect").grid("mouthOpenBelowNose")),
  mouthWideBelowNose: memo(() => petArt("effect").grid("mouthWideBelowNose")),
};

const mouthCache = new WeakMap<SpriteGrid, Map<PetMouth, { grid: SpriteGrid; origin: PetPoint } | null>>();

/**
 * Where an open mouth goes on `face`: four pixels wide, centered on the
 * nose's top row, on the first row below the nose. A mouth line in the nose
 * color right under the nose means the mouth hangs from it and opens a row
 * lower. Undefined when closed or without a nose.
 */
export function mouthPlacement(mouth: PetMouth, face: SpriteGrid): { grid: SpriteGrid; origin: PetPoint } | undefined {
  if (mouth === "closed") return undefined;
  let byMouth = mouthCache.get(face);
  if (!byMouth) {
    byMouth = new Map();
    mouthCache.set(face, byMouth);
  }
  const cached = byMouth.get(mouth);
  if (cached !== undefined) return cached ?? undefined;
  const result = computeMouth(mouth, face);
  byMouth.set(mouth, result ?? null);
  return result;
}

function computeMouth(mouth: PetMouth, face: SpriteGrid): { grid: SpriteGrid; origin: PetPoint } | undefined {
  const isNose = (x: number, y: number) => x >= 0 && x < face.width && face.code(x, y) === cells.nose;
  const rowHasNose = (y: number) => {
    for (let x = 0; x < face.width; x++) if (isNose(x, y)) return true;
    return false;
  };
  let top = -1;
  for (let y = 0; y < face.height; y++) {
    if (rowHasNose(y)) {
      top = y;
      break;
    }
  }
  if (top < 0) return undefined;
  const columns: number[] = [];
  for (let x = 0; x < face.width; x++) if (isNose(x, top)) columns.push(x);
  const center = Math.floor(((columns[0] ?? 0) + (columns[columns.length - 1] ?? 0) + 1) / 2);
  let row = top + 1;
  while (row < face.height && (isNose(center - 1, row) || isNose(center, row))) row += 1;
  const hangs = row < face.height && rowHasNose(row);
  let shape: SpriteGrid;
  if (mouth === "wide") shape = hangs ? EffectArt.mouthWideBelowNose() : EffectArt.mouthWide();
  else shape = hangs ? EffectArt.mouthOpenBelowNose() : EffectArt.mouthOpen();
  return { grid: shape, origin: { x: center - 2, y: row } };
}

/** A front leg reaching up to the top edge, paw first, for hanging out of the notch. */
export function hangingLeg(length: number): SpriteGrid {
  const leg = new SpriteGrid(4, Math.max(3, length));
  for (let y = 0; y < leg.height; y++) {
    for (let x = 0; x < leg.width; x++) {
      const isPaw = y < 2;
      /* Rounded paw tip: the toe row is one pixel narrower per side. */
      if (y === 0 && (x === 0 || x === 3)) continue;
      leg.setCode(x, y, isPaw ? cells.paws : x === 0 || x === 3 ? EMPTY_CELL : cells.furBase);
    }
  }
  return leg;
}

const faceCache = new WeakMap<SpriteGrid, Map<string, SpriteGrid>>();

/**
 * `face` with its open eyes replaced by `eyes`, found as the eye-colored
 * pixels on `eyeRow`. Asleep, a panting tongue below the cheek row is
 * cleared too, so the mouth closes.
 */
export function faceWithEyes(face: SpriteGrid, eyeRow: number, eyes: PetEyes): SpriteGrid {
  if (eyes === "open") return face;
  const key = `${eyeRow}:${eyes}`;
  let byKey = faceCache.get(face);
  if (!byKey) {
    byKey = new Map();
    faceCache.set(face, byKey);
  }
  const cached = byKey.get(key);
  if (cached) return cached;
  const result = computeFace(face, eyeRow, eyes);
  byKey.set(key, result);
  return result;
}

function computeFace(face: SpriteGrid, eyeRow: number, eyes: Exclude<PetEyes, "open">): SpriteGrid {
  const overlay =
    eyes === "closed"
      ? EffectArt.eyesClosed()
      : eyes === "sleepy"
        ? EffectArt.eyesSleepy()
        : eyes === "happy"
          ? EffectArt.eyesHappy()
          : EffectArt.eyesSqueezed();
  const result = face.copy();
  if (eyes === "sleepy") {
    for (let y = Math.min(face.height, eyeRow + 4); y < face.height; y++) {
      for (let x = 0; x < face.width; x++) if (face.code(x, y) === cells.blush) result.setCode(x, y, EMPTY_CELL);
    }
  }
  /* A pupil drawn in the outline color is part of the eye it sits in. */
  const isEye = (code: number) =>
    code === cells.eye || code === cells.pupil || code === cells.eyeLight || code === cells.outline;
  const lefts: number[] = [];
  for (let x = 0; x < face.width; x++) {
    if (isEye(face.code(x, eyeRow)) && (x === 0 || !isEye(face.code(x - 1, eyeRow)))) lefts.push(x);
  }
  for (const left of lefts) {
    let run = 0;
    while (left + run < face.width && isEye(face.code(left + run, eyeRow))) run += 1;
    const width = Math.max(2, run);
    for (let y = eyeRow; y < Math.min(face.height, eyeRow + 3); y++) {
      for (let x = left; x < Math.min(face.width, left + width); x++) {
        if (isEye(face.code(x, y))) result.setCode(x, y, EMPTY_CELL);
      }
    }
    /* The overlay's spare pixel goes toward the cheek: left of a left eye, right of a right eye. */
    const isRightEye = left * 2 + width > face.width;
    const start = isRightEye && width > 2 ? left : left - 1;
    for (let y = 0; y < overlay.height; y++) {
      for (let x = 0; x < overlay.width; x++) {
        const code = overlay.code(x, y);
        if (code === EMPTY_CELL) continue;
        const fx = start + (isRightEye ? overlay.width - 1 - x : x);
        const fy = eyeRow + y;
        if (fx >= 0 && fx < face.width && fy < face.height) result.setCode(fx, fy, code);
      }
    }
  }
  return result;
}

/** Port of PawArt: the waving paw and the grooming arm. */
export const PawArt = {
  wave: memo(() => petArt("paw").sequence("wave")),
  groomPaw: memo(() => petArt("paw").grid("groomPaw")),
};

const groomCache = new Map<number, SpriteGrid>();

/** A raised front leg `height` rows long, the paw at its top. */
export function groomArm(height: number): SpriteGrid {
  const cached = groomCache.get(height);
  if (cached) return cached;
  const paw = PawArt.groomPaw();
  const arm = new SpriteGrid(paw.width, Math.max(paw.height + 1, height));
  const leg = [EMPTY_CELL, cells.outline, cells.furBase];
  for (let y = 0; y < arm.height; y++) {
    for (let x = 0; x < arm.width; x++) {
      arm.setCode(x, y, y < paw.height ? paw.code(x, y) : (leg[Math.min(x, 5 - x)] ?? EMPTY_CELL));
    }
  }
  groomCache.set(height, arm);
  return arm;
}

const liftCache = new WeakMap<SpriteGrid, SpriteGrid>();

/**
 * The sitting body with its left front paw lifted off the floor: the paw
 * is flooded from the floor row and cleared, leaving a shade line where it
 * met the fur.
 */
export function liftingLeftPaw(body: SpriteGrid): SpriteGrid {
  const cached = liftCache.get(body);
  if (cached) return cached;
  const result = computeLift(body);
  liftCache.set(body, result);
  return result;
}

function computeLift(body: SpriteGrid): SpriteGrid {
  const bottom = body.height - 1;
  const isPaw = (x: number, y: number) => body.code(x, y) === cells.paws;
  let start = -1;
  for (let x = 0; x < Math.floor(body.width / 2); x++) {
    if (isPaw(x, bottom)) {
      start = x;
      break;
    }
  }
  if (start < 0) return body;
  const key = (x: number, y: number) => y * body.width + x;
  const paw = new Set<number>([key(start, bottom)]);
  const queue: [number, number][] = [[start, bottom]];
  while (queue.length > 0) {
    const [cx, cy] = queue.pop() ?? [0, 0];
    for (const [dx, dy] of [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ] as const) {
      const x = cx + dx;
      const y = cy + dy;
      if (x < 0 || x >= body.width || y < 0 || y >= body.height || !isPaw(x, y) || paw.has(key(x, y))) continue;
      paw.add(key(x, y));
      queue.push([x, y]);
    }
  }
  const result = body.copy();
  const isFur = (x: number, y: number) =>
    x >= 0 && x < body.width && body.code(x, y) !== EMPTY_CELL && !paw.has(key(x, y));
  for (const cell of paw) {
    const x = cell % body.width;
    const y = (cell - x) / body.width;
    result.setCode(x, y, y < bottom && (isFur(x - 1, y) || isFur(x + 1, y)) ? cells.furShade : EMPTY_CELL);
  }
  /* The floor row loses the paw's whole run, cuffs included. */
  let x = start;
  while (x > 0 && body.code(x - 1, bottom) !== EMPTY_CELL) x -= 1;
  while (x < body.width && body.code(x, bottom) !== EMPTY_CELL) {
    result.setCode(x, bottom, EMPTY_CELL);
    x += 1;
  }
  return result;
}

/** Port of TailArt: cutting, swinging and wrapping tails. */
export const TailArt = {
  nub: memo(() => petArt("tail").grid("nub")),
};

const splitCache = new WeakMap<SpriteGrid, Map<number, { body: SpriteGrid; tail: SpriteGrid }>>();

/** Splits a tail drawn into a body at `column`, so the swish can bend it on its own. */
export function splitTail(body: SpriteGrid, column: number): { body: SpriteGrid; tail: SpriteGrid } {
  let byColumn = splitCache.get(body);
  if (!byColumn) {
    byColumn = new Map();
    splitCache.set(body, byColumn);
  }
  const cached = byColumn.get(column);
  if (cached) return cached;
  const rest = body.copy();
  const tail = new SpriteGrid(body.width, body.height);
  for (let y = 0; y < body.height; y++) {
    for (let x = column; x < body.width; x++) {
      tail.setCode(x, y, body.code(x, y));
      rest.setCode(x, y, EMPTY_CELL);
    }
  }
  const result = { body: rest, tail };
  byColumn.set(column, result);
  return result;
}

const swingCache = new WeakMap<SpriteGrid, Map<string, SpriteGrid>>();

/**
 * The tail leaned `swing` pixels to the right at its tip, bending evenly to
 * nothing at its base, never past `room` columns of the frame.
 */
export function swungTail(tail: SpriteGrid, swing: number, room: number): SpriteGrid {
  const key = `${swing}:${room}`;
  let byKey = swingCache.get(tail);
  if (!byKey) {
    byKey = new Map();
    swingCache.set(tail, byKey);
  }
  const cached = byKey.get(key);
  if (cached) return cached;
  const result = computeSwing(tail, swing, room);
  byKey.set(key, result);
  return result;
}

function computeSwing(tail: SpriteGrid, swingIn: number, room: number): SpriteGrid {
  const rows: number[] = [];
  for (let y = 0; y < tail.height; y++) {
    for (let x = 0; x < tail.width; x++) {
      if (tail.code(x, y) !== EMPTY_CELL) {
        rows.push(y);
        break;
      }
    }
  }
  let right = 0;
  for (let x = 0; x < tail.width; x++) {
    for (let y = 0; y < tail.height; y++) {
      if (tail.code(x, y) !== EMPTY_CELL) {
        right = x;
        break;
      }
    }
  }
  const swing = Math.min(swingIn, room - 1 - right);
  const top = rows[0];
  const base = rows[rows.length - 1];
  if (!(swing > 0) || top === undefined || base === undefined || !(base > top)) return tail;
  const bent = new SpriteGrid(tail.width + swing, tail.height);
  for (let y = 0; y < tail.height; y++) {
    const lean = (swing * (base - y)) / (base - top);
    const shift = Math.min(Math.max(Math.round(lean), 0), base - y);
    for (let x = 0; x < tail.width; x++) {
      const code = tail.code(x, y);
      if (code !== EMPTY_CELL) bent.setCode(x + shift, y, code);
    }
  }
  return bent;
}

const wrapCache = new Map<number, SpriteGrid>();

/** A tail wrapped along the floor in front of a curled-up pet, `length` wide, its tip curling up. */
export function wrappedTail(lengthIn: number): SpriteGrid {
  const length = Math.max(lengthIn, 8);
  const cached = wrapCache.get(length);
  if (cached) return cached;
  const grid = new SpriteGrid(length, 3);
  for (let x = 0; x < length; x++) {
    /* Faint rings every few pixels; plain fur on unstriped breeds. */
    const fur = x > 3 && x % 4 === 1 ? cells.stripes : cells.furBase;
    if (x >= 3 && x < length - 2) grid.setCode(x, 1, fur);
    if (x >= 2) grid.setCode(x, 2, x < 3 ? cells.tailTip : fur);
  }
  /* The tip curls up in front of the chin. */
  for (const [x, y] of [
    [1, 0],
    [2, 0],
    [0, 1],
    [1, 1],
    [2, 1],
    [1, 2],
  ] as const) {
    grid.setCode(x, y, cells.tailTip);
  }
  wrapCache.set(length, grid);
  return grid;
}

/** Which way a walking leg's lower half leans. */
export type WalkLean = "under" | "forward" | "back";

/** One step of the walk cycle: each leg's lean, and whether the paws touch down. */
export interface WalkStep {
  readonly nearFront: WalkLean;
  readonly farFront: WalkLean;
  readonly nearBack: WalkLean;
  readonly farBack: WalkLean;
  readonly isContact: boolean;
}

/** Port of WalkArt: side-on torsos and tails, and procedural legs. */
export const WalkArt = {
  catTorso: memo(() => petArt("walk").grid("catTorso")),
  dogTorso: memo(() => petArt("walk").grid("dogTorso")),
  longTorso: memo(() => petArt("walk").grid("longTorso")),
  catTail: memo(() => petArt("walk").sequence("catTail")),
  roundCatTorso: memo(() => petArt("walk").grid("roundCatTorso")),
  roundCatTail: memo(() => petArt("walk").sequence("roundCatTail")),
  sphynxTorso: memo(() => petArt("walk").grid("sphynxTorso")),
  sphynxTail: memo(() => petArt("walk").sequence("sphynxTail")),
  foldCatTail: memo(() => petArt("walk").sequence("foldCatTail")),
  longhairCatTorso: memo(() => petArt("walk").grid("longhairCatTorso")),
  longhairCatTail: memo(() => petArt("walk").sequence("longhairCatTail")),
  poodleTorso: memo(() => petArt("walk").grid("poodleTorso")),
  poodleTail: memo(() => petArt("walk").sequence("poodleTail")),
  shihTzuTorso: memo(() => petArt("walk").grid("shihTzuTorso")),
  shihTzuTail: memo(() => petArt("walk").sequence("shihTzuTail")),
  dogTail: memo(() => petArt("walk").sequence("dogTail")),
  longTail: memo(() => petArt("walk").sequence("longTail")),
  cycle: [
    { nearFront: "forward", farFront: "back", nearBack: "back", farBack: "forward", isContact: true },
    { nearFront: "under", farFront: "under", nearBack: "under", farBack: "under", isContact: false },
    { nearFront: "back", farFront: "forward", nearBack: "forward", farBack: "back", isContact: true },
    { nearFront: "under", farFront: "under", nearBack: "under", farBack: "under", isContact: false },
  ] as readonly WalkStep[],
};

const legCache = new Map<string, SpriteGrid>();

/** A two-pixel-wide leg `height` rows tall whose lower half leans; far legs are shaded. */
export function walkLeg(height: number, lean: WalkLean, far: boolean): SpriteGrid {
  const key = `${height}:${lean}:${far}`;
  const cached = legCache.get(key);
  if (cached) return cached;
  const grid = new SpriteGrid(3, height);
  const fur = far ? cells.furShade : cells.furBase;
  for (let y = 0; y < height; y++) {
    /* The hip stays put; the lower half swings to the lean. */
    const lower = y >= Math.floor(height / 2);
    const left = lean === "under" ? 0 : lean === "forward" ? (lower ? 0 : 1) : lower ? 1 : 0;
    const cell = y === height - 1 ? cells.paws : fur;
    grid.setCode(left, y, cell);
    grid.setCode(left + 1, y, cell);
  }
  legCache.set(key, grid);
  return grid;
}

const reachCache = new Map<string, SpriteGrid>();

/** A front leg folded down and reaching `reach` pixels ahead, its forearm on the floor. */
export function reachingLeg(height: number, reach: number, far: boolean): SpriteGrid {
  const key = `${height}:${reach}:${far}`;
  const cached = reachCache.get(key);
  if (cached) return cached;
  const grid = new SpriteGrid(reach + 2, height);
  const fur = far ? cells.furShade : cells.furBase;
  for (let y = 0; y < height; y++) {
    /* The bottom two rows are the forearm resting on the ground. */
    const lying = reach > 0 && y >= height - 2;
    for (let x = lying ? 0 : reach; x < reach + 2; x++) grid.setCode(x, y, fur);
  }
  /* The paw is the leading tip of the bottom row. */
  grid.setCode(0, height - 1, cells.paws);
  grid.setCode(1, height - 1, cells.paws);
  reachCache.set(key, grid);
  return grid;
}
