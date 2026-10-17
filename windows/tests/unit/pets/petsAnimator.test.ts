import { describe, expect, it } from "vitest";
import {
  PetAnimator,
  PetClipSet,
  activityForMood,
  playbackElapsed,
  type PetAnimatorEvent,
  type PetPlace,
  type PetPlayback,
} from "../../../src/core/pets/petAnimator";
import { PetCanvas } from "../../../src/core/pets/petCanvas";
import { PetClip, PetFrame, animationLoops } from "../../../src/core/pets/petClip";
import { PET_ANIMATIONS, type PetAnimation } from "../../../src/core/pets/petKinds";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { clip, opaqueCount } from "./support";

// Port of PetsAnimatorTests.swift: the clip set and the animator's state machine.

const clips = new PetClipSet({ breed: "tuxedo" });
const durations = clips.durations;

function duration(animation: PetAnimation): number {
  const value = durations.get(animation);
  if (value === undefined) throw new Error(`no ${animation} duration`);
  return value;
}

function animator(place: PetPlace = "beside", asleep = false, seed = 7): PetAnimator {
  return new PetAnimator(durations, { place, asleep, at: 0, seed });
}

function animationAt(pet: PetAnimator, time: number): PetAnimation | undefined {
  pet.advance(time);
  return pet.playback?.animation;
}

const BLINK = PetAnimator.blinkInterval;

function inBlinkInterval(gap: number): boolean {
  return gap >= BLINK.lower && gap <= BLINK.upper;
}

function frameOf(animation: PetAnimation, index: number): PetFrame {
  const frame = clips.clip(animation).frames.at(index);
  if (!frame) throw new Error(`no frame ${index} in ${animation}`);
  return frame;
}

const event = (kind: Exclude<PetAnimatorEvent["kind"], "activity">): PetAnimatorEvent => ({ kind });

