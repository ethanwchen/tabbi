import { describe, expect, it } from "vitest";
import type { AIProvider } from "../../../src/core/ai/aiProvider";
import { AIProviderFailure, type AIRequest, type AIStreamEvent } from "../../../src/core/ai/aiRequest";
import { DAY_PLAN_JSON_SCHEMA } from "../../../src/core/planner/dayPlan";
import { planAnswer, planRequest } from "../../../src/core/schedule/planRefinement";

/* A provider that answers with `events`, or never answers when there are none, recording each request. */
function provider(events: readonly AIStreamEvent[] | "never" | "fail"): AIProvider & { requests: AIRequest[] } {
  const requests: AIRequest[] = [];
  return {
    id: "ollama",
    requests,
    async *stream(request: AIRequest) {
      requests.push(request);
      if (events === "fail") throw new AIProviderFailure({ kind: "unreachable", detail: "down" });
      if (events === "never") await new Promise(() => undefined);
      else yield* events;
    },
  };
}

describe("asking the AI for a plan", () => {
  it("sends the prompt alone, with the plan's schema", () => {
    const request = planRequest("Plan my day");
    expect(request.messages).toHaveLength(1);
    expect(request.messages[0]?.text).toBe("Plan my day");
    expect(request.model).toBe("");
    expect(request.responseSchema).toBe(DAY_PLAN_JSON_SCHEMA);
  });

  it("returns the whole answer", async () => {
    const ai = provider([
      { kind: "textDelta", text: '{"blocks"' },
      { kind: "textDelta", text: ": []}" },
    ]);
    expect(await planAnswer(ai, "Plan my day")).toBe('{"blocks": []}');
    expect(ai.requests[0]?.responseSchema).toBe(DAY_PLAN_JSON_SCHEMA);
  });

  it("gives up quietly on an error or a timeout", async () => {
    expect(await planAnswer(provider("fail"), "Plan my day")).toBeUndefined();
    expect(await planAnswer(provider("never"), "Plan my day", 0.05)).toBeUndefined();
  });
});
