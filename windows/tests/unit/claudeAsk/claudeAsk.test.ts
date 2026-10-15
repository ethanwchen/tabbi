import { describe, expect, it } from "vitest";
import { assistantMessage, userMessage, AIProviderFailure } from "../../../src/core/ai/aiRequest";
import { ProcessFailure } from "../../../src/core/claude/claudeCLI";
import { fittedPixelSize, type ClaudeAskAttachment } from "../../../src/core/claudeAsk/claudeAskAttachment";
import { chatDateLabel, chatTitle, demoHistory, type ClaudeAskChat } from "../../../src/core/claudeAsk/claudeAskChat";
import {
  ClaudeAskConversation,
  demoConversation,
  failureDetail,
  failureFromError,
  failureNeedsSetup,
  failureSetupAction,
  failureSetupTitle,
  failureTitle,
  summarize,
} from "../../../src/core/claudeAsk/claudeAskConversation";
import { markdownBlocks, simplifyBlocks } from "../../../src/core/claudeAsk/claudeAskMarkdown";
import {
  CLAUDE_ASK_LARGE_VIEWS,
  decodeClaudeAskPreferences,
  largeViewTitle,
  offersExpand,
  opensLarge,
} from "../../../src/core/claudeAsk/claudeAskPreferences";

/* Port of the ClaudeAsk tests: conversation, failure, chat label, markdown, attachment and preferences. */

let ids = 0;
const fresh = () => new ClaudeAskConversation(`chat-${++ids}`, 0);
const answer = (conversation: ClaudeAskConversation) => conversation.messages.findLast((m) => m.role === "assistant");
const result = (text: string | undefined, sessionID: string | undefined, isError: boolean) =>
  ({ type: "result", result: { ...(text === undefined ? {} : { text }), ...(sessionID === undefined ? {} : { sessionID }), isError } }) as const;

function savedChat(sessionID: string | undefined, messages: [string, string][], sessionProvider?: "claude-cli"): ClaudeAskChat {
  return {
    id: "saved",
    createdAt: 0,
    updatedAt: 0,
    ...(sessionID === undefined ? {} : { sessionID }),
    ...(sessionProvider === undefined ? {} : { sessionProvider }),
    messages: messages.flatMap(([q, a]) => [
      { role: "user" as const, text: q, status: "complete" as const, attachments: [] },
      { role: "assistant" as const, text: a, status: "complete" as const, attachments: [] },
    ]),
  };
}

