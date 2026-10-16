import {
  accessoryArt,
  accessoryFrameCounts,
  bondCollarArt,
  bondSparkleArt,
  outfitArt,
  outfitHood,
} from "./costumeArt";
import {
  auraFrameCount,
  backFrameCount,
  bodyFrame,
  bodyFrameCount,
  faceFrame,
  headFrameCount,
  headGrid,
  type CostumeAuraItem,
  type CostumeBackItem,
  type CostumeBodyItem,
  type CostumeFaceItem,
  type CostumeHeadItem,
  type CostumePlacement,
} from "./petArt";
import {
  CatArt,
  DogArt,
  PawArt,
  PropArt,
  TailArt,
  WalkArt,
  faceWithEyes,
  groomArm,
  hangingLeg,
  liftingLeftPaw,
  mouthPlacement,
  reachingLeg,
  splitTail,
  swungTail,
  walkLeg,
  wrappedTail,
  type WalkLean,
} from "./petArtPieces";
import { NO_BOND_LOOK, type PetBondLook } from "./petBond";
import { breedBodyShape, breedHasTail, breedPattern } from "./petBreed";
import { PetCanvas, type PetPattern } from "./petCanvas";
import { accessorySlot, wearable, type PetAccessory, type PetOutfit } from "./petCostume";
import { itemParts, type PetItem } from "./petItem";
import type { PetBodyShape, PetBreed } from "./petKinds";
import { SITTING, petPose, type PetGesture, type PetPoint, type PetPose, type PetProp, type PetStance } from "./petPose";
import type { SpriteGrid } from "./spriteGrid";

/*
 * Port of PetComposer: builds a full pet frame from the shared art of its
 * body shape. Every frame is a fixed 32x32 canvas with the pet's paws on the
 * same baseline, so frames swap in place without jitter.
 */

export const FRAME_SIZE = 32;
/** Where the chin rests once a peeking pet is fully out of the notch. */
export const HANGING_CHIN_ROW = 20;
/** Where the chin rests on a pet curled up asleep, on its wrapped tail. */
export const CURLED_CHIN_ROW = 27;

/** A composed, outlined frame plus where the head ended up. */
export interface Composed {
  /** The pet, without what it wears behind it. */
  readonly canvas: PetCanvas;
  /** The outlined layer of back items (wings), or undefined when none is worn. */
  readonly back?: PetCanvas;
  /** The particles of aura items in the air, not outlined and not moved by a hop. */
  readonly aura?: PetCanvas;
  /** Top-right corner of the head's skull, in frame pixels. */
  readonly headTopRight: PetPoint;
  /** Top-left corner of a held mug, where its steam rises from. */
  readonly mugTop?: PetPoint;
}

/** The pet with its aura, over its back layer. */
export function composedPicture(composed: Composed): PetCanvas {
  const pet = composed.aura ? composed.canvas.scattering(composed.aura) : composed.canvas;
  return composed.back ? pet.over(composed.back) : pet;
}

type Family = "cat" | "dog" | "longDog";

/** Where every part of a sitting pet goes for one body shape. */
interface SitLayout {
  readonly family: Family;
  readonly body: SpriteGrid;
  readonly bodyX: number;
  readonly bodyY: number;
  readonly tail?: { readonly grid: SpriteGrid; readonly x: number; readonly y: number };
  /** First body column of a tail drawn into the sitting body. */
  readonly tailColumn?: number;
  readonly head: SpriteGrid;
  readonly headX: number;
  readonly headY: number;
  readonly face: SpriteGrid;
  /** Head row the face grid's top row is stamped on. */
  readonly faceRow: number;
  /** Head row of the top of the eyes. */
  readonly eyeRow: number;
  /** Head row where a hat's band sits. */
  readonly skullTop: number;
}

