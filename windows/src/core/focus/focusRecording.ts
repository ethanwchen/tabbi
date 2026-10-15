import { NOISE_TARGET_RMS } from "./dsp/noise";

/*
 * Port of the pure parts of FocusRecording: the bundled cafe loop
 * (`Sources/TabbiKitCore/Focus/FocusRecordings/cafe.m4a`), mono AAC at
 * 48 kHz whose encoder records its delay, so it decodes to exactly 5,760,000
 * samples (120 s) and loops with no seam. Decoding itself is the platform's
 * job (Web Audio's decodeAudioData); these read the file's own timing and
 * level so the engine can trim and scale whatever the decoder hands back.
 */

/** The cafe loop's length in samples at its own rate, from docs/sounds.md. */
export const CAFE_LOOP_SAMPLES = 5_760_000;
/** The rate the cafe is encoded at, and the rate the Mac's mixer plays at. */
export const FOCUS_SAMPLE_RATE = 48_000;

/** The encoder's gapless playback info (Apple's iTunSMPB tag). */
export interface GaplessInfo {
  /** Samples of encoder delay before the audio starts. */
  readonly priming: number;
  /** Samples of padding after the audio ends. */
  readonly padding: number;
  /** The audio's own length, without priming or padding. */
  readonly length: number;
}

/** What an MP4 audio file says about its timing. */
export interface Mp4AudioTiming {
  /** The media timescale (the sample rate, for AAC). */
  readonly timescale: number;
  /** The media length in timescale units, priming and padding included. */
  readonly mediaDuration: number;
  readonly gapless: GaplessInfo | undefined;
}

const CONTAINERS = new Set(["moov", "trak", "mdia", "minf", "stbl", "udta", "edts"]);

function boxType(bytes: Uint8Array, offset: number): string {
  return String.fromCharCode(bytes[offset] ?? 0, bytes[offset + 1] ?? 0, bytes[offset + 2] ?? 0, bytes[offset + 3] ?? 0);
}

function findBox(bytes: Uint8Array, view: DataView, start: number, end: number, type: string): number | undefined {
  let offset = start;
  while (offset + 8 <= end) {
    let size = view.getUint32(offset);
    const name = boxType(bytes, offset + 4);
    let header = 8;
    if (size === 1) {
      size = Number(view.getBigUint64(offset + 8));
      header = 16;
    } else if (size === 0) {
      size = end - offset;
    }
    if (size < header) return undefined;
    if (name === type) return offset;
    if (CONTAINERS.has(name)) {
      const inner = findBox(bytes, view, offset + header, offset + size, type);
      if (inner !== undefined) return inner;
    }
    offset += size;
  }
  return undefined;
}

/** Reads the iTunSMPB tag ("00000000 00000840 000003C0 000000000057E400 ...") from an MP4 file's bytes. */
export function readGaplessInfo(bytes: Uint8Array): GaplessInfo | undefined {
  const text = new TextDecoder("latin1").decode(bytes);
  const tag = text.indexOf("iTunSMPB");
  if (tag < 0) return undefined;
  const fields = text
    .slice(tag, tag + 200)
    .match(/(?: [0-9A-Fa-f]{8}){3} [0-9A-Fa-f]{16}/)?.[0]
    .trim()
    .split(" ");
  if (fields === undefined) return undefined;
  const [, priming, padding, length] = fields.map((field) => Number.parseInt(field, 16));
  if (priming === undefined || padding === undefined || length === undefined) return undefined;
  return { priming, padding, length };
}

/** Reads the audio track's timescale and length (its `mdhd` box) and the gapless tag from an MP4 file. */
export function readMp4AudioTiming(bytes: Uint8Array): Mp4AudioTiming | undefined {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const mdhd = findBox(bytes, view, 0, bytes.byteLength, "mdhd");
  if (mdhd === undefined) return undefined;
  const version = bytes[mdhd + 8];
  const timescale = version === 1 ? view.getUint32(mdhd + 28) : view.getUint32(mdhd + 20);
  const mediaDuration = version === 1 ? Number(view.getBigUint64(mdhd + 32)) : view.getUint32(mdhd + 24);
  return { timescale, mediaDuration, gapless: readGaplessInfo(bytes) };
}

/**
 * Which decoded samples are the loop itself. Decoders differ in how much of
 * the encoder's priming and padding they drop (FFmpeg drops both, some drop
 * only the priming, some neither), so the decoded length says which case this
 * is; anything unexpected keeps the whole buffer.
 */
export function gaplessWindow(decodedLength: number, gapless: GaplessInfo | undefined): { start: number; length: number } {
  if (gapless === undefined) return { start: 0, length: decodedLength };
  const { priming, padding, length } = gapless;
  if (decodedLength === length) return { start: 0, length };
  if (decodedLength === length + padding) return { start: 0, length };
  if (decodedLength === priming + length) return { start: priming, length };
  if (decodedLength === priming + length + padding) return { start: priming, length };
  return { start: 0, length: decodedLength };
}

/**
 * Port of FocusRecording.decode's down-mix: averages the channels into mono
 * and keeps the Mac's 16-bit resolution, so the level matches what the Mac
 * computes its gain from.
 */
export function monoSixteenBit(channels: readonly Float32Array[], start = 0, length?: number): Float32Array {
  const count = length ?? (channels[0]?.length ?? 0) - start;
  const scale = Math.fround(32767 / Math.max(channels.length, 1));
  const out = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    let sum = 0;
    for (const channel of channels) sum = Math.fround(sum + (channel[start + i] ?? 0));
    const quantized = Math.trunc(Math.max(Math.min(Math.fround(sum * scale), 32767), -32767));
    out[i] = quantized / 32767;
  }
  return out;
}

/**
 * Port of FocusRecording.gain: the factor that brings the recording to
 * NOISE_TARGET_RMS like every synthesized sound, so the file's own level never
 * matters and the loudness trim alone sets how loud it plays. 0 for silence.
 */
export function recordingGain(samples: Float32Array): number {
  let power = 0;
  for (const sample of samples) power += sample * sample;
  const rms = samples.length === 0 ? 0 : Math.sqrt(power / samples.length);
  return rms > 0 ? Math.fround(NOISE_TARGET_RMS / Math.fround(rms)) : 0;
}