describe("ClaudeAskConversation", () => {
  it("adds a question and a streaming answer on begin", () => {
    const c = fresh();
    expect(c.begin("  What is 2+2?\n")).toBe("What is 2+2?");
    expect(c.isStreaming).toBe(true);
    expect(c.messages.map((m) => m.role)).toEqual(["user", "assistant"]);
    expect(c.messages[0]?.text).toBe("What is 2+2?");
    expect(answer(c)?.status).toBe("streaming");
    expect(answer(c)?.text).toBe("");
  });

  it("rejects a blank prompt or a busy conversation", () => {
    const c = fresh();
    expect(c.begin("  \n ")).toBeUndefined();
    expect(c.isEmpty).toBe(true);
    c.begin("one");
    expect(c.begin("two")).toBeUndefined();
    expect(c.messages).toHaveLength(2);
  });

  it("accumulates deltas and lets the result replace them", () => {
    const c = fresh();
    c.begin("hi");
    c.applyClaude({ type: "sessionStarted", sessionID: "s1" });
    c.applyClaude({ type: "textDelta", text: "Hel" });
    c.applyClaude({ type: "textDelta", text: "lo" });
    expect(answer(c)?.text).toBe("Hello");
    expect(answer(c)?.status).toBe("streaming");
    c.applyClaude(result("Hello there!", "s1", false));
    expect(answer(c)?.text).toBe("Hello there!");
    expect(answer(c)?.status).toBe("complete");
    expect(c.phase).toEqual({ kind: "idle" });
    expect(c.sessionID).toBe("s1");
  });

  it("lets a complete assistant message supersede the deltas", () => {
    const c = fresh();
    c.begin("hi");
    c.applyClaude({ type: "textDelta", text: "Hel" });
    c.applyClaude({ type: "assistantText", text: "Hello" });
    expect(answer(c)?.text).toBe("Hello");
    c.applyClaude({ type: "textDelta", text: "More" });
    expect(answer(c)?.text).toBe("Hello\n\nMore");
  });

  it("keeps streamed text when the result has none", () => {
    const c = fresh();
    c.begin("hi");
    c.applyClaude({ type: "textDelta", text: "Streamed" });
    c.applyClaude(result(undefined, undefined, false));
    expect(answer(c)?.text).toBe("Streamed");
    expect(answer(c)?.status).toBe("complete");
  });

  it("turns an error result into a failure with a summarized detail", () => {
    const c = fresh();
    c.begin("hi");
    c.applyClaude(result("\nAPI Error: overloaded\nstack...", "s1", true));
    expect(c.phase).toEqual({ kind: "failed", failure: { kind: "process", detail: "API Error: overloaded" } });
    expect(answer(c)?.status).toBe("failed");
    expect(c.sessionID).toBe("s1");
    const bare = fresh();
    bare.begin("hi");
    bare.applyClaude(result(undefined, undefined, true));
    expect(bare.failure?.kind === "process" && bare.failure.detail.length > 0).toBe(true);
  });

  it("keeps the session and history for a follow-up", () => {
    const c = fresh();
    c.begin("first");
    c.applyClaude({ type: "sessionStarted", sessionID: "s1" });
    c.applyClaude(result("A1", "s1", false));
    expect(c.begin("second")).toBe("second");
    expect(c.sessionID).toBe("s1");
    c.applyClaude({ type: "textDelta", text: "A2" });
    expect(c.messages.map((m) => m.text)).toEqual(["first", "A1", "second", "A2"]);
    expect(new Set(c.messages.map((m) => m.id)).size).toBe(4);
  });

  it("keeps the text or fails when the stream ends without a result", () => {
    const withText = fresh();
    withText.begin("hi");
    withText.applyClaude({ type: "textDelta", text: "partial" });
    withText.finish();
    expect(withText.phase).toEqual({ kind: "idle" });
    expect(answer(withText)?.status).toBe("complete");
    const empty = fresh();
    empty.begin("hi");
    empty.finish();
    expect(empty.failure?.kind).toBe("process");
  });

  it("keeps the partial text on cancel and ignores late events", () => {
    const c = fresh();
    c.begin("hi");
    c.applyClaude({ type: "textDelta", text: "Part" });
    c.cancel();
    expect(c.phase).toEqual({ kind: "idle" });
    expect(answer(c)?.status).toBe("stopped");
    c.applyClaude({ type: "textDelta", text: "ial" });
    c.finish();
    expect(answer(c)?.text).toBe("Part");
    expect(answer(c)?.status).toBe("stopped");
  });

  it("removes the failed exchange on retry and returns its question", () => {
    const c = fresh();
    c.begin("ok");
    c.applyClaude(result("fine", "s1", false));
    c.begin("boom");
    c.fail({ kind: "process", detail: "exit 1" });
    expect(c.takeRetryQuestion()).toEqual({ text: "boom", attachments: [] });
    expect(c.messages.map((m) => m.text)).toEqual(["ok", "fine"]);
    expect(c.phase).toEqual({ kind: "idle" });
    expect(c.takeRetryQuestion()).toBeUndefined();
  });

  it("drops a lost session and returns the question once", () => {
    const screenshot: ClaudeAskAttachment = { id: "shot", pixelWidth: 10, pixelHeight: 10 };
    const c = ClaudeAskConversation.restoring(savedChat("gone", [["ok", "fine"]]));
    c.begin("more", [screenshot]);
    c.fail({ kind: "process", detail: "No conversation found with session ID: gone" });
    expect(c.takeQuestionForLostSession()).toEqual({ text: "more", attachments: [screenshot] });
    expect(c.sessionID).toBeUndefined();
    expect(c.messages.map((m) => m.text)).toEqual(["ok", "fine"]);
    c.begin("more");
    c.fail({ kind: "process", detail: "No conversation found with session ID: gone" });
    expect(c.takeQuestionForLostSession()).toBeUndefined();
    expect(c.failure).toBeDefined();
  });

  it("asks a lost session again with the chat so far", () => {
    const c = ClaudeAskConversation.restoring(savedChat("gone", [["Retry policy?", "Back off and retry."]], "claude-cli"));
    c.begin("And jitter?");
    const resumed = c.request("And jitter?", "claude-cli");
    expect(resumed.resumeSessionID).toBe("gone");
    expect(resumed.messages).toEqual([userMessage("And jitter?")]);
    c.fail({ kind: "process", detail: "No conversation found with session ID: gone" });
    const question = c.takeQuestionForLostSession();
    if (!question) throw new Error("no question");
    c.begin(question.text);
    const seeded = c.request(question.text, "claude-cli");
    expect(seeded.resumeSessionID).toBeUndefined();
    expect(seeded.messages).toEqual([userMessage("Retry policy?"), assistantMessage("Back off and retry."), userMessage("And jitter?")]);
    expect(c.messages.findLast((m) => m.role === "user")?.text).toBe("And jitter?");
    c.apply({ kind: "sessionStarted", sessionID: "fresh" }, "claude-cli");
    c.apply({ kind: "finished", text: "Add randomness." }, "claude-cli");
    c.begin("Thanks");
    const next = c.request("Thanks", "claude-cli");
    expect(next.resumeSessionID).toBe("fresh");
    expect(next.messages).toEqual([userMessage("Thanks")]);
  });

  it("sends a new chat's question as typed with its screenshots", () => {
    const c = fresh();
    c.begin("Hi");
    const request = c.request("Hi", "openai", { images: [new Uint8Array([1])], system: "Be brief." });
    expect(request.messages).toEqual([userMessage("Hi", [new Uint8Array([1])])]);
    expect(request.system).toBe("Be brief.");
    expect(request.model).toBe("");
  });

  it("never lets another provider resume a session it does not hold", () => {
    const c = fresh();
    c.begin("Retry policy?");
    c.apply({ kind: "sessionStarted", sessionID: "claude-1" }, "claude-cli");
    c.apply({ kind: "finished", text: "Back off." }, "claude-cli");
    c.begin("Jitter?");
    for (const provider of ["codex-cli", "gemini", "ollama"] as const) {
      const request = c.request("Jitter?", provider);
      expect(request.resumeSessionID, provider).toBeUndefined();
      expect(request.messages).toEqual([userMessage("Retry policy?"), assistantMessage("Back off."), userMessage("Jitter?")]);
    }
  });

  it("keeps the latest whole exchanges within the transcript limit", () => {
    const c = ClaudeAskConversation.restoring(savedChat(undefined, [["a".repeat(50), "old"], ["recent", "latest"]]));
    c.begin("Next");
    const request = c.request("Next", "anthropic", { transcriptLimit: 30 });
    expect(request.messages).toEqual([userMessage("recent"), assistantMessage("latest"), userMessage("Next")]);
  });

  it("streams provider events into the answer", () => {
    const c = fresh();
    c.begin("Hi");
    c.apply({ kind: "textDelta", text: "Hel" }, "ollama");
    expect(c.messages.at(-1)?.text).toBe("Hel");
    expect(c.isStreaming).toBe(true);
    c.apply({ kind: "textDelta", text: "lo" }, "ollama");
    c.apply({ kind: "finished" }, "ollama");
    expect(c.messages.at(-1)?.text).toBe("Hello");
    expect(c.messages.at(-1)?.status).toBe("complete");
    expect(c.sessionID).toBeUndefined();
    c.begin("Again");
    c.apply({ kind: "textDelta", text: "draft" }, "codex-cli");
    c.apply({ kind: "finished", text: "Final answer" }, "codex-cli");
    expect(c.messages.at(-1)?.text).toBe("Final answer");
  });

  it("fails an empty answer naming the assistant", () => {
    const c = fresh();
    c.begin("Hi");
    c.apply({ kind: "finished" }, "gemini");
    expect(c.failure).toEqual({ kind: "process", detail: "Gemini ended without answering." });
  });

  it("remembers who was asked for each answer", () => {
    const c = fresh();
    c.begin("Hi", [], "ollama");
    c.fail({ kind: "process", detail: "Ollama is not running." });
    c.begin("Again", [], "gemini");
    const answers = c.messages.filter((m) => m.role === "assistant");
    expect(answers.map((m) => m.provider)).toEqual(["ollama", "gemini"]);
    expect(answers[0]?.status).toBe("failed");
    expect(c.messages[0]?.provider).toBeUndefined();
  });

  it("saves and restores the session's tool", () => {
    const c = fresh();
    c.begin("Hi");
    c.apply({ kind: "sessionStarted", sessionID: "codex-1" }, "codex-cli");
    c.apply({ kind: "finished", text: "Hello" }, "codex-cli");
    const chat = c.savedChat(10);
    if (!chat) throw new Error("nothing saved");
    expect(chat.sessionProvider).toBe("codex-cli");
    const restored = ClaudeAskConversation.restoring(chat);
    expect(restored.sessionProvider).toBe("codex-cli");
    expect(restored.sessionID).toBe("codex-1");
  });

  it("drops the tool's session when another provider answers", () => {
    const c = fresh();
    c.begin("Hi");
    c.applyClaude(result("Hello", "s1", false));
    c.begin("And the API?");
    c.apply({ kind: "textDelta", text: "Sure" }, "anthropic");
    c.apply({ kind: "finished" }, "anthropic");
    expect(c.sessionID).toBeUndefined();
    expect(c.sessionProvider).toBeUndefined();
    c.begin("Back to Claude Code");
    const request = c.request("Back to Claude Code", "claude-cli");
    expect(request.resumeSessionID).toBeUndefined();
    expect(request.messages.map((m) => m.text)).toEqual(["Hi", "Hello", "And the API?", "Sure", "Back to Claude Code"]);
  });

  it("keeps the session when the same tool answers", () => {
    const c = fresh();
    c.begin("Hi");
    c.apply({ kind: "sessionStarted", sessionID: "codex-1" }, "codex-cli");
    c.apply({ kind: "finished", text: "Hello" }, "codex-cli");
    c.begin("More");
    c.apply({ kind: "sessionStarted", sessionID: "codex-1" }, "codex-cli");
    c.apply({ kind: "textDelta", text: "Yes" }, "codex-cli");
    c.apply({ kind: "finished" }, "codex-cli");
    expect(c.sessionID).toBe("codex-1");
  });

  it("keeps the session through other failures", () => {
    const c = fresh();
    c.begin("ok");
    c.applyClaude(result("fine", "s1", false));
    c.begin("boom");
    c.fail({ kind: "process", detail: "exit 1" });
    expect(c.takeQuestionForLostSession()).toBeUndefined();
    expect(c.sessionID).toBe("s1");
    expect(c.failure).toEqual({ kind: "process", detail: "exit 1" });
  });

  it("marks the answer failed when the tool is missing, and clears the failure on the next question", () => {
    const c = fresh();
    c.begin("hi");
    c.fail({ kind: "notInstalled", provider: "claude-cli" });
    expect(c.phase).toEqual({ kind: "failed", failure: { kind: "notInstalled", provider: "claude-cli" } });
    expect(answer(c)?.status).toBe("failed");
    c.begin("again");
    expect(c.failure).toBeUndefined();
  });

  it("starts fresh with new ids on reset", () => {
    const c = fresh();
    c.begin("hi");
    c.applyClaude({ type: "sessionStarted", sessionID: "s1" });
    const oldIDs = new Set(c.messages.map((m) => m.id));
    c.reset("new-chat", 100);
    expect(c.isEmpty).toBe(true);
    expect(c.sessionID).toBeUndefined();
    expect(c.phase).toEqual({ kind: "idle" });
    expect(c.chatID).toBe("new-chat");
    c.begin("again");
    expect(c.messages.some((m) => oldIDs.has(m.id))).toBe(false);
  });

  it("summarizes to the first line and truncates", () => {
    expect(summarize(undefined)).toBeUndefined();
    expect(summarize(" \n ")).toBeUndefined();
    expect(summarize("\n  boom \nmore")).toBe("boom");
    const summary = summarize("x".repeat(300), 20);
    expect([...(summary ?? "")]).toHaveLength(20);
    expect(summary?.endsWith("…")).toBe(true);
  });
});

