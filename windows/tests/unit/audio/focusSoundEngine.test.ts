import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { layerTargetGain, raisedCosineCurve, volumeAmplitude } from "../../../src/core/focus/dsp/gain";
import { layerSeed, recordingStartFraction } from "../../../src/core/focus/dsp/soundGenerator";
import { FocusMix } from "../../../src/core/focus/focusMix";
import { CAFE_LOOP_SAMPLES } from "../../../src/core/focus/focusRecording";
import { FocusSoundEngine, type FocusAudioPlatform } from "../../../src/ui/audio/focusSoundEngine";
import { STOP_MESSAGE, SYNTH_PROCESSOR } from "../../../src/ui/audio/focusSoundProtocol";

/*
 * Drives FocusSoundEngine against a recording fake of the Web Audio API, to
 * pin the graph and the automation it schedules: which nodes play each sound,
 * the layer gains with their loudness trims, the volume curve, the 2 s fades,
 * the cafe loop's trim and start, and when the context sleeps. The sound
 * itself was checked end to end in Microsoft Edge (see the port's notes).
 */

type Event =
  | { kind: "hold"; time: number }
  | { kind: "set"; value: number; time: number }
  | { kind: "curve"; curve: number[]; time: number; duration: number };

class FakeParam {
  value = 1;
  events: Event[] = [];
  cancelAndHoldAtTime(time: number): void {
    this.events.push({ kind: "hold", time });
  }
  cancelScheduledValues(): void {}
  setValueAtTime(value: number, time: number): void {
    this.value = value;
    this.events.push({ kind: "set", value, time });
  }
  setValueCurveAtTime(curve: Float32Array, time: number, duration: number): void {
    this.value = curve[curve.length - 1] ?? this.value;
    this.events.push({ kind: "curve", curve: Array.from(curve), time, duration });
  }
  get last(): Event | undefined {
    return this.events[this.events.length - 1];
  }
}

class FakeNode {
  outputs: FakeNode[] = [];
  disconnected = false;
  connect<T>(target: T): T {
    this.outputs.push(target as unknown as FakeNode);
    return target;
  }
  disconnect(): void {
    this.disconnected = true;
  }
}

class FakeGain extends FakeNode {
  gain = new FakeParam();
}

class FakeScheduledSource extends FakeNode {}

class FakeBufferSource extends FakeScheduledSource {
  started: [number, number] | undefined;
  stopped = false;
  readonly buffer: FakeBuffer;
  readonly loop: boolean;
  constructor(_context: unknown, options: { buffer: FakeBuffer; loop: boolean }) {
    super();
    this.buffer = options.buffer;
    this.loop = options.loop;
    created.push(this);
  }
  start(when: number, offset: number): void {
    this.started = [when, offset];
  }
  stop(): void {
    this.stopped = true;
  }
}

class FakeWorkletNode extends FakeNode {
  readonly messages: unknown[] = [];
  readonly port = { postMessage: (message: unknown) => this.messages.push(message) };
  constructor(
    _context: unknown,
    readonly name: string,
    readonly options: AudioWorkletNodeOptions,
  ) {
    super();
    created.push(this);
  }
}

class FakeBuffer {
  readonly channels: Float32Array[];
  constructor(
    channelCount: number,
    readonly length: number,
    readonly sampleRate: number,
  ) {
    this.channels = Array.from({ length: channelCount }, () => new Float32Array(length));
  }
  get numberOfChannels(): number {
    return this.channels.length;
  }
  get duration(): number {
    return this.length / this.sampleRate;
  }
  getChannelData(index: number): Float32Array {
    return this.channels[index] ?? new Float32Array(0);
  }
  copyToChannel(source: Float32Array, index: number): void {
    this.channels[index]?.set(source);
  }
}