function makeSitLayout(shape: PetBodyShape): SitLayout {
  switch (shape) {
    case "cat":
    case "roundCat":
    case "sphynxCat":
    case "foldCat": {
      /* The British Shorthair's and Scottish Fold's plump bodies are a column wider, so their tails start one later. */
      const plump = shape === "roundCat" || shape === "foldCat";
      const [body, head, face] =
        shape === "roundCat"
          ? [CatArt.bodyRound(), CatArt.headRound(), CatArt.faceRound()]
          : shape === "sphynxCat"
            ? [CatArt.bodySphynx(), CatArt.headSphynx(), CatArt.faceSphynx()]
            : shape === "foldCat"
              ? [CatArt.bodyFold(), CatArt.headFold(), CatArt.faceOpen()]
              : [CatArt.bodySit(), CatArt.head(), CatArt.faceOpen()];
      return {
        family: "cat",
        body,
        bodyX: 6,
        bodyY: 20,
        tailColumn: plump ? 18 : 17,
        head,
        headX: 6,
        headY: 7,
        face,
        faceRow: 0,
        eyeRow: 7,
        skullTop: 3,
      };
    }
    case "longDog":
      return {
        family: "longDog",
        body: DogArt.bodyLong(),
        bodyX: 6,
        bodyY: 21,
        tailColumn: 23,
        head: DogArt.headLong(),
        headX: 2,
        headY: 8,
        face: DogArt.faceLongSnout(),
        faceRow: 4,
        eyeRow: 4,
        skullTop: 1,
      };
    default: {
      const body = shape === "poodleDog" ? DogArt.bodyPoodle() : shape === "shihTzuDog" ? DogArt.bodyShihTzu() : DogArt.bodySit();
      const tail =
        shape === "poodleDog"
          ? { grid: DogArt.tailPom(), x: 24, y: 21 }
          : shape === "shihTzuDog"
            ? { grid: DogArt.tailPlume(), x: 24, y: 21 }
            : { grid: DogArt.tailUp(), x: 23, y: 24 };
      const [grid, eyes, skull]: [SpriteGrid, number, number] =
        shape === "fluffyDog"
          ? [DogArt.headFluffy(), 4, 1]
          : shape === "batEaredDog"
            ? [DogArt.headBatEared(), 8, 5]
            : shape === "pointyEaredDog"
              ? [DogArt.headPointyEared(), 8, 5]
              : shape === "poodleDog"
                ? [DogArt.headPoodle(), 8, 4]
                : shape === "shihTzuDog"
                  ? [DogArt.headShihTzu(), 7, 5]
                  : [DogArt.headFloppy(), 4, 1];
      /* Dog heads differ in height; all rest their chin on the neck. */
      return {
        family: "dog",
        body,
        bodyX: 6,
        bodyY: 20,
        tail,
        head: grid,
        headX: 6,
        headY: 21 - grid.height,
        face: shape === "shihTzuDog" ? DogArt.faceShihTzu() : DogArt.faceOpen(),
        faceRow: eyes,
        eyeRow: eyes,
        skullTop: skull,
      };
    }
  }
}

function sitPickBody(layout: SitLayout, item: CostumeBodyItem): SpriteGrid {
  return layout.family === "cat" ? item.cat : layout.family === "dog" ? item.dog : item.longDog;
}

function sitPickAura(layout: SitLayout, item: CostumeAuraItem): CostumePlacement {
  return layout.family === "longDog" ? item.longDog : item.front;
}

function sitPickBack(layout: SitLayout, item: CostumeBackItem): CostumePlacement {
  return layout.family === "cat" ? item.cat : layout.family === "dog" ? item.dog : item.longDog;
}

/** Where every part of a walking pet goes for one body family. */
interface WalkLayout {
  readonly family: Family;
  readonly torso: SpriteGrid;
  readonly torsoX: number;
  readonly torsoY: number;
  readonly tails: readonly SpriteGrid[];
  readonly tailX: number;
  readonly legHeight: number;
  /** Left edge of the near front leg; far legs stand 3 pixels further back. */
  readonly frontHip: number;
  readonly backHip: number;
  readonly headX: number;
  /** Frame row of the head's last pixel on a passing step. */
  readonly chinRow: number;
}

function makeWalkLayout(shape: PetBodyShape, family: Family): WalkLayout {
  const shared = { torsoX: 7, frontHip: 9, headX: 1, family };
  switch (family) {
    case "cat": {
      const [torso, tails] =
        shape === "roundCat"
          ? [WalkArt.roundCatTorso(), WalkArt.roundCatTail()]
          : shape === "sphynxCat"
            ? [WalkArt.sphynxTorso(), WalkArt.sphynxTail()]
            : shape === "foldCat"
              ? [WalkArt.catTorso(), WalkArt.foldCatTail()]
              : [WalkArt.catTorso(), WalkArt.catTail()];
      return { ...shared, torso, tails, torsoY: 20, tailX: 26, legHeight: 4, backHip: 22, chinRow: 24 };
    }
    case "dog": {
      const [torso, tails] =
        shape === "poodleDog"
          ? [WalkArt.poodleTorso(), WalkArt.poodleTail()]
          : shape === "shihTzuDog"
            ? [WalkArt.shihTzuTorso(), WalkArt.shihTzuTail()]
            : [WalkArt.dogTorso(), WalkArt.dogTail()];
      return { ...shared, torso, tails, torsoY: 20, tailX: 26, legHeight: 4, backHip: 22, chinRow: 24 };
    }
    case "longDog":
      return {
        ...shared,
        torso: WalkArt.longTorso(),
        torsoY: 22,
        tails: WalkArt.longTail(),
        tailX: 27,
        legHeight: 3,
        backHip: 23,
        chinRow: 26,
      };
  }
}