describe("ClaudeAskFailure", () => {
  it("turns provider errors into setup or their own words", () => {
    expect(failureFromError(new AIProviderFailure({ kind: "notInstalled" }), "codex-cli")).toEqual({ kind: "notInstalled", provider: "codex-cli" });
    expect(failureFromError(new AIProviderFailure({ kind: "missingAPIKey" }), "openai")).toEqual({ kind: "needsKey", provider: "openai" });
    expect(failureFromError(new AIProviderFailure({ kind: "unreachable" }), "ollama")).toEqual({
      kind: "process",
      detail: "Ollama is not running. Open Ollama and try again.",
    });
    expect(failureNeedsSetup({ kind: "needsKey", provider: "openai" })).toBe(true);
    expect(failureNeedsSetup({ kind: "process", detail: "x" })).toBe(false);
  });

  it("names the provider in the setup words", () => {
    expect(failureSetupTitle({ kind: "notInstalled", provider: "gemini-cli" })).toBe("Set up Gemini to ask questions");
    expect(failureSetupAction({ kind: "notInstalled", provider: "gemini-cli" })).toBe("Set up Gemini");
    expect(failureSetupTitle({ kind: "needsKey", provider: "anthropic" })).toBe("Add your Claude API key");
    expect(failureSetupAction({ kind: "noProvider" })).toBe("Choose AI");
    expect(failureTitle({ kind: "process", detail: "boom" }, "Codex")).toBe("Codex couldn't answer");
    expect(failureDetail({ kind: "process", detail: "boom" })).toBe("boom");
  });

  it("uses the first stderr line of a failed process, or its status", () => {
    expect(failureFromError(new ProcessFailure(3, "\n  Error: not logged in  \nat foo\n"), "claude-cli")).toEqual({
      kind: "process",
      detail: "Error: not logged in",
    });
    expect(failureFromError(new ProcessFailure(7, ""), "claude-cli")).toEqual({ kind: "process", detail: "Claude exited unexpectedly (status 7)." });
  });

  it("uses other errors' descriptions", () => {
    expect(failureFromError(new Error("The file doesn't exist."), "claude-cli")).toEqual({ kind: "process", detail: "The file doesn't exist." });
  });

  it("has a finished demo conversation that can follow up", () => {
    const demo = demoConversation("demo", 0);
    expect(demo.messages.map((m) => m.role)).toEqual(["user", "assistant", "user", "assistant"]);
    expect(demo.messages.every((m) => m.status === "complete")).toBe(true);
    expect(demo.messages.at(-1)?.text).not.toBe("");
    expect(demo.phase).toEqual({ kind: "idle" });
    expect(demo.sessionID).toBeDefined();
  });
});

