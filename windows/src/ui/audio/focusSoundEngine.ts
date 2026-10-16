import { FADE_SECONDS, VOLUME_GLIDE_SECONDS, clampVolume, layerTargetGain, raisedCosineCurve, volumeAmplitude } from "../../core/focus/dsp/gain";
import { layerSeed, recordingStartFraction } from "../../core/focus/dsp/soundGenerator";
import type { Seed } from "../../core/focus/dsp/random";
import { FocusMix } from "../../core/focus/focusMix";
import { FOCUS_SAMPLE_RATE, gaplessWindow, monoSixteenBit, readGaplessInfo, recordingGain } from "../../core/focus/focusRecording";
import { FOCUS_SOUNDS, type FocusSound } from "../../core/focus/focusSound";
import { FocusSettings } from "../../core/focus/focusSettings";
import { SOFT_CLIP_PROCESSOR, STOP_MESSAGE, SYNTH_PROCESSOR, type FocusSynthOptions } from "./focusSoundProtocol";

/** What the engine needs from the browser, injectable so a test can drive it without a sound card. */
export interface FocusAudioPlatform {
  /** A fresh context; the engine asks for 48 kHz, the rate the Mac's mixer and the cafe loop use. */
  createContext(): AudioContext;
  /** The URL of the worklet module with the focus sound processors. */
  readonly workletUrl: string;
  /** The bundled cafe loop's bytes (a local asset; nothing leaves the PC). */
  loadCafe(): Promise<ArrayBuffer>;
  /** A fresh 64-bit seed, so each engine opens on a different moment of every sound. */
  randomSeed(): Seed;
  /** Where the finished mix goes; the context's speakers unless a meter or a recorder sits in between. */
  connectOutput?(context: AudioContext, output: AudioNode): void;
  setTimeout(callback: () => void, milliseconds: number): unknown;
  clearTimeout(handle: unknown): void;
}

/* How many points a glide's value curve gets per second; Web Audio interpolates between them. */
const CURVE_POINTS_PER_SECOND = 400;
/* How long after a fade lands before its layer or the context is let go. */
const SETTLE_MILLISECONDS = 250;

interface Layer {
  readonly gain: GainNode;
  source: AudioNode | undefined;
  target: number;
  teardown: unknown;
}

/**
 * Glides `param` from where it is now to `target` over `seconds` along the
 * Mac's raised-cosine curve (GainRamp), so fades and volume moves never click.
 * Retargeting mid-glide starts from wherever the value is.
 */
function glide(param: AudioParam, target: number, seconds: number, now: number): void {
  const current = param.value;
  if (typeof param.cancelAndHoldAtTime === "function") {
    param.cancelAndHoldAtTime(now);
  } else {
    param.cancelScheduledValues(now);
    param.setValueAtTime(current, now);
  }
  if (seconds <= 0 || current === target) {
    param.setValueAtTime(target, now);
    return;
  }
  const points = Math.max(Math.ceil(seconds * CURVE_POINTS_PER_SECOND), 2);
  param.setValueCurveAtTime(raisedCosineCurve(current, target, points), now, seconds);
}

/**
 * Port of FocusSoundEngine for Windows: plays a `FocusMix` through Web Audio,
 * mirroring the Mac's FocusMixer.
 *
 * Each synthesized sound in the mix is an AudioWorklet node running the
 * ported Swift DSP; the cafe is its recording, decoded once, trimmed to the
 * exact 120 s loop and looped sample-accurately by an AudioBufferSourceNode.
 * Every layer has its own gain (its share of the mix times its loudness trim),
 * then come the master volume (a squared curve), a 2 s transport fade and the
 * Mac's soft clip. Sounds leaving or joining crossfade over 2 s; the volume
 * glides over 50 ms.
 *
 * The context only runs while sound is audible: `play()` resumes it and fades
 * in; `stop()` fades out and suspends it once silent, so idle focus mode costs
 * no CPU and keeps no audio device awake.
 */
export class FocusSoundEngine {
  private readonly platform: FocusAudioPlatform;
  private readonly seed: Seed;
  private mixValue: FocusMix = FocusMix.off;
  private volumeValue: number;
  private playing = false;

  private context: AudioContext | undefined;
  private ready: Promise<void> | undefined;
  private master: GainNode | undefined;
  private transport: GainNode | undefined;
  private readonly layers = new Map<FocusSound, Layer>();
  private transportTarget = 0;
  private transportLandsAt = 0;
  private suspendTimer: unknown;
  private cafe: Promise<AudioBuffer | undefined> | undefined;