class FakeContext {
  currentTime = 0;
  state: "suspended" | "running" | "closed" = "suspended";
  readonly destination = new FakeNode();
  readonly gains: FakeGain[] = [];
  readonly modules: string[] = [];
  suspends = 0;
  readonly audioWorklet = {
    addModule: async (url: string) => {
      this.modules.push(url);
    },
  };
  async resume(): Promise<void> {
    this.state = "running";
  }
  async suspend(): Promise<void> {
    this.suspends += 1;
    this.state = "suspended";
  }
  async close(): Promise<void> {
    this.state = "closed";
  }
  createGain(): FakeGain {
    const gain = new FakeGain();
    this.gains.push(gain);
    return gain;
  }
  createBuffer(channels: number, length: number, rate: number): FakeBuffer {
    return new FakeBuffer(channels, length, rate);
  }
  /* A decoder that keeps the encoder's trailing padding, as some do; the engine trims it. */
  async decodeAudioData(): Promise<FakeBuffer> {
    const buffer = new FakeBuffer(1, CAFE_LOOP_SAMPLES + 960, 48_000);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.sin(i / 7) * 0.1;
    return buffer;
  }
}

let created: (FakeWorkletNode | FakeBufferSource)[] = [];

const cafeBytes = readFileSync(
  fileURLToPath(new URL("../../../../Sources/TabbiKitCore/Focus/FocusRecordings/cafe.m4a", import.meta.url)),
);

const SEED = 0x1234_5678_9abc_def0n;

function setup(): { engine: FocusSoundEngine; context: FakeContext; timers: (() => void)[]; settle: () => Promise<void> } {
  const context = new FakeContext();
  const timers: (() => void)[] = [];
  const platform: FocusAudioPlatform = {
    createContext: () => context as unknown as AudioContext,
    workletUrl: "/worklet.js",
    loadCafe: async () => cafeBytes.buffer.slice(cafeBytes.byteOffset, cafeBytes.byteOffset + cafeBytes.byteLength),
    randomSeed: () => SEED,
    setTimeout: (callback) => timers.push(callback),
    clearTimeout: () => undefined,
  };
  const settle = async (): Promise<void> => {
    for (let i = 0; i < 10; i++) await new Promise((resolve) => setTimeout(resolve, 0));
  };
  return { engine: new FocusSoundEngine(platform, 0.7), context, timers, settle };
}

/* The context's gains in creation order: master, transport, then one per layer. */
function graph(context: FakeContext): { master: FakeGain; transport: FakeGain; layers: FakeGain[] } {
  const [master, transport, ...layers] = context.gains;
  if (master === undefined || transport === undefined) throw new Error("no graph");
  return { master, transport, layers };
}

function curveEvent(param: FakeParam): { curve: number[]; time: number; duration: number } {
  const event = param.last;
  if (event?.kind !== "curve") throw new Error(`expected a curve, got ${JSON.stringify(event)}`);
  return event;
}

