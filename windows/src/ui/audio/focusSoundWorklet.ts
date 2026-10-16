/*
 * The focus sound processors, loaded into the AudioWorklet global scope by
 * FocusSoundEngine. They only wrap the pure DSP in core/focus/dsp, which
 * Vitest checks, so the audio thread runs exactly the tested code:
 *
 * - `tabbi-focus-synth` renders one synthesized sound (brown, pink or white
 *   noise, rain or the fireplace) at NoiseGenerator.targetRMS, mono.
 * - `tabbi-focus-soft-clip` applies the Mac mixer's soft clip to the sum.
 *
 * Gains (the mix, the loudness trims, volume and fades) are AudioParams on
 * the engine's GainNodes, not here.
 */

import { focusSoftClip } from "../../core/focus/dsp/gain";
import { SynthGenerator } from "../../core/focus/dsp/soundGenerator";
import { SOFT_CLIP_PROCESSOR, STOP_MESSAGE, SYNTH_PROCESSOR, type FocusSynthOptions } from "./focusSoundProtocol";

/* The AudioWorkletGlobalScope, which TypeScript's DOM library does not describe. */
declare const sampleRate: number;
declare class AudioWorkletProcessor {
  readonly port: MessagePort;
  constructor(options?: AudioWorkletNodeOptions);
}
declare function registerProcessor(name: string, processor: new (options: AudioWorkletNodeOptions) => AudioWorkletProcessor): void;

class FocusSynthProcessor extends AudioWorkletProcessor {
  private readonly generator: SynthGenerator;
  private running = true;

  constructor(options: AudioWorkletNodeOptions) {
    super(options);
    const { sound, seed } = options.processorOptions as FocusSynthOptions;
    this.generator = new SynthGenerator(sound, sampleRate, BigInt(seed));
    this.port.onmessage = (event: MessageEvent) => {
      if (event.data === STOP_MESSAGE) this.running = false;
    };
  }

  process(_inputs: Float32Array[][], outputs: Float32Array[][]): boolean {
    const output = outputs[0];
    const first = output?.[0];
    if (output === undefined || first === undefined) return this.running;
    this.generator.fill(first);
    for (let channel = 1; channel < output.length; channel++) output[channel]?.set(first);
    return this.running;
  }
}

class FocusSoftClipProcessor extends AudioWorkletProcessor {
  process(inputs: Float32Array[][], outputs: Float32Array[][]): boolean {
    const input = inputs[0];
    const output = outputs[0];
    if (output === undefined) return true;
    output.forEach((channel, index) => {
      const source = input?.[index];
      if (source === undefined) {
        channel.fill(0);
        return;
      }
      for (let i = 0; i < channel.length; i++) channel[i] = focusSoftClip(source[i] ?? 0);
    });
    return true;
  }
}

registerProcessor(SYNTH_PROCESSOR, FocusSynthProcessor);
registerProcessor(SOFT_CLIP_PROCESSOR, FocusSoftClipProcessor);