describe("PetAnimator", () => {
  it("clip set has every animation and durations match the clips", () => {
    for (const animation of PET_ANIMATIONS) {
      expect(clips.clip(animation).animation).toBe(animation);
      expect(durations.get(animation)).toBe(clips.clip(animation).duration);
    }
    const profile = new PetProfile("Mochi", "corgi", { outfit: "scrubs", accessories: ["stethoscope"] });
    const fromProfile = new PetClipSet({
      breed: profile.breed,
      outfit: profile.outfit,
      accessories: profile.accessories,
      bond: profile.bondLook,
    }).clip("idle");
    const direct = clip("idle", "corgi", { outfit: "scrubs", accessories: ["stethoscope"] });
    expect(fromProfile.frames.map((frame) => frame.canvas.symbols())).toEqual(direct.frames.map((frame) => frame.canvas.symbols()));
  });

  it("starts in the resting animation for its place", () => {
    expect(animator().playback).toEqual({ animation: "idle", startedAt: 0 });
    expect(animator("beside", true).playback?.animation).toBe("sleep");
    expect(animator("hidden").playback, "nothing to draw inside the notch").toBeUndefined();
    expect(animator("hidden", true).isAsleep, "only a pet beside the notch can doze").toBe(false);

    const hanging = animator("hanging");
    expect(hanging.playback?.animation).toBe("peekIn");
    expect(clips.frame(hanging.playback, 0), "a hanging pet shows the settled frame at once").toBe(frameOf("peekIn", -1));
    expect(hanging.isTransitioning(0)).toBe(false);
  });

  it("idle blinks at random intervals and returns to idle exactly when the blink ends", () => {
    const pet = animator();
    const blinkStarts: number[] = [];
    let time = 0;
    while (time < 60) {
      time += 1 / 30;
      pet.advance(time);
      const playback = pet.playback;
      if (playback && playback.animation === "blink" && blinkStarts.at(-1) !== playback.startedAt) {
        blinkStarts.push(playback.startedAt);
      }
    }
    expect(blinkStarts.length).toBeGreaterThanOrEqual(Math.trunc(60 / Math.trunc(BLINK.upper + 1)));
    let restStart = 0;
    for (const start of blinkStarts) {
      expect(inBlinkInterval(start - restStart), `gap ${start - restStart}`).toBe(true);
      restStart = start + duration("blink");
    }
    const gaps = blinkStarts.slice(1).map((start, index) => start - (blinkStarts[index] ?? 0));
    expect(new Set(gaps).size, "blinks are not on a fixed beat").toBeGreaterThan(1);
  });

  it("blink timing is reproducible from the seed and independent of frame rate", () => {
    const coarse = animator("beside", false, 42);
    const fine = animator("beside", false, 42);
    coarse.advance(30);
    let time = 0;
    while (time < 30) {
      time += 1 / 120;
      fine.advance(Math.min(time, 30));
    }
    // Jumping ahead lands in the same state as ticking, the generator included.
    const state = (pet: PetAnimator) => [pet.playback, pet.nextBlinkAt, pet.place, pet.isAsleep, pet.activity];
    expect(state(coarse)).toEqual(state(fine));
    coarse.advance(90);
    fine.advance(90);
    expect(state(coarse)).toEqual(state(fine));
    expect(animator("beside", false, 1).nextBlinkAt).not.toBe(animator("beside", false, 2).nextBlinkAt);
  });

  it("nudge alerts then returns to idle when the clip ends", () => {
    const pet = animator("beside", true);
    expect(pet.send(event("nudge"), 1)).toBe(true);
    expect(pet.isAsleep, "a nudge wakes the pet").toBe(false);
    expect(pet.playback).toEqual({ animation: "alert", startedAt: 1 });
    expect(clips.frame(pet.playback, 1.05)?.bubbleAnchor).toBeDefined();

    const end = 1 + duration("alert");
    expect(animationAt(pet, end - 0.01)).toBe("alert");
    expect(animationAt(pet, end + 0.5)).toBe("idle");
    expect(pet.playback?.startedAt, "idle restarts at the clip's end, not the tick").toBe(end);
  });

  it("celebrate is not cut short by a nudge but celebrate overrides alert", () => {
    const pet = animator();
    pet.send(event("celebrate"), 0);
    expect(pet.send(event("nudge"), 0.2)).toBe(false);
    expect(pet.playback?.animation).toBe("celebrate");

    pet.advance(10);
    pet.send(event("nudge"), 10);
    expect(pet.send(event("celebrate"), 10.1)).toBe(true);
    expect(pet.playback).toEqual({ animation: "celebrate", startedAt: 10.1 });
  });

  it("sleep and wake", () => {
    const pet = animator();
    expect(pet.send(event("wake"), 0), "already awake").toBe(false);
    expect(pet.send(event("sleep"), 1)).toBe(true);
    expect(pet.playback).toEqual({ animation: "sleep", startedAt: 1 });
    expect(pet.nextBlinkAt, "no blinking while asleep").toBeUndefined();
    expect(animationAt(pet, 120), "sleep loops").toBe("sleep");
    expect(pet.send(event("wake"), 121)).toBe(true);
    expect(pet.playback, "waking stretches first").toEqual({ animation: "stretch", startedAt: 121 });
    expect(pet.nextBlinkAt, "no blink mid-stretch").toBeUndefined();
    const stretchEnd = 121 + duration("stretch");
    expect(animationAt(pet, stretchEnd - 0.01)).toBe("stretch");
    expect(animationAt(pet, stretchEnd)).toBe("idle");
    expect(pet.playback?.startedAt, "idle starts exactly when the stretch ends").toBe(stretchEnd);
    expect(pet.nextBlinkAt).toBeDefined();

    // Dozing off again mid-stretch waits for the stretch to finish.
    pet.send(event("sleep"), 150);
    pet.send(event("wake"), 151);
    pet.send(event("sleep"), 151.2);
    expect(pet.playback?.animation).toBe("stretch");
    expect(animationAt(pet, 151 + duration("stretch"))).toBe("sleep");

    // A nudge interrupts the stretch.
    pet.send(event("wake"), 160);
    expect(pet.send(event("nudge"), 160.2)).toBe(true);
    expect(pet.playback).toEqual({ animation: "alert", startedAt: 160.2 });

    // Dozing off mid-celebration lets the celebration finish first.
    pet.send(event("celebrate"), 200);
    pet.send(event("sleep"), 200.1);
    expect(pet.playback?.animation).toBe("celebrate");
    expect(animationAt(pet, 200 + duration("celebrate"))).toBe("sleep");
  });

  it("peek in hangs until peek out, then hides", () => {
    const peek = duration("peekIn");
    const pet = animator("hidden");
    expect(pet.send(event("celebrate"), 0), "can't celebrate inside the notch").toBe(false);
    expect(pet.send(event("nudge"), 1), "a nudge from inside the notch peeks out").toBe(true);
    expect(pet.place).toBe("hanging");
    expect(pet.playback).toEqual({ animation: "peekIn", startedAt: 1 });
    expect(pet.isTransitioning(1 + peek / 2)).toBe(true);

    expect(animationAt(pet, 30), "hangs on the held last frame").toBe("peekIn");
    expect(clips.frame(pet.playback, 30)).toBe(frameOf("peekIn", -1));
    expect(pet.send(event("peekIn"), 30)).toBe(false);

    expect(pet.send(event("peekOut"), 31)).toBe(true);
    expect(pet.place).toBe("hidden");
    expect(animationAt(pet, 31 + peek / 2)).toBe("peekOut");
    expect(animationAt(pet, 31 + peek + 0.01), "gone once it climbs back in").toBeUndefined();
  });

  it("events during a peek transition wait for it to finish", () => {
    const peek = duration("peekIn");
    const pet = animator("hidden");
    pet.send(event("peekIn"), 0);
    expect(pet.send(event("peekOut"), peek / 2), "deferred, not dropped").toBe(true);
    expect(pet.playback?.animation, "the climb out isn't cut").toBe("peekIn");

    expect(animationAt(pet, peek + 0.01)).toBe("peekOut");
    expect(pet.playback?.startedAt, "the deferred event starts as the transition ends").toBe(peek);

    pet.send(event("appear"), peek + 0.02);
    expect(animationAt(pet, peek * 2)).toBe("idle");
    expect(pet.place).toBe("beside");
    expect(pet.playback?.startedAt).toBe(peek * 2);
  });

  it("appear and disappear cut straight to a place", () => {
    const pet = animator("hanging");
    pet.send(event("disappear"), 1);
    expect(pet.playback).toBeUndefined();
    pet.send(event("appear"), 2);
    expect(pet.place).toBe("beside");
    expect(pet.playback).toEqual({ animation: "idle", startedAt: 2 });
    expect(clips.frame(undefined, 2)).toBeUndefined();
  });

  it("next frame boundary for looping and one-shot clips", () => {
    const canvas = new PetCanvas(1, 1);
    const frames = [new PetFrame(canvas, 0.5), new PetFrame(canvas, 0.25)];
    const loop = new PetClip("idle", frames);
    expect(loop.nextFrameBoundary(0)).toBe(0.5);
    expect(loop.nextFrameBoundary(0.5), "a boundary itself is not 'after'").toBe(0.75);
    expect(loop.nextFrameBoundary(0.8), "wraps into the next cycle").toBe(1.25);
    expect(new PetClip("sit", frames.slice(0, 1)).nextFrameBoundary(3), "a single-frame loop never changes").toBeUndefined();

    const once = new PetClip("alert", frames);
    expect(once.nextFrameBoundary(0.6), "the last boundary is the clip's end").toBe(0.75);
    expect(once.nextFrameBoundary(0.75), "a finished one-shot holds its last frame").toBeUndefined();
  });

  it("next change predicts every frame change", () => {
    const pet = animator("beside", false, 3);
    const events = new Map<number, PetAnimatorEvent>([
      [4000, event("nudge")],
      [9000, event("sleep")],
      [13000, event("disappear")],
      [14000, event("peekIn")],
    ]);
    const shown = (time: number): string => {
      const playback = pet.playback;
      if (!playback) return "none";
      return `${playback.animation}:${clips.clip(playback.animation).frameIndex(playbackElapsed(playback, time))}`;
    };
    let previous = shown(0);
    let scheduled = clips.nextChange(pet, 0);
    let changes = 0;
    for (let millisecond = 1; millisecond <= 20000; millisecond++) {
      const time = millisecond / 1000;
      const sent = events.get(millisecond);
      if (sent) pet.send(sent, time);
      else pet.advance(time);
      const now = shown(time);
      if (now !== previous && !sent) {
        if (scheduled === undefined) expect.fail(`frame changed at ${time} with nothing scheduled`);
        expect(Math.abs(scheduled - time), `frame changed at ${time}, scheduled for ${scheduled}`).toBeLessThanOrEqual(0.001);
        changes += 1;
      }
      previous = now;
      scheduled = clips.nextChange(pet, time);
      if (scheduled !== undefined && !(scheduled > time)) expect.fail(`scheduled ${scheduled} is not after ${time}`);
    }
    expect(changes).toBeGreaterThan(20);
    expect(pet.place).toBe("hanging");
    expect(scheduled, "hanging holds its frame until the next event").toBeUndefined();
    pet.send(event("disappear"), 20.5);
    expect(clips.nextChange(pet, 20.5), "nothing to redraw while hidden").toBeUndefined();
  });

  it("studying types and breaks sip coffee without idle blinks", () => {
    const pet = animator();
    expect(pet.send({ kind: "activity", activity: "studying" }, 1)).toBe(true);
    expect(pet.playback).toEqual({ animation: "typing", startedAt: 1 });
    expect(pet.nextBlinkAt, "the laptop loop has no idle blinks").toBeUndefined();
    expect(animationAt(pet, 120), "typing keeps looping through the focus block").toBe("typing");
    expect(pet.send({ kind: "activity", activity: "studying" }, 121), "no change, no restart").toBe(false);
    expect(pet.playback?.startedAt).toBe(1);

    expect(pet.send({ kind: "activity", activity: "onBreak" }, 200)).toBe(true);
    expect(pet.playback, "a short block ends without a yawn").toEqual({ animation: "coffee", startedAt: 200 });
    expect(pet.send({ kind: "activity", activity: "free" }, 300)).toBe(true);
    expect(pet.playback?.animation).toBe("idle");
    expect(pet.nextBlinkAt).toBeDefined();

    const studying = new PetAnimator(durations, { activity: "studying", at: 0, seed: 7 });
    expect(studying.playback?.animation, "a pet created mid-session studies at once").toBe("typing");
  });

  it("one-shots and sleep return to the activity, not idle", () => {
    const pet = animator();
    pet.send({ kind: "activity", activity: "onBreak" }, 0);
    pet.send(event("celebrate"), 1);
    expect(animationAt(pet, 1 + duration("celebrate") + 0.1), "back to the mug after celebrating").toBe("coffee");

    const sleepy = animator("beside", true);
    expect(sleepy.send({ kind: "activity", activity: "studying" }, 1)).toBe(true);
    expect(sleepy.playback?.animation, "only the wake-up moves a sleeping pet").toBe("sleep");
    sleepy.send(event("wake"), 2);
    expect(sleepy.playback?.animation).toBe("stretch");
    expect(animationAt(sleepy, 2 + duration("stretch") + 0.1)).toBe("typing");
  });

  it("a long focus stretch ends with a yawn, then the break", () => {
    const pet = animator();
    pet.send({ kind: "activity", activity: "studying" }, 0);
    const longEnd = PetAnimator.longSession;
    expect(pet.send({ kind: "activity", activity: "onBreak" }, longEnd)).toBe(true);
    expect(pet.playback).toEqual({ animation: "yawn", startedAt: longEnd });
    const yawnEnd = longEnd + duration("yawn");
    expect(animationAt(pet, yawnEnd - 0.01)).toBe("yawn");
    expect(pet.playback?.startedAt).toBe(longEnd);
    pet.advance(yawnEnd + 0.01);
    expect(pet.playback, "coffee starts as the yawn ends").toEqual({ animation: "coffee", startedAt: yawnEnd });

    const celebrating = animator();
    celebrating.send({ kind: "activity", activity: "studying" }, 0);
    celebrating.send(event("celebrate"), longEnd);
    celebrating.send({ kind: "activity", activity: "free" }, longEnd + 0.1);
    expect(celebrating.playback?.animation, "the yawn never cuts a celebration short").toBe("celebrate");
    const celebrateEnd = longEnd + duration("celebrate");
    celebrating.advance(celebrateEnd + 0.01);
    expect(celebrating.playback).toEqual({ animation: "yawn", startedAt: celebrateEnd });
    celebrating.advance(celebrateEnd + duration("yawn") + 0.01);
    expect(celebrating.playback?.animation).toBe("idle");

    const asleepAfterwards = animator();
    asleepAfterwards.send({ kind: "activity", activity: "studying" }, 0);
    asleepAfterwards.send({ kind: "activity", activity: "free" }, longEnd);
    asleepAfterwards.send(event("sleep"), longEnd + 0.1);
    expect(asleepAfterwards.playback?.animation, "a yawn plays out before dozing off").toBe("yawn");
    asleepAfterwards.advance(yawnEnd + 0.01);
    expect(asleepAfterwards.playback?.animation).toBe("sleep");
  });

  it("only a long stretch of focus makes the pet yawn", () => {
    const pet = animator();
    pet.send({ kind: "activity", activity: "studying" }, 0);
    pet.send({ kind: "activity", activity: "free" }, PetAnimator.longSession - 1);
    expect(pet.playback?.animation).toBe("idle");
    pet.send({ kind: "activity", activity: "onBreak" }, PetAnimator.longSession * 2);
    expect(pet.playback?.animation, "time spent idle is not focus").toBe("coffee");

    const hidden = animator("hidden");
    hidden.send({ kind: "activity", activity: "studying" }, 0);
    expect(hidden.send({ kind: "activity", activity: "free" }, PetAnimator.longSession)).toBe(true);
    expect(hidden.playback, "a hidden pet records the activity but draws nothing").toBeUndefined();
    hidden.send(event("appear"), PetAnimator.longSession + 1);
    expect(hidden.playback?.animation).toBe("idle");
  });

  it("the notch mood picks the activity", () => {
    expect(activityForMood("studying")).toBe("studying");
    expect(activityForMood("onBreak")).toBe("onBreak");
    expect(activityForMood("awake")).toBe("free");
    expect(activityForMood("asleep")).toBe("free");
  });

  it("still frame is where each clip settles", () => {
    for (const animation of PET_ANIMATIONS) {
      const built = clips.clip(animation);
      if (animation === "sleep" || animation === "nap") {
        expect(built.stillFrame, `${animation} holds a bright z drifting up`).toBe(built.frames[1]);
        expect(opaqueCount(built.stillFrame.canvas)).toBeGreaterThan(opaqueCount(frameOf(animation, 3).canvas));
      } else if (animation === "sip") {
        expect(built.stillFrame, "a still sip holds the mug at the mouth").toBe(built.frames[2]);
      } else {
        expect(built.stillFrame, animation).toBe(animationLoops(animation) ? built.frames[0] : built.frames.at(-1));
      }
    }
    expect(clips.clip("alert").stillFrame.bubbleAnchor, "a still alert keeps its bubble").toBeDefined();
  });

  it("a still pet shows one pose per state and ignores blinks", () => {
    const pet = animator();
    expect(clips.stillFrame(pet)).toBe(frameOf("idle", 0));
    expect(clips.nextStillChange(pet, 0), "a resting still pet waits for events").toBeUndefined();

    let time = 0;
    while (pet.playback?.animation !== "blink" && time < 10) {
      time += 0.05;
      pet.advance(time);
    }
    expect(pet.playback?.animation).toBe("blink");
    expect(clips.stillFrame(pet)).toBe(frameOf("idle", 0));
    expect(clips.nextStillChange(pet, time)).toBeUndefined();

    pet.send({ kind: "activity", activity: "studying" }, 20);
    expect(clips.stillFrame(pet)).toBe(frameOf("typing", 0));
    pet.send({ kind: "activity", activity: "onBreak" }, 21);
    expect(clips.stillFrame(pet)).toBe(frameOf("coffee", 0));
    pet.send(event("sleep"), 22);
    expect(clips.stillFrame(pet)).toBe(frameOf("sleep", 1));
    expect(clips.stillFrame(animator("hidden")), "nothing to draw inside the notch").toBeUndefined();
    expect(clips.stillFrame(animator("hanging"))).toBe(frameOf("peekIn", -1));
  });

  it("a still alert holds its pose until the clip ends, then rests", () => {
    const pet = animator("beside", true);
    pet.send(event("nudge"), 5);
    const alert = clips.clip("alert");
    expect(clips.stillFrame(pet)).toBe(alert.frames.at(-1));
    const end = clips.nextStillChange(pet, 5);
    if (end === undefined) expect.fail("the alert ends");
    expect(end).toBeCloseTo(5 + alert.duration, 9);

    pet.advance(end);
    expect(clips.stillFrame(pet), "the nudge woke the pet").toBe(frameOf("idle", 0));
    expect(clips.nextStillChange(pet, end)).toBeUndefined();
  });

  // The idle beats an idling pet starts in its first `seconds`, sampled at 30 fps.
  function idleBeats(happy: boolean, seconds = 120, seed = 7): PetPlayback[] {
    const pet = new PetAnimator(durations, { happy, at: 0, seed });
    const beats: PetPlayback[] = [];
    let time = 0;
    while (time < seconds) {
      time += 1 / 30;
      pet.advance(time);
      const playback = pet.playback;
      const last = beats.at(-1);
      if (playback && playback.animation !== "idle" && !(last && last.animation === playback.animation && last.startedAt === playback.startedAt)) {
        beats.push(playback);
      }
    }
    return beats;
  }

  it("a happy pet swishes its tail in place of every third blink", () => {
    const plain = idleBeats(false);
    expect(plain.every((beat) => beat.animation === "blink"), "before the bond grows the pet only blinks").toBe(true);

    const happy = idleBeats(true);
    expect(happy.length).toBeGreaterThan(2 * PetAnimator.happyBeatEvery);
    happy.forEach((beat, index) => {
      const swishes = (index + 1) % PetAnimator.happyBeatEvery === 0;
      expect(beat.animation, `beat ${index + 1}`).toBe(swishes ? "tailSwish" : "blink");
    });
    const swish = happy[PetAnimator.happyBeatEvery - 1];
    const next = happy[PetAnimator.happyBeatEvery];
    if (!swish || !next) expect.fail("enough beats");
    const gap = next.startedAt - (swish.startedAt + clips.clip("tailSwish").duration);
    expect(inBlinkInterval(gap), `gap ${gap}`).toBe(true);
    expect(happy.slice(0, PetAnimator.happyBeatEvery - 1), "the same seed blinks on the same beat").toEqual(
      plain.slice(0, PetAnimator.happyBeatEvery - 1),
    );
  });

  it("a happy pet idles with blinks alone while studying or asleep and holds still under Reduce Motion", () => {
    const pet = new PetAnimator(durations, { happy: true, at: 0, seed: 7 });
    const swish = idleBeats(true).find((beat) => beat.animation === "tailSwish");
    if (!swish) expect.fail("a swish");
    pet.advance(swish.startedAt + 0.01);
    expect(pet.playback).toEqual(swish);
    expect(clips.stillFrame(pet), "Reduce Motion shows the idle pose").toBe(frameOf("idle", 0));
    expect(clips.nextStillChange(pet, swish.startedAt + 0.01)).toBeUndefined();
    expect(clips.nextChange(pet, swish.startedAt + 0.01), "the swish animates").toBeDefined();

    pet.send({ kind: "activity", activity: "studying" }, swish.startedAt + 0.1);
    expect(pet.playback).toEqual({ animation: "typing", startedAt: swish.startedAt + 0.1 });
    pet.advance(swish.startedAt + 300);
    expect(pet.playback?.animation, "no idle beats on the laptop").toBe("typing");
    pet.send(event("sleep"), swish.startedAt + 301);
    pet.advance(swish.startedAt + 600);
    expect(pet.playback?.animation, "a dozing pet does not swish").toBe("sleep");
  });
});
