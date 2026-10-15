import { describe, expect, it } from "vitest";
import { type ClaudeStreamEvent, type ClaudeUsageWindow, parseClaudeStreamLine } from "../../src/core/claude/claudeStreamEvent";
import { ClaudeAskConversation } from "../../src/core/claudeAsk/claudeAskConversation";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/claude-stream/stream-json.json, written on the Mac
 * by ClaudeStreamGoldenTests: every raw `claude -p` line through the parser,
 * and every Ask exchange through the conversation reducer, comparing each
 * recorded output.
 */

interface FixtureWindow {
  utilization: number;
  resetsAt?: number;
}

interface FixtureEvent {
  type: string;
  sessionID?: string;
  text?: string;
  isError?: boolean;
  status?: string;
  fiveHour?: FixtureWindow;
  sevenDay?: FixtureWindow;
}

interface FixtureInput {
  action: string;
  prompt?: string;
  line?: string;
}

interface FixtureStep {
  input: FixtureInput;
  sent?: string;
  messages: { role: string; text: string; status: string }[];
  phase: string;
  failure?: string;
  sessionID?: string;
}

interface Fixture {
  schema: string;
  version: number;
  lines: { name: string; line: string; event: FixtureEvent }[];
  conversations: { name: string; steps: FixtureStep[] }[];
}

const fixture = loadFixture<Fixture>("claude-stream/stream-json.json");

function window(value: ClaudeUsageWindow): FixtureWindow {
  return value.resetsAt === undefined ? { utilization: value.utilization } : { utilization: value.utilization, resetsAt: value.resetsAt };
}

/** The neutral form the fixture records: `type` and only the fields that case carries. */
function neutral(event: ClaudeStreamEvent): FixtureEvent {
  const out: FixtureEvent = { type: event.type };
  switch (event.type) {
    case "sessionStarted":
      if (event.sessionID !== undefined) out.sessionID = event.sessionID;
      break;
    case "rateLimit":
      if (event.snapshot.status !== undefined) out.status = event.snapshot.status;
      if (event.snapshot.fiveHour) out.fiveHour = window(event.snapshot.fiveHour);
      if (event.snapshot.sevenDay) out.sevenDay = window(event.snapshot.sevenDay);
      break;
    case "textDelta":
    case "assistantText":
      out.text = event.text;
      break;
    case "result":
      if (event.result.text !== undefined) out.text = event.result.text;
      if (event.result.sessionID !== undefined) out.sessionID = event.result.sessionID;
      out.isError = event.result.isError;
      break;
    case "other":
      break;
  }
  return out;
}

/** Feeds `inputs` to a fresh conversation and records it after each one, like the Swift recorder. */
function run(inputs: FixtureInput[]): FixtureStep[] {
  const conversation = new ClaudeAskConversation("00000000-0000-0000-0000-000000000000", 0);
  return inputs.map((input) => {
    let sent: string | undefined;
    switch (input.action) {
      case "begin":
        sent = conversation.begin(input.prompt ?? "");
        break;
      case "line":
        conversation.applyClaude(parseClaudeStreamLine(input.line ?? ""));
        break;
      case "finish":
        conversation.finish();
        break;
      case "cancel":
        conversation.cancel();
        break;
      case "retry":
        sent = conversation.takeRetryQuestion()?.text;
        break;
      case "retryLostSession":
        sent = conversation.takeQuestionForLostSession()?.text;
        break;
      default:
        throw new Error(`Unknown action ${input.action}`);
    }
    const failure = conversation.failure;
    const step: FixtureStep = {
      input,
      messages: conversation.messages.map((message) => ({ role: message.role, text: message.text, status: message.status })),
      phase: conversation.phase.kind,
    };
    if (sent !== undefined) step.sent = sent;
    if (failure) step.failure = failure.kind === "process" ? failure.detail : "needsSetup";
    if (conversation.sessionID !== undefined) step.sessionID = conversation.sessionID;
    return step;
  });
}

describe("claude-stream golden fixture", () => {
  it("is the version this port reads", () => {
    expect(fixture.schema).toBe("tabbi.claude-stream.golden");
    expect(fixture.version).toBe(1);
    expect(fixture.lines).toHaveLength(34);
    expect(fixture.conversations).toHaveLength(13);
  });

  describe("lines", () => {
    for (const line of fixture.lines) {
      it(line.name, () => {
        expect(neutral(parseClaudeStreamLine(line.line))).toStrictEqual(line.event);
      });
    }
  });

  describe("conversations", () => {
    for (const conversation of fixture.conversations) {
      it(conversation.name, () => {
        const steps = run(conversation.steps.map((step) => step.input));
        expect(steps).toHaveLength(conversation.steps.length);
        steps.forEach((step, index) => expect(step, `step ${index}`).toStrictEqual(conversation.steps[index]));
      });
    }
  });
});
