import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  CAFE_LOOP_SAMPLES,
  FOCUS_SAMPLE_RATE,
  gaplessWindow,
  monoSixteenBit,
  readMp4AudioTiming,
  recordingGain,
} from "../../../src/core/focus/focusRecording";
import { loudnessGain } from "../../../src/core/focus/focusSound";
import { NOISE_TARGET_RMS } from "../../../src/core/focus/dsp/noise";
import { loudness, rms } from "../../support/signalAnalysis";

/*
 * The cafe loop must decode to exactly 5,760,000 samples at 48 kHz with no
 * seam (docs/windows/HANDOFF.md, section 4). Node has no AAC decoder of its
 * own, so the file's timing is always checked from its metadata, and the
 * decode itself runs only where an ffmpeg binary is on the PATH (the same
 * FFmpeg family Chromium decodes with); elsewhere that test is skipped.
 */

const cafePath = fileURLToPath(new URL("../../../../Sources/TabbiKitCore/Focus/FocusRecordings/cafe.m4a", import.meta.url));
const bytes = new Uint8Array(readFileSync(cafePath));

const hasFfmpeg = spawnSync("ffmpeg", ["-version"], { stdio: "ignore" }).status === 0;

describe("cafe loop metadata", () => {
  const timing = readMp4AudioTiming(bytes);

  it("is 48 kHz and 120 s once the encoder's delay and padding are taken out", () => {
    expect(timing?.timescale).toBe(FOCUS_SAMPLE_RATE);
    expect(timing?.gapless).toEqual({ priming: 2112, padding: 960, length: CAFE_LOOP_SAMPLES });
    const gapless = timing?.gapless;
    expect(timing === undefined || gapless === undefined ? -1 : timing.mediaDuration - gapless.priming - gapless.padding).toBe(
      CAFE_LOOP_SAMPLES,
    );
  });

  it("finds the loop in whatever a decoder hands back", () => {
    const gapless = timing?.gapless;
    expect(gaplessWindow(5_760_000, gapless)).toEqual({ start: 0, length: CAFE_LOOP_SAMPLES });
    expect(gaplessWindow(5_760_960, gapless)).toEqual({ start: 0, length: CAFE_LOOP_SAMPLES });
    expect(gaplessWindow(5_762_112, gapless)).toEqual({ start: 2112, length: CAFE_LOOP_SAMPLES });
    expect(gaplessWindow(5_763_072, gapless)).toEqual({ start: 2112, length: CAFE_LOOP_SAMPLES });
    expect(gaplessWindow(1234, gapless)).toEqual({ start: 0, length: 1234 });
    expect(gaplessWindow(1234, undefined)).toEqual({ start: 0, length: 1234 });
  });
});

describe.skipIf(!hasFfmpeg)("cafe loop decoded with ffmpeg", () => {
  const decode = (): Float32Array => {
    const result = spawnSync("ffmpeg", ["-v", "error", "-i", cafePath, "-f", "f32le", "-ac", "1", "-ar", "48000", "-"], {
      maxBuffer: 64 * 1024 * 1024,
    });
    expect(result.status).toBe(0);
    const raw = result.stdout;
    return new Float32Array(raw.buffer, raw.byteOffset, raw.byteLength / 4);
  };

  /*
   * Decoding two minutes of audio and sorting 5.76 million steps takes a
   * second or two alone and several times that on a busy machine, well past
   * Vitest's 5 s default, so this test has a budget of its own (below).
   */
  it("is exactly 5,760,000 samples at 48 kHz, wraps with no seam, and plays at the shared loudness", () => {
    const decoded = decode();
    const window = gaplessWindow(decoded.length, readMp4AudioTiming(bytes)?.gapless);
    expect(window.length).toBe(CAFE_LOOP_SAMPLES);
    const loop = monoSixteenBit([decoded], window.start, window.length);
    expect(loop.length).toBe(CAFE_LOOP_SAMPLES);

    /* The jump from the last sample back to the first is no bigger than the loop's ordinary steps. */
    const steps = new Float32Array(loop.length - 1);
    for (let i = 1; i < loop.length; i += 1) steps[i - 1] = Math.abs((loop[i] ?? 0) - (loop[i - 1] ?? 0));
    steps.sort();
    const typicalLargeStep = steps[Math.floor(steps.length * 0.999)] ?? 0;
    const seam = Math.abs((loop[0] ?? 0) - (loop[loop.length - 1] ?? 0));
    expect(seam).toBeLessThanOrEqual(typicalLargeStep);

    const gain = recordingGain(loop);
    const scaled = Float32Array.from(loop, (value) => value * gain);
    expect(rms(scaled)).toBeCloseTo(NOISE_TARGET_RMS, 4);
    const trimmed = Float32Array.from(scaled.subarray(0, FOCUS_SAMPLE_RATE * 30), (value) => value * loudnessGain("cafe"));
    expect(Math.abs(loudness(trimmed) - -17)).toBeLessThan(1);
  }, 60_000);
});
