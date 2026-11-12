import { createHash } from "node:crypto";
import type { PetCanvas } from "../../src/core/pets/petCanvas";
import type { PetClip } from "../../src/core/pets/petClip";

/*
 * The digest input and run-length frames the pet golden fixtures use
 * (shared/fixtures/pets/README.md), shared by the pets and Radiant replays.
 */

/** A growable little-endian byte buffer for the digest input. */
export class Bytes {
  private buffer = new Uint8Array(1 << 20);
  private view = new DataView(this.buffer.buffer);
  length = 0;

  private reserve(count: number): void {
    if (this.length + count <= this.buffer.length) return;
    let size = this.buffer.length * 2;
    while (size < this.length + count) size *= 2;
    const next = new Uint8Array(size);
    next.set(this.buffer.subarray(0, this.length));
    this.buffer = next;
    this.view = new DataView(next.buffer);
  }

  byte(value: number): void {
    this.reserve(1);
    this.buffer[this.length++] = value;
  }

  text(value: string): void {
    for (const byte of new TextEncoder().encode(value)) this.byte(byte);
  }

  uint32(value: number): void {
    this.reserve(4);
    this.view.setUint32(this.length, value, true);
    this.length += 4;
  }

  int32(value: number): void {
    this.reserve(4);
    this.view.setInt32(this.length, value, true);
    this.length += 4;
  }

  float64(value: number): void {
    this.reserve(8);
    this.view.setFloat64(this.length, value, true);
    this.length += 8;
  }

  symbols(canvas: PetCanvas): void {
    const text = canvas.symbols();
    this.reserve(text.length);
    for (let i = 0; i < text.length; i++) this.buffer[this.length++] = text.charCodeAt(i);
  }

  get bytes(): Uint8Array {
    return this.buffer.subarray(0, this.length);
  }
}

/** Rows joined by `/`, each a list of runs written as an optional count and a symbol. */
export function runLength(rows: readonly string[]): string {
  return rows
    .map((row) => {
      let out = "";
      let previous = "";
      let count = 0;
      const flush = () => {
        if (previous) out += (count > 1 ? String(count) : "") + previous;
      };
      for (const symbol of row) {
        if (symbol === previous) count += 1;
        else {
          flush();
          previous = symbol;
          count = 1;
        }
      }
      flush();
      return out;
    })
    .join("/");
}

export function decodeRunLength(text: string): string[] {
  return text.split("/").map((row) => {
    let out = "";
    let count = "";
    for (const character of row) {
      if (character >= "0" && character <= "9") count += character;
      else {
        out += character.repeat(count ? Number(count) : 1);
        count = "";
      }
    }
    return out;
  });
}


/** The `composed-digests.json` digest of a dress's clips, one per animation in declaration order. */
export function clipsDigest(clips: readonly PetClip[]): { frameCount: number; sha256: string } {
  const bytes = new Bytes();
  let frameCount = 0;
  for (const clip of clips) {
    frameCount += clip.frames.length;
    bytes.text(clip.animation);
    bytes.byte(0);
    bytes.uint32(clip.frames.length);
    for (const frame of clip.frames) {
      bytes.float64(frame.duration);
      bytes.byte(frame.bubbleAnchor ? 1 : 0);
      bytes.int32(frame.bubbleAnchor?.x ?? 0);
      bytes.int32(frame.bubbleAnchor?.y ?? 0);
      bytes.symbols(frame.canvas);
      if (frame.itemFrames.length > 0) {
        bytes.uint32(frame.itemFrames.length);
        for (const canvas of frame.itemFrames) bytes.symbols(canvas);
      }
    }
  }
  return { frameCount, sha256: createHash("sha256").update(bytes.bytes).digest("hex") };
}