function walkPickBody(walk: WalkLayout, item: CostumeBodyItem): SpriteGrid {
  return walk.family === "longDog" ? item.walkLong : item.walk;
}

function walkPickBack(walk: WalkLayout, item: CostumeBackItem): CostumePlacement {
  return walk.family === "longDog" ? item.walkLong : item.walk;
}

const sitLayouts = new Map<PetBodyShape, SitLayout>();
const walkLayouts = new Map<PetBodyShape, WalkLayout>();

function sitLayout(shape: PetBodyShape): SitLayout {
  let layout = sitLayouts.get(shape);
  if (!layout) {
    layout = makeSitLayout(shape);
    sitLayouts.set(shape, layout);
  }
  return layout;
}

function walkLayout(shape: PetBodyShape, family: Family): WalkLayout {
  let layout = walkLayouts.get(shape);
  if (!layout) {
    layout = makeWalkLayout(shape, family);
    walkLayouts.set(shape, layout);
  }
  return layout;
}

function collarArt(bond: PetBondLook, accessories: readonly PetAccessory[]): CostumeBodyItem | undefined {
  if (accessories.some((accessory) => accessorySlot(accessory) === "neck")) return undefined;
  return bondCollarArt(bond.collar);
}

function backItems(worn: readonly PetAccessory[]): CostumeBackItem[] {
  const items: CostumeBackItem[] = [];
  for (const accessory of worn) {
    const art = accessoryArt(accessory);
    if (art.kind === "back") items.push(art.item);
  }
  return items;
}

function auraItems(worn: readonly PetAccessory[], bond: PetBondLook): CostumeAuraItem[] {
  const items: CostumeAuraItem[] = [];
  for (const accessory of worn) {
    const art = accessoryArt(accessory);
    if (art.kind === "aura") items.push(art.item);
  }
  if (bond.sparkle) items.push(bondSparkleArt());
  return items;
}

