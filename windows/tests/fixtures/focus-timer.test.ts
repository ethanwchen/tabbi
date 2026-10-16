import { beforeAll, describe, expect, it } from "vitest";
import { FocusTimer, FocusTimerConfig, type FocusPhaseCompletion } from "../../src/core/focus/focusTimer";
import { completionActivityRecord } from "../../src/core/focus/focusTimerActivity";
import { focusClock, focusCompletionMessage, focusPhaseName, focusStatus } from "../../src/core/focus/focusTimerFormat";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { activityJson, providedJson } from "../support/focusGolden";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/focus-timer (written by FocusTimerGoldenTests on
 * the Mac): the countdown readouts and every Pomodoro sequence, comparing
 * each step's completions, timer state, focus card and shared focus clock.
 */

interface Input {
  action: string;
  at: number;
  focusDuration?: number;
  restDuration?: number;
}

interface Step {
  input: Input;
  [key: string]: unknown;
}

interface Golden {
  schema: string;
  version: number;
  clocks: { seconds: number; text: string }[];
  sequences: { name: string; steps: Step[] }[];
}

const golden = loadFixture<Golden>("focus-timer/focus-timer.json");

/** The module id the shared clock and activity records carry. */
const SOURCE = "focus";

function completionJson(completion: FocusPhaseCompletion, config: FocusTimerConfig): Record<string, unknown> {
  const message = focusCompletionMessage(completion, config);
  return {
    phase: completion.phase,
    endedAt: completion.endedAt,
    title: message.title,
    body: message.body,
    activity: activityJson(completionActivityRecord(completion, config, SOURCE)),
  };
}

function stateJson(timer: FocusTimer): Record<string, unknown> {
  const run = timer.runState;
  return {
    phase: timer.phase,
    run: run.kind,
    endsAt: run.kind === "running" ? run.endsAt : undefined,
    pausedRemaining: run.kind === "paused" ? run.remaining : undefined,
    focusDuration: timer.config.focusDuration,
    restDuration: timer.config.restDuration,
    completedFocusCount: timer.completedFocusCount,
  };
}

/** Feeds `inputs` to a fresh 25/5 timer and records it after each one, as the Swift test does. */
function run(inputs: Input[]): Record<string, unknown>[] {
  const timer = new FocusTimer();
  return inputs.map((input) => {
    const now = input.at;
    let completions: FocusPhaseCompletion[] = [];
    switch (input.action) {
      case "start":
        timer.start(now);
        break;
      case "pause":
        timer.pause(now);
        break;
      case "reset":
        timer.reset();
        break;
      case "skip":
        timer.skip(now);
        break;
      case "advance":
        completions = timer.advance(now);
        break;
      case "configure":
        timer.config = new FocusTimerConfig(input.focusDuration ?? 0, input.restDuration ?? 0);
        break;
      default:
        throw new Error(`Unknown action ${input.action}`);
    }
    return {
      input,
      completions: completions.map((completion) => completionJson(completion, timer.config)),
      state: stateJson(timer),
      view: {
        remaining: timer.remaining(now),
        progress: timer.progress(now),
        clock: focusClock(timer.remaining(now)),
        phaseName: focusPhaseName(timer.phase),
        status: focusStatus(timer),
      },
      provided: providedJson(timer.provided(SOURCE), now),
    };
  });
}

describe("focus-timer fixture", () => {
  beforeAll(() => switchLanguage("en"));

  it("is the version this port reads", () => {
    expect(golden.schema).toBe("tabbi.focus-timer.golden");
    expect(golden.version).toBe(1);
  });

  it("matches every countdown readout", () => {
    for (const clock of golden.clocks) expect(focusClock(clock.seconds), `${clock.seconds}`).toBe(clock.text);
  });

  for (const sequence of golden.sequences) {
    it(`replays ${sequence.name}`, () => {
      const replayed = run(sequence.steps.map((step) => step.input));
      expect(replayed).toHaveLength(sequence.steps.length);
      sequence.steps.forEach((step, index) => {
        expect(goldenDiff(replayed[index], step, `${sequence.name}[${index}] (${step.input.action})`)).toBeUndefined();
      });
    });
  }
});