describe("ClaudeAskChat", () => {
  const at = (year: number, month: number, day: number, hour = 12, minute = 0) => Date.UTC(year, month - 1, day, hour, minute) / 1000;
  const label = (updated: number, now: number) =>
    chatDateLabel({ id: "c", createdAt: updated, updatedAt: updated, messages: [] }, now, "UTC", "en-US");

  it("shows the time today", () => {
    /* ICU writes a narrow no-break space before AM in newer versions, a plain one in older. */
    expect(label(at(2026, 10, 5, 9, 41), at(2026, 10, 5, 18)).replace(/s/gu, " ")).toBe("9:41 AM");
  });
  it("counts yesterday by calendar day, not hours", () => expect(label(at(2026, 10, 4, 23, 50), at(2026, 10, 5, 0, 10))).toBe("Yesterday"));
  it("shows the weekday within the past week", () => expect(label(at(2026, 10, 1), at(2026, 10, 5))).toBe("Thursday"));
  it("shows the date, with a year only when it differs", () => {
    expect(label(at(2026, 9, 20), at(2026, 10, 5))).toBe("Sep 20");
    expect(label(at(2025, 12, 30), at(2026, 1, 10))).toBe("Dec 30, 2025");
  });

  it("titles a chat by its first question on one line", () => {
    const chat = savedChat(undefined, [["  Explain\n\nmutexes   please ", "ok"]]);
    expect(chatTitle(chat)).toBe("Explain mutexes please");
    expect(chatTitle({ ...chat, messages: [] })).toBe("Untitled chat");
  });

  it("has a demo history newest first that opens like a saved chat", () => {
    let next = 0;
    const now = at(2026, 10, 5);
    const chats = demoHistory(now, () => `demo-${++next}`);
    expect(chats.length).toBeGreaterThanOrEqual(3);
    expect(chats.map((c) => c.updatedAt)).toEqual([...chats.map((c) => c.updatedAt)].sort((a, b) => b - a));
    expect(new Set(chats.map((c) => c.id)).size).toBe(chats.length);
    expect(chats.every((c) => c.updatedAt <= now && c.sessionID !== undefined)).toBe(true);
    const first = chats[0];
    if (!first) throw new Error("no chats");
    expect(chatTitle(first)).toBe(chatTitle(demoConversation("x", 0).savedChat(0) ?? first));
    const restored = ClaudeAskConversation.restoring(first);
    expect(restored.chatID).toBe(first.id);
    expect(restored.sessionID).toBe(first.sessionID);
    expect(restored.savedChat(first.updatedAt)).toEqual(first);
  });

  it("can show a question asked about a screenshot", () => {
    let next = 0;
    const now = at(2026, 10, 5);
    const screenshot: ClaudeAskAttachment = { id: "shot", pixelWidth: 1440, pixelHeight: 900 };
    const chats = demoHistory(now, () => `demo-${++next}`, screenshot);
    expect(chats).toHaveLength(demoHistory(now, () => `other-${++next}`).length + 1);
    expect(chats[0]?.messages.every((m) => m.attachments.length === 0)).toBe(true);
    const second = chats[1];
    if (!second) throw new Error("no screenshot chat");
    const restored = ClaudeAskConversation.restoring(second);
    expect(restored.messages[0]?.role).toBe("user");
    expect(restored.messages[0]?.attachments).toEqual([screenshot]);
    expect(restored.messages.at(-1)?.status).toBe("complete");
  });
});