beforeEach(() => {
  created = [];
  vi.stubGlobal("AudioWorkletNode", FakeWorkletNode);
  vi.stubGlobal("AudioBufferSourceNode", FakeBufferSource);
  vi.stubGlobal("AudioScheduledSourceNode", FakeScheduledSource);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("FocusSoundEngine", () => {
  it("opens no audio device until there is something to play", () => {
    const { engine, context } = setup();
    engine.play();
    expect(context.gains).toHaveLength(0);
    expect(engine.isPlaying).toBe(true);
  });

  it("plays a synthesized sound through the worklet with its trim, then fades in over 2 s", async () => {
    const { engine, context, settle } = setup();
    engine.setMix(FocusMix.single("brown"));
    engine.play();
    await settle();
    expect(context.modules).toEqual(["/worklet.js"]);
    expect(context.state).toBe("running");
    const { master, transport, layers } = graph(context);
    expect(master.gain.value).toBe(volumeAmplitude(0.7));
    const synth = created.find((node): node is FakeWorkletNode => node instanceof FakeWorkletNode && node.name === SYNTH_PROCESSOR);
    expect(synth?.options.processorOptions).toEqual({ sound: "brown", seed: layerSeed(SEED, "brown").toString() });
    const layer = layers[0];
    expect(layer?.gain.last).toEqual({ kind: "set", value: layerTargetGain(FocusMix.single("brown"), "brown"), time: 0 });
    const fade = curveEvent(transport.gain);
    expect([fade.time, fade.duration, fade.curve[0], fade.curve[fade.curve.length - 1]]).toEqual([0, 2, 0, 1]);
    expect(fade.curve).toEqual(Array.from(raisedCosineCurve(0, 1, fade.curve.length)));
  });

  it("crossfades to the cafe loop, trimmed to 120 s and looped from the seed's start", async () => {
    const { engine, context, timers, settle } = setup();
    engine.setMix(FocusMix.single("brown"));
    engine.play();
    await settle();
    context.currentTime = 5;
    engine.setMix(FocusMix.single("cafe"));
    await settle();
    const { layers } = graph(context);
    const [brownGain, cafeGain] = layers;
    const out = curveEvent(brownGain?.gain ?? new FakeParam());
    expect([out.time, out.duration, out.curve[out.curve.length - 1]]).toEqual([5, 2, 0]);
    const into = curveEvent(cafeGain?.gain ?? new FakeParam());
    expect(into.curve[into.curve.length - 1]).toBe(layerTargetGain(FocusMix.single("cafe"), "cafe"));

    const loop = created.find((node): node is FakeBufferSource => node instanceof FakeBufferSource);
    expect(loop?.loop).toBe(true);
    expect(loop?.buffer.length).toBe(CAFE_LOOP_SAMPLES);
    expect(loop?.started).toEqual([5, recordingStartFraction(layerSeed(SEED, "cafe")) * 120]);

    /* Once faded out, the brown layer stops rendering. */
    timers.splice(0).forEach((run) => run());
    const brown = created.find((node): node is FakeWorkletNode => node instanceof FakeWorkletNode && node.name === SYNTH_PROCESSOR);
    expect(brown?.messages).toEqual([STOP_MESSAGE]);
    expect(brown?.disconnected).toBe(true);
  });

  it("glides the volume over 50 ms on a squared curve", async () => {
    const { engine, context, settle } = setup();
    engine.setMix(FocusMix.single("pink"));
    engine.play();
    await settle();
    context.currentTime = 1;
    engine.setVolume(0.5);
    const glide = curveEvent(graph(context).master.gain);
    expect([glide.time, glide.duration, glide.curve[glide.curve.length - 1]]).toEqual([1, 0.05, 0.25]);
    expect(engine.volume).toBe(0.5);
  });

  it("fades out on stop and lets the context sleep once silent", async () => {
    const { engine, context, timers, settle } = setup();
    engine.setMix(FocusMix.single("rain"));
    engine.play();
    await settle();
    context.currentTime = 10;
    engine.stop();
    const fade = curveEvent(graph(context).transport.gain);
    expect([fade.time, fade.duration, fade.curve[fade.curve.length - 1]]).toEqual([10, 2, 0]);
    expect(engine.isSilent).toBe(false);

    context.currentTime = 11;
    timers.splice(0).forEach((run) => run());
    expect(context.suspends).toBe(0);
    context.currentTime = 12.1;
    timers.splice(0).forEach((run) => run());
    expect(context.suspends).toBe(1);
    expect(engine.isSilent).toBe(true);
  });

  it("switching to Off while playing fades out, and a new sound fades back in", async () => {
    const { engine, context, settle } = setup();
    engine.setMix(FocusMix.single("fireplace"));
    engine.play();
    await settle();
    context.currentTime = 3;
    engine.setMix(FocusMix.off);
    expect(curveEvent(graph(context).transport.gain).curve.at(-1)).toBe(0);
    context.currentTime = 3.5;
    engine.setMix(FocusMix.single("white"));
    await settle();
    const back = curveEvent(graph(context).transport.gain);
    expect([back.time, back.curve.at(-1)]).toEqual([3.5, 1]);
  });
});