  constructor(platform: FocusAudioPlatform, volume: number = FocusSettings.default.volume) {
    this.platform = platform;
    this.seed = platform.randomSeed();
    this.volumeValue = clampVolume(volume);
  }

  get mix(): FocusMix {
    return this.mixValue;
  }

  get volume(): number {
    return this.volumeValue;
  }

  /** True between `play()` and `stop()`, while sound is (or is fading) in. */
  get isPlaying(): boolean {
    return this.playing;
  }

  /** True once stopped and fully faded out: the output is silence and the context can sleep. */
  get isSilent(): boolean {
    if (this.playing || this.context === undefined) return !this.playing;
    return this.transportTarget === 0 && this.context.currentTime >= this.transportLandsAt;
  }

  /** Changes the sounds; crossfades over 2 s while playing. Off while playing fades out and lets the context sleep. */
  setMix(mix: FocusMix): void {
    this.mixValue = mix;
    if (this.context !== undefined) this.applyMix(this.isSilent);
    if (this.playing) this.updateTransport();
  }

  /** Sets the 0...1 master volume; glides over 50 ms so sliders never zip. */
  setVolume(volume: number): void {
    this.volumeValue = clampVolume(volume);
    if (this.context !== undefined && this.master !== undefined) {
      glide(this.master.gain, volumeAmplitude(this.volumeValue), VOLUME_GLIDE_SECONDS, this.context.currentTime);
    }
  }

  /** Fades in over 2 s (starting the context) when the mix has any sound. */
  play(): void {
    this.playing = true;
    this.updateTransport();
  }

  /** Fades out over 2 s, then lets the context sleep. */
  stop(): void {
    if (!this.playing) return;
    this.playing = false;
    this.updateTransport();
  }

  /** Releases the audio device for good. */
  async close(): Promise<void> {
    this.playing = false;
    this.platform.clearTimeout(this.suspendTimer);
    const context = this.context;
    this.context = undefined;
    this.layers.clear();
    if (context !== undefined) await context.close();
  }

  /* The transport plays only when we are playing and there is something to hear. */
  private updateTransport(): void {
    if (this.playing && !this.mixValue.isOff) {
      this.platform.clearTimeout(this.suspendTimer);
      void this.start();
    } else {
      this.fadeTransport(0);
      this.scheduleSuspend();
    }
  }

  private async start(): Promise<void> {
    const context = this.ensureContext();
    await this.ready;
    if (!this.playing || this.context !== context) return;
    if (context.state !== "running") await context.resume();
    /* Coming out of silence the transport fade covers the mix, so the layers jump straight to their levels. */
    this.applyMix(this.transportTarget === 0 && context.currentTime >= this.transportLandsAt);
    this.fadeTransport(1);
  }

  private ensureContext(): AudioContext {
    if (this.context !== undefined) return this.context;
    const context = this.platform.createContext();
    this.context = context;
    const master = context.createGain();
    master.gain.value = volumeAmplitude(this.volumeValue);
    const transport = context.createGain();
    transport.gain.value = 0;
    this.master = master;
    this.transport = transport;
    this.ready = context.audioWorklet.addModule(this.platform.workletUrl).then(() => {
      const clip = new AudioWorkletNode(context, SOFT_CLIP_PROCESSOR, { numberOfOutputs: 1, outputChannelCount: [1] });
      master.connect(transport).connect(clip);
      if (this.platform.connectOutput === undefined) clip.connect(context.destination);
      else this.platform.connectOutput(context, clip);
    });
    return context;
  }

  private fadeTransport(target: number): void {
    const context = this.context;
    const transport = this.transport;
    if (context === undefined || transport === undefined) return;
    if (this.transportTarget === target) return;
    this.transportTarget = target;
    this.transportLandsAt = context.currentTime + FADE_SECONDS;
    glide(transport.gain, target, FADE_SECONDS, context.currentTime);
  }

  /* Polls until the fade-out lands, then suspends the context; playing again cancels it. */
  private scheduleSuspend(): void {
    const context = this.context;
    if (context === undefined) return;
    this.platform.clearTimeout(this.suspendTimer);
    this.suspendTimer = this.platform.setTimeout(() => {
      if (this.context !== context || this.playing && !this.mixValue.isOff) return;
      if (!this.isSilent) {
        this.scheduleSuspend();
        return;
      }
      void context.suspend();
    }, SETTLE_MILLISECONDS);
  }