describe("ClaudeAskMarkdown", () => {
  it("keeps line breaks, turns bullets into dots and headings into bold", () => {
    expect(simplifyBlocks("First line\n\nSecond line")).toBe("First line\n\nSecond line");
    expect(simplifyBlocks("Options:\n- one\n* two\n  + nested")).toBe("Options:\n• one\n• two\n  • nested");
    expect(simplifyBlocks("## Summary\nBody")).toBe("**Summary**\nBody");
    expect(simplifyBlocks("#hashtag")).toBe("#hashtag");
    expect(simplifyBlocks("Run:\n```sh\nswift build\n```\nDone")).toBe("Run:\n`swift build`\nDone");
    expect(simplifyBlocks("```\nuse `x`\n\n```")).toBe("`use 'x'`\n");
  });

  it("keeps prose without fences as one block", () => {
    expect(markdownBlocks("One\n\n- two")).toEqual([{ kind: "text", text: "One\n\n- two" }]);
  });

  it("splits fenced code from prose, keeping language and indentation", () => {
    expect(markdownBlocks("Try this:\n\n```swift\nfunc a() {\n    b()\n}\n```\n\nThat's it.")).toEqual([
      { kind: "text", text: "Try this:" },
      { kind: "code", language: "swift", code: "func a() {\n    b()\n}", isClosed: true },
      { kind: "text", text: "That's it." },
    ]);
  });

  it("handles a fence without a language and with extra info", () => {
    expect(markdownBlocks("```\nls\n```")).toEqual([{ kind: "code", code: "ls", isClosed: true }]);
    expect(markdownBlocks("```sh title=x\nls\n```")).toEqual([{ kind: "code", language: "sh", code: "ls", isClosed: true }]);
  });

  it("runs an unclosed fence to the end while streaming", () => {
    expect(markdownBlocks("Run:\n```sh\nswift build\nswift te")).toEqual([
      { kind: "text", text: "Run:" },
      { kind: "code", language: "sh", code: "swift build\nswift te", isClosed: false },
    ]);
    expect(markdownBlocks("Run:\n```")).toEqual([{ kind: "text", text: "Run:" }, { kind: "code", code: "", isClosed: false }]);
  });

  it("removes only a fence's own indent in a list", () => {
    expect(markdownBlocks("- Step:\n  ```\n  if x {\n      y\n  }\n  ```")).toEqual([
      { kind: "text", text: "- Step:" },
      { kind: "code", code: "if x {\n    y\n}", isClosed: true },
    ]);
  });

  it("keeps blank lines inside code and has no blocks for an empty answer", () => {
    expect(markdownBlocks("```\na\n\nb\n```")).toEqual([{ kind: "code", code: "a\n\nb", isClosed: true }]);
    expect(markdownBlocks("")).toEqual([]);
    expect(markdownBlocks("\n\n")).toEqual([]);
  });
});

