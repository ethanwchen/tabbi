import { answer, type AIProvider } from "../ai/aiProvider";
import { promptRequest, type AIRequest } from "../ai/aiRequest";
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
 * Port of DayPlanner.request(prompt:): what Plan my day and the Schedule's
 * Refine send, the prompt alone, with the plan's JSON Schema for a provider
 * that can enforce it.
 */
export function planRequest(prompt: string): AIRequest {
  return promptRequest(prompt, "", DAY_PLAN_JSON_SCHEMA);
}

/**
 * Port of DayPlanner.answer(from:prompt:timeout:): `provider`'s whole
 * answer to `prompt`, or undefined on an error or after `timeoutSeconds`.
 * Plan my day and Refine both ask this way.
 */
export async function planAnswer(provider: AIProvider, prompt: string, timeoutSeconds = 60): Promise<string | undefined> {
  try {
    return await answer(provider, planRequest(prompt), AbortSignal.timeout(timeoutSeconds * 1000));
  } catch {
    return undefined;
  }
}
