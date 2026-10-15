import { clockText } from "../calendar/zonedCalendar";
import { DAY_PLAN_JSON_SCHEMA, MAXIMUM_BLOCKS, dayPlanPrompt, parseDayPlan, validateDayPlan } from "../planner/dayPlan";
import type { DayPlanContext, PlanBlock } from "../planner/dayPlan";

/** Port of PlanRefinement: what Refine did, `changed` (moved, resized, retitled or dropped blocks) or `unchanged`. */
export type PlanRefinement = "changed" | "unchanged";

/* A refined plan may keep every local block, even past the usual most. */
function refineLimit(plan: readonly PlanBlock[]): number {
  return Math.max(MAXIMUM_BLOCKS, plan.length);
}

/**
 * Port of DayPlanner.refinePrompt: asks the AI the user picked to improve
 * the on-device plan, with the same day, free time and tasks as a plain
 * Plan my day request plus the local plan as the starting point. Blocks
 * name their task id where they work on a checklist item.
 */
export function refinePrompt(context: DayPlanContext, plan: readonly PlanBlock[]): string {
  const keys = new Map(context.taskKeys.map(({ key, task }) => [task.id, key]));
  const lines = [...plan]
    .sort((a, b) => a.start - b.start)
    .map((block) => {
      const key = block.linkedTaskID === undefined ? undefined : keys.get(block.linkedTaskID);
      const task = key === undefined ? "" : ` (task ${key})`;
      return `- ${clockText(block.start, context.timeZone)}-${clockText(block.end, context.timeZone)} ${block.title}${task}`;
    });
  return [
    dayPlanPrompt(context, refineLimit(plan)),
    "",
    "An on-device planner already proposed this plan, which is your starting point:",
    lines.length === 0 ? "- none" : lines.join("\n"),
    "",
    "Keep what works and change only what clearly makes the day better: " +
      "the order, block lengths, breaks between blocks, or a task it missed. " +
      "Answer with the complete plan in the JSON format above, unchanged if it is already good.",
  ].join("\n");
}

/**
 * Port of DayPlanner.refinement: the AI's refinement of `plan`, validated
 * against `context`. Blocks keep the kind of the local block for the same
 * task, or else with the same title (ignoring case). Throws when the
 * answer holds no JSON.
 */
export function refinedBlocks(text: string, context: DayPlanContext, plan: readonly PlanBlock[]): PlanBlock[] {
  const blocks = validateDayPlan(parseDayPlan(text, context), context, refineLimit(plan));
  return blocks.map((block) => {
    const local =
      plan.find((candidate) => candidate.linkedTaskID !== undefined && candidate.linkedTaskID === block.linkedTaskID) ??
      plan.find((candidate) => candidate.title.toLowerCase() === block.title.toLowerCase());
    return local === undefined ? block : { ...block, kind: local.kind };
  });
}

/**
 * What Plan my day and the Schedule's Refine send: the prompt alone, with
 * the plan's JSON Schema for a provider that can enforce it. A narrow
 * stand-in for the AI port's `promptRequest(prompt, "", schema)`.
 */
export interface PlanPromptRequest {
  readonly prompt: string;
  readonly responseSchema: string;
}

export function planPromptRequest(prompt: string): PlanPromptRequest {
  return { prompt, responseSchema: DAY_PLAN_JSON_SCHEMA };
}

/**
 * The whole answer to `prompt` from `ask` (the AI the user picked), or
 * undefined on an error or after `timeoutSeconds`. Plan my day and Refine
 * both ask this way. `ask` gets an abort signal that fires on the timeout.
 */
export async function planAnswer(
  ask: (request: PlanPromptRequest, signal: AbortSignal) => Promise<string>,
  prompt: string,
  timeoutSeconds = 60,
): Promise<string | undefined> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<undefined>((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve(undefined);
    }, timeoutSeconds * 1000);
  });
  try {
    return await Promise.race([ask(planPromptRequest(prompt), controller.signal), timeout]);
  } catch {
    return undefined;
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