  /*
   * Points every layer's gain at what the mix asks of it: a 2 s crossfade, or
   * at once while silent, since the transport fade covers the next start.
   */
  private applyMix(immediate: boolean): void {
    const context = this.context;
    const master = this.master;
    if (context === undefined || master === undefined) return;
    const seconds = immediate ? 0 : FADE_SECONDS;
    for (const sound of FOCUS_SOUNDS) {
      const target = layerTargetGain(this.mixValue, sound);
      let layer = this.layers.get(sound);
      if (layer === undefined) {
        if (target === 0) continue;
        layer = this.createLayer(context, master, sound);
      }
      this.platform.clearTimeout(layer.teardown);
      if (layer.target !== target) {
        layer.target = target;
        glide(layer.gain.gain, target, seconds, context.currentTime);
      }
      if (target === 0) this.scheduleTeardown(sound, layer, seconds);
    }
  }

  private createLayer(context: AudioContext, master: GainNode, sound: FocusSound): Layer {
    const gain = context.createGain();
    gain.gain.value = 0;
    gain.connect(master);
    const layer: Layer = { gain, source: undefined, target: 0, teardown: undefined };
    this.layers.set(sound, layer);
    const seed = layerSeed(this.seed, sound);
    if (sound === "cafe") {
      void this.cafeBuffer(context).then((buffer) => {
        if (buffer === undefined || this.layers.get(sound) !== layer) return;
        const source = new AudioBufferSourceNode(context, { buffer, loop: true });
        source.connect(gain);
        source.start(context.currentTime, recordingStartFraction(seed) * buffer.duration);
        layer.source = source;
      });
    } else {
      void this.ready?.then(() => {
        if (this.layers.get(sound) !== layer) return;
        const options: FocusSynthOptions = { sound, seed: seed.toString() };
        const node = new AudioWorkletNode(context, SYNTH_PROCESSOR, {
          numberOfInputs: 0,
          numberOfOutputs: 1,
          outputChannelCount: [1],
          processorOptions: options,
        });
        node.connect(gain);
        layer.source = node;
      });
    }
    return layer;
  }

  /* A layer that has faded out stops rendering, like the Mac mixer skipping silent layers. */
  private scheduleTeardown(sound: FocusSound, layer: Layer, seconds: number): void {
    layer.teardown = this.platform.setTimeout(() => {
      if (this.layers.get(sound) !== layer || layer.target !== 0) return;
      this.layers.delete(sound);
      const source = layer.source;
      if (source instanceof AudioScheduledSourceNode) source.stop();
      if (source instanceof AudioWorkletNode) source.port.postMessage(STOP_MESSAGE);
      source?.disconnect();
      layer.gain.disconnect();
    }, seconds * 1000 + SETTLE_MILLISECONDS);
  }

  /*
   * The cafe loop, decoded once per engine: trimmed to the encoder's own
   * length (exactly 5,760,000 samples at 48 kHz), down-mixed to mono and
   * scaled to NoiseGenerator.targetRMS like the Mac's FocusRecording, so its
   * loudness trim alone sets how loud it plays. Undefined when it cannot be
   * read, in which case the cafe is silent rather than breaking focus mode.
   */
  private cafeBuffer(context: AudioContext): Promise<AudioBuffer | undefined> {
    this.cafe ??= this.platform
      .loadCafe()
      .then(async (data) => {
        const gapless = readGaplessInfo(new Uint8Array(data.slice(0)));
        const decoded = await context.decodeAudioData(data);
        const channels = Array.from({ length: decoded.numberOfChannels }, (_, index) => decoded.getChannelData(index));
        const window =
          decoded.sampleRate === FOCUS_SAMPLE_RATE ? gaplessWindow(decoded.length, gapless) : { start: 0, length: decoded.length };
        const mono = monoSixteenBit(channels, window.start, window.length);
        const gain = recordingGain(mono);
        for (let i = 0; i < mono.length; i++) mono[i] = (mono[i] ?? 0) * gain;
        const buffer = context.createBuffer(1, mono.length, decoded.sampleRate);
        buffer.copyToChannel(mono, 0);
        return buffer;
      })
      .catch(() => undefined);
    return this.cafe;
  }
}