describe("ClaudeAskAttachment and preferences", () => {
  it("scales large captures to the long edge keeping their shape, never up", () => {
    expect(fittedPixelSize(3024, 1964)).toEqual({ width: 1568, height: 1018 });
    expect(fittedPixelSize(1000, 4000)).toEqual({ width: 392, height: 1568 });
    expect(fittedPixelSize(800, 600)).toEqual({ width: 800, height: 600 });
    expect(fittedPixelSize(0, 0)).toEqual({ width: 1, height: 1 });
    expect(fittedPixelSize(20_000, 1)).toEqual({ width: 1568, height: 1 });
  });

  it("opens the large view by the user's choice", () => {
    expect([opensLarge("askEachTime", false), opensLarge("askEachTime", true), offersExpand("askEachTime")]).toEqual([false, true, true]);
    expect([opensLarge("always", false), opensLarge("always", true), offersExpand("always")]).toEqual([true, true, true]);
    expect([opensLarge("never", false), opensLarge("never", true), offersExpand("never")]).toEqual([false, false, false]);
    expect(CLAUDE_ASK_LARGE_VIEWS.map(largeViewTitle)).toEqual(["Ask each time", "Always", "Never"]);
  });

  it("reads stored preferences leniently", () => {
    expect(decodeClaudeAskPreferences(undefined)).toEqual({ largeView: "askEachTime" });
    expect(decodeClaudeAskPreferences({ largeView: "always" })).toEqual({ largeView: "always" });
    expect(decodeClaudeAskPreferences({ largeView: "sometimes" })).toEqual({ largeView: "askEachTime" });
  });
});