/** The outfit, bond collar and neck items worn, in drawing order. */
function bodyItems(
  outfit: PetOutfit,
  accessories: readonly PetAccessory[],
  worn: readonly PetAccessory[],
  bond: PetBondLook,
): CostumeBodyItem[] {
  const items: CostumeBodyItem[] = [];
  const outfitItem = outfitArt(outfit);
  if (outfitItem) items.push(outfitItem);
  const collar = collarArt(bond, accessories);
  if (collar) items.push(collar);
  for (const accessory of worn) {
    const art = accessoryArt(accessory);
    if (art.kind === "body") items.push(art.item);
  }
  return items;
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

/** Ticks of the item clock before every animated item worn is back on its first frame together. */
export function itemLoopLength(
  outfit: PetOutfit,
  accessories: readonly PetAccessory[],
  bond: PetBondLook = NO_BOND_LOOK,
): number {
  const counts: number[] = [];
  const outfitItem = outfitArt(outfit);
  if (outfitItem) counts.push(bodyFrameCount(outfitItem));
  const hood = outfitHood(outfit);
  if (hood) counts.push(headFrameCount(hood));
  if (bond.sparkle) counts.push(auraFrameCount(bondSparkleArt()));
  for (const accessory of wearable(accessories)) counts.push(...accessoryFrameCounts(accessoryArt(accessory)));
  return counts.reduce((length, count) => (length / gcd(length, count)) * count, 1);
}

/** Whether the left front paw is up (a gesture, or batting a toy). */
function liftsLeftPaw(pose: PetPose): boolean {
  if (pose.gesture) return true;
  return pose.prop?.kind === "toy" && pose.prop.bat;
}

/**
 * The walking torso with its tail and torso costumes, on its own frame
 * canvas so a stance can bend it before laying it over the legs.
 */
function walkingTorso(
  pattern: PetPattern,
  hasTail: boolean,
  walk: WalkLayout,
  items: readonly CostumeBodyItem[],
  wag: number | undefined,
  phase: number,
): PetCanvas {
  const canvas = new PetCanvas(FRAME_SIZE, FRAME_SIZE);
  canvas.stamp(walk.torso, walk.torsoX, walk.torsoY, pattern);
  if (hasTail && wag !== undefined) {
    const tail = walk.tails[wag % walk.tails.length];
    if (tail) canvas.stamp(tail, walk.tailX, walk.torsoY - tail.height, pattern);
  }
  for (const item of items) {
    const frame = bodyFrame(item, phase);
    canvas.stamp(walkPickBody(walk, frame), walk.torsoX, walk.torsoY - frame.rise);
  }
  return canvas;
}

/** The back items worn, on their own frame canvas placed from the walking torso. */
function walkingBack(items: readonly CostumeBackItem[], walk: WalkLayout, phase: number): PetCanvas {
  const canvas = new PetCanvas(FRAME_SIZE, FRAME_SIZE);
  for (const item of items) {
    const placement = walkPickBack(walk, item);
    const frame = placement.frames[phase % backFrameCount(item)];
    if (frame) canvas.stamp(frame, walk.torsoX + placement.x, walk.torsoY + placement.y);
  }
  return canvas;
}

/** Left edge of the toy `roll` pixels after it starts rolling away; it stops at the edge. */
function toyX(roll: number, center: number): number {
  const ball = PropArt.ball()[0];
  return Math.max(0, center - Math.floor((ball?.width ?? 0) / 2) - Math.max(roll, 0));
}

/**
 * Draws a held prop in front of the sitting pet, centered under the head:
 * the laptop on the floor, the mug from the lap to the mouth, a toy rolling
 * away. Returns the mug's top-left corner.
 */
function stampProp(
  prop: PetProp,
  canvas: PetCanvas,
  layout: SitLayout,
  headX: number,
  headY: number,
  pattern: PetPattern,
): PetPoint | undefined {
  const center = headX + Math.floor(layout.head.width / 2);
  switch (prop.kind) {
    case "laptop": {
      const laptop = PropArt.laptop();
      const lidY = FRAME_SIZE - 1 - laptop.height;
      canvas.stamp(laptop, center - Math.floor(laptop.width / 2), lidY);
      /* Resting paws hang over the lid's edge; a tapping paw lifts off it. */
      const pawY = lidY - 1;
      canvas.stamp(PropArt.paw(), center - 7, pawY - (prop.tap < 0 ? 2 : 0), pattern);
      canvas.stamp(PropArt.paw(), center + 1, pawY - (prop.tap > 0 ? 2 : 0), pattern);
      return undefined;
    }
    case "mug": {
      const mouth = mouthPlacement("open", layout.face);
      if (!mouth) return undefined;
      const mouthX = headX + mouth.origin.x + 2;
      const sipY = headY + layout.faceRow + mouth.origin.y - 1;
      /* Held in the lap, low enough that the steam rises over the chest. */
      const lapY = headY + layout.head.height + 3;
      const y = lapY + Math.trunc(((sipY - lapY) * Math.min(Math.max(prop.raise, 0), 2)) / 2);
      const x = mouthX - 3;
      /* Paws first, so the mug's handle shows over the right one. */
      canvas.stamp(PropArt.mugPaw(), x - 3, y + 1, pattern);
      canvas.stamp(PropArt.mugPaw(), x + 4, y + 1, pattern);
      canvas.stamp(PropArt.mug(), x, y);
      return { x, y };
    }
    case "toy": {
      /* Cats play with yarn, dogs with a ball; only a ball bounces. */
      const yarn = layout.family === "cat";
      const art = yarn ? PropArt.yarn() : PropArt.ball();
      const toy = art[Math.trunc(prop.roll / 2) % art.length];
      if (!toy) return undefined;
      const x = toyX(prop.roll, center);
      const y = FRAME_SIZE - toy.height - (yarn ? 0 : Math.max(prop.bounce, 0));
      canvas.stamp(toy, x, y);
      /* The lifted left paw presses on the toy's top. */
      if (prop.bat) canvas.stamp(PropArt.paw(), x - 1, y - 1, pattern);
      return undefined;
    }
  }
}

/** Draws the lifted front paw: a wave beside the head, or grooming at the mouth or cheek. */
function stampGesture(
  gesture: PetGesture,
  canvas: PetCanvas,
  layout: SitLayout,
  headX: number,
  headY: number,
  pattern: PetPattern,
): void {
  const shoulder = { x: layout.bodyX + 3, y: layout.bodyY + 4 };
  switch (gesture.kind) {
    case "wave": {
      const wave = PawArt.wave();
      const arm = wave[Math.min(Math.max(gesture.swing, 0), wave.length - 1)];
      if (arm) canvas.stamp(arm, shoulder.x - 8, shoulder.y - arm.height + 1, pattern);
      return;
    }
    case "groom": {
      const mouth = mouthPlacement("open", layout.face);
      if (!mouth) return;
      const mouthX = headX + mouth.origin.x + 2;
      const mouthY = headY + layout.faceRow + mouth.origin.y;
      /* Just under the tongue to lick it; lower at rest; up over the cheek to wash. */
      const [x, y] =
        gesture.reach <= 0 ? [mouthX - 4, mouthY + 4] : gesture.reach === 1 ? [mouthX - 4, mouthY + 2] : [mouthX - 8, mouthY - 3];
      /* The whole front leg is lifted, reaching down to just above the floor. */
      const knee = layout.bodyY + layout.body.height - 2;
      canvas.stamp(groomArm(knee - y + 1), x, y, pattern);
      return;
    }
  }
}

/**
 * Composes one frame. `phase` is the tick of the item clock: animated
 * costume items draw that frame of their loop, and 0 is their still.
 */
export function compose(
  breed: PetBreed,
  pose: PetPose,
  outfit: PetOutfit,
  accessories: readonly PetAccessory[],
  bond: PetBondLook = NO_BOND_LOOK,
  stance: PetStance = SITTING,
  phase = 0,
): Composed {
  const shape = breedBodyShape(breed);
  const layout = sitLayout(shape);
  const pattern = breedPattern(breed);
  const hasTail = breedHasTail(breed);
  const worn = wearable(accessories);
  const canvas = new PetCanvas(FRAME_SIZE, FRAME_SIZE);
  let headX = layout.headX;
  let headY = layout.headY + pose.headDrop;
  /* Body items stamp at the body origin while sitting; other stances draw them on the torso. */
  let sittingBody = true;
  const behind = backItems(worn);
  const back = new PetCanvas(FRAME_SIZE, FRAME_SIZE);
  switch (stance.kind) {
    case "sitting": {
      for (const item of behind) {
        const placement = sitPickBack(layout, item);
        const frame = placement.frames[phase % backFrameCount(item)];
        if (frame) back.stamp(frame, layout.bodyX + placement.x, layout.bodyY + placement.y);
      }
      /* A gesturing pet lifts its left front paw off the floor. */
      let body = liftsLeftPaw(pose) ? liftingLeftPaw(layout.body) : layout.body;
      const swing = Math.max(pose.tailSwing, 0);
      if (swing > 0 && layout.tailColumn !== undefined) {
        /* A tail drawn into the body is cut out and bent on its own. */
        const split = splitTail(body, layout.tailColumn);
        body = split.body;
        const room = FRAME_SIZE - 1 - layout.bodyX;
        canvas.stamp(swungTail(split.tail, swing, room), layout.bodyX, layout.bodyY, pattern);
      }
      canvas.stamp(body, layout.bodyX, layout.bodyY, pattern);
      if (hasTail && layout.tail) {
        const room = FRAME_SIZE - 1 - layout.tail.x;
        canvas.stamp(swungTail(layout.tail.grid, swing, room), layout.tail.x, layout.tail.y, pattern);
      } else if (!hasTail && swing > 0) {
        /* No tail to swish: a stub pops out past the haunch and bobs. */
        const haunch = layout.bodyX + layout.body.width - 1;
        canvas.stamp(TailArt.nub(), haunch, layout.bodyY + 7 - swing, pattern);
      }
      break;
    }
    case "hanging": {
      /* A hanging pet's chin always rests on the same row, whatever the head. */
      headY = HANGING_CHIN_ROW + 1 - layout.head.height;
      const leg = hangingLeg(headY + 3);
      canvas.stamp(leg, layout.headX + 4, 0, pattern);
      canvas.stamp(leg, layout.headX + layout.head.width - 4 - leg.width, 0, pattern);
      sittingBody = false;
      break;
    }
    case "walking": {
      const walk = walkLayout(shape, layout.family);
      const step = WalkArt.cycle[stance.step % WalkArt.cycle.length] ?? WalkArt.cycle[0];
      if (!step) break;
      /* Contact steps sink a pixel onto bent legs; the head rides along. */
      const sink = step.isContact ? 1 : 0;
      const legY = walk.torsoY + walk.torso.height;
      const legs: [number, WalkLean, boolean][] = [
        [walk.frontHip + 3, step.farFront, true],
        [walk.backHip + 3, step.farBack, true],
        [walk.frontHip, step.nearFront, false],
        [walk.backHip, step.nearBack, false],
      ];
      for (const [x, lean, far] of legs) canvas.stamp(walkLeg(walk.legHeight, lean, far), x, legY, pattern);
      /* The tail sways once per half cycle, not every step, so it doesn't flicker. */
      const items = bodyItems(outfit, accessories, worn, bond);
      canvas.lay(walkingTorso(pattern, hasTail, walk, items, Math.trunc(stance.step / 2), phase), () => sink);
      back.lay(walkingBack(behind, walk, phase), () => sink);
      sittingBody = false;
      headX = walk.headX;
      headY = walk.chinRow + 1 - layout.head.height + sink + pose.headDrop;
      break;
    }
    case "stretching": {
      const walk = walkLayout(shape, layout.family);
      /* Short legs bow less, so the chin never sinks onto the paws. */
      const depth = Math.min(stance.depth, walk.legHeight - 1);
      const legY = walk.torsoY + walk.torso.height;
      /* Back legs stand straight; front legs fold down and reach ahead. */
      const height = Math.max(2, walk.legHeight - depth);
      const reach = depth * 2;
      for (const [x, far] of [
        [walk.backHip + 3, true],
        [walk.backHip, false],
      ] as const) {
        canvas.stamp(walkLeg(walk.legHeight, "under", far), x, legY, pattern);
      }
      /* Bow the torso: columns toward the chest sink, the rump stays put. */
      const items = bodyItems(outfit, accessories, worn, bond);
      const torso = walkingTorso(pattern, hasTail, walk, items, stance.wag, phase);
      const pivot = walk.torsoX + Math.trunc((walk.torso.width * 2) / 3);
      const bow = (x: number) =>
        x >= pivot ? 0 : Math.min(depth, Math.round((depth * (pivot - x)) / (pivot - walk.torsoX)));
      canvas.lay(torso, bow);
      back.lay(walkingBack(behind, walk, phase), bow);
      /* The forearms lie in front of the lowered chest. */
      for (const [x, far] of [
        [walk.frontHip + 3, true],
        [walk.frontHip, false],
      ] as const) {
        canvas.stamp(reachingLeg(height, reach, far), x - reach, legY + walk.legHeight - height, pattern);
      }
      sittingBody = false;
      headX = walk.headX;
      headY = walk.chinRow + 1 - layout.head.height + depth + pose.headDrop;
      break;
    }
    case "curled": {
      const walk = walkLayout(shape, layout.family);
      /* The torso drops onto the floor where the legs were; on a breath the back swells up a pixel. */
      const items = bodyItems(outfit, accessories, worn, bond);
      const torso = walkingTorso(pattern, hasTail, walk, items, undefined, phase);
      const floor = walk.legHeight;
      canvas.lay(torso, () => floor);
      back.lay(walkingBack(behind, walk, phase), () => floor);
      if (stance.breath > 0) {
        const low = walk.torsoX + 4;
        const high = walk.torsoX + walk.torso.width - 4;
        canvas.lay(torso, (x) => (x >= low && x <= high ? floor - 1 : floor));
      }
      sittingBody = false;
      headX = walk.headX;
      headY = CURLED_CHIN_ROW + 1 - layout.head.height + pose.headDrop;
      break;
    }
  }
  canvas.stamp(layout.head, headX, headY, pattern);
  const face = faceWithEyes(layout.face, layout.eyeRow - layout.faceRow, pose.eyes);
  canvas.stamp(face, headX, headY + layout.faceRow, pattern);
  const mouth = mouthPlacement(pose.mouth, layout.face);
  if (mouth) canvas.stamp(mouth.grid, headX + mouth.origin.x, headY + layout.faceRow + mouth.origin.y, pattern);
  if (stance.kind === "curled" && hasTail) {
    /* The tail comes round from the rump and runs along the floor in front, under the chin. */
    const walk = walkLayout(shape, layout.family);
    const left = headX + 2;
    const tail = wrappedTail(walk.torsoX + walk.torso.width - left);
    const layer = new PetCanvas(FRAME_SIZE, FRAME_SIZE);
    layer.stamp(tail, left, FRAME_SIZE - 1 - tail.height, pattern);
    canvas.lay(layer.outlined(), () => 0);
  }

  const stampFace = (item: CostumeFaceItem) => {
    const frame = faceFrame(item, phase);
    canvas.stamp(layout.family === "cat" ? frame.cat : frame.dog, headX, headY + layout.eyeRow - item.eyeRow);
  };
  const stampHead = (item: CostumeHeadItem) => {
    canvas.stamp(headGrid(item, phase), headX, headY + layout.skullTop - item.sitRow);
  };
  const stampBody = (item: CostumeBodyItem) => {
    if (!sittingBody) return;
    const frame = bodyFrame(item, phase);
    canvas.stamp(sitPickBody(layout, frame), layout.bodyX, layout.bodyY - item.rise);
  };
  const outfitItem = outfitArt(outfit);
  if (outfitItem) stampBody(outfitItem);
  /* An outfit's hood goes under any hat, which is worn over it. */
  const hood = outfitHood(outfit);
  if (hood) stampHead(hood);
  /* The bond collar goes over the outfit, under any neck item. */
  const collar = collarArt(bond, accessories);
  if (collar) stampBody(collar);
  for (const accessory of worn) {
    const art = accessoryArt(accessory);
    switch (art.kind) {
      case "body":
        stampBody(art.item);
        break;
      case "face":
        stampFace(art.item);
        break;
      case "head":
        stampHead(art.item);
        break;
      case "mask":
        stampFace(art.face);
        stampHead(art.head);
        break;
      case "back":
      case "aura":
        break;
    }
  }
  let mugTop: PetPoint | undefined;
  if (stance.kind === "sitting" && pose.prop) {
    const top = stampProp(pose.prop, canvas, layout, headX, headY, pattern);
    if (top) mugTop = { x: top.x, y: top.y - pose.lift };
  }
  if (stance.kind === "sitting" && pose.gesture) stampGesture(pose.gesture, canvas, layout, headX, headY, pattern);
  /* Aura items float in the air, placed in the frame by the view, not the body. */
  let aura: PetCanvas | undefined;
  const floating = auraItems(worn, bond);
  if (floating.length > 0 && stance.kind !== "hanging") {
    const layer = new PetCanvas(FRAME_SIZE, FRAME_SIZE);
    for (const item of floating) {
      const placement = stance.kind === "sitting" ? sitPickAura(layout, item) : item.side;
      const frame = placement.frames[phase % auraFrameCount(item)];
      if (frame) layer.stamp(frame, placement.x, placement.y);
    }
    aura = layer;
  }
  const headTopRight = { x: headX + layout.head.width - 1, y: headY + layout.skullTop - pose.lift };
  /* The back layer is outlined on its own and goes under the outlined pet. */
  return {
    canvas: canvas.outlined().shifted(0, -pose.lift),
    ...(behind.length === 0 ? {} : { back: back.outlined().shifted(0, -pose.lift) }),
    ...(aura ? { aura } : {}),
    headTopRight,
    ...(mugTop ? { mugTop } : {}),
  };
}

/** The pet sitting, facing the viewer, optionally dressed and posed. */
export function sitting(
  breed: PetBreed,
  options: {
    outfit?: PetOutfit;
    accessories?: readonly PetAccessory[];
    bond?: PetBondLook;
    pose?: PetPose;
  } = {},
): PetCanvas {
  return composedPicture(
    compose(breed, options.pose ?? petPose(), options.outfit ?? "none", options.accessories ?? [], options.bond ?? NO_BOND_LOOK),
  );
}

/**
 * Ticks of an item's own animation loop (a flame flickering, a glint
 * crossing gold): 1 for an item that stays still. Port of PetItem.loopFrameCount.
 */
export function itemLoopFrameCount(item: PetItem): number {
  const parts = itemParts(item);
  return parts.kind === "outfit" ? itemLoopLength(parts.outfit, []) : itemLoopLength("none", [parts.accessory]);
}
