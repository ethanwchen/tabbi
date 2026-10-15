import { describe, expect, it } from "vitest";
import {
  claudeEvents,
  claudeExecutableCandidates,
  claudeInputArguments,
  claudeInputLine,
  claudePromptArguments,
} from "../../../src/core/claude/claudeCLI";
import { parseClaudeStreamLine } from "../../../src/core/claude/claudeStreamEvent";

/* Port of ClaudeStreamEventTests and the pure parts of ClaudeCLIStreamTests. */

describe("ClaudeStreamEvent", () => {
  it("parses both rate-limit windows", () => {
    const line = `{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1790912400,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.05,"resetsAt":1790912400},"seven_day":{"utilization":0.04,"resetsAt":1791460800}}},"session_id":"s"}`;
    const event = parseClaudeStreamLine(line);
    if (event.type !== "rateLimit") throw new Error("expected rateLimit");
    expect(event.snapshot.status).toBe("allowed");
    expect(event.snapshot.fiveHour).toEqual({ utilization: 0.05, resetsAt: 1790912400 });
    expect(event.snapshot.sevenDay?.utilization).toBe(0.04);
  });

  it("has no windows when the event has none", () => {
    expect(parseClaudeStreamLine(`{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}`)).toEqual({
      type: "rateLimit",
      snapshot: { status: "allowed" },
    });
  });

  it("carries the session id of system init", () => {
    expect(parseClaudeStreamLine(`{"type":"system","subtype":"init","session_id":"abc"}`)).toEqual({ type: "sessionStarted", sessionID: "abc" });
  });

  it("joins an assistant message's text blocks and skips tool use", () => {
    const line = `{"type":"assistant","message":{"content":[{"type":"text","text":"Hel"},{"type":"tool_use","name":"x"},{"type":"text","text":"lo"}]}}`;
    expect(parseClaudeStreamLine(line)).toEqual({ type: "assistantText", text: "Hello" });
  });

  it("reads a text delta", () => {
    const line = `{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}`;
    expect(parseClaudeStreamLine(line)).toEqual({ type: "textDelta", text: "Hi" });
  });

  it("reads success and error results", () => {
    expect(parseClaudeStreamLine(`{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s1"}`)).toEqual({
      type: "result",
      result: { text: "ok", sessionID: "s1", isError: false },
    });
    expect(parseClaudeStreamLine(`{"type":"result","subtype":"error_max_turns","session_id":"s1"}`)).toEqual({
      type: "result",
      result: { sessionID: "s1", isError: true },
    });
  });

  it("reads garbage as other", () => {
    expect(parseClaudeStreamLine("not json")).toEqual({ type: "other" });
    expect(parseClaudeStreamLine(`{"no":"type"}`)).toEqual({ type: "other" });
    expect(parseClaudeStreamLine(`{"type":"user"}`)).toEqual({ type: "other" });
  });

  it("parses every line in order", () => {
    expect(claudeEvents([`{"type":"system","subtype":"init","session_id":"s"}`, "noise"]).map((e) => e.type)).toEqual(["sessionStarted", "other"]);
  });
});

describe("ClaudeCLI arguments", () => {
  it("puts the prompt last, after a double dash, verbatim", () => {
    expect(claudePromptArguments("--help me", ["--model", "sonnet"])).toEqual([
      "-p",
      "--output-format",
      "stream-json",
      "--verbose",
      "--model",
      "sonnet",
      "--",
      "--help me",
    ]);
  });

  it("sends no prompt argument when the input goes on stdin", () => {
    const args = claudeInputArguments(["--resume", "s1"]);
    expect(args).toEqual(["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--resume", "s1"]);
    expect(args).not.toContain("--");
  });

  it("writes one user message with images before the text", () => {
    const line = claudeInputLine("What is this?", [new Uint8Array([0x89, 0x50]), new Uint8Array([9])]);
    expect(line.endsWith("\n")).toBe(true);
    expect(line.split("\n")).toHaveLength(2);
    const json = JSON.parse(line) as { type: string; message: { role: string; content: { type: string; source?: Record<string, string>; text?: string }[] } };
    expect(json.type).toBe("user");
    expect(json.message.role).toBe("user");
    expect(json.message.content.map((block) => block.type)).toEqual(["image", "image", "text"]);
    expect(json.message.content[0]?.source).toEqual({ type: "base64", media_type: "image/png", data: "iVA=" });
    expect(json.message.content[2]?.text).toBe("What is this?");
    expect(claudeInputLine("hi")).toBe(`{"message":{"content":[{"text":"hi","type":"text"}],"role":"user"},"type":"user"}\n`);
  });

  it("looks for claude.exe where Windows installs put it", () => {
    expect(
      claudeExecutableCandidates({
        userPath: " D:\\tools\\claude.exe ",
        home: "C:\\Users\\ana",
        pathFolders: ["C:\\Windows\\System32\\", "", "C:\\Users\\ana\\AppData\\Roaming\\npm"],
      }),
    ).toEqual([
      "D:\\tools\\claude.exe",
      "C:\\Users\\ana\\.local\\bin\\claude.exe",
      "C:\\Windows\\System32\\claude.exe",
      "C:\\Windows\\System32\\claude.cmd",
      "C:\\Users\\ana\\AppData\\Roaming\\npm\\claude.exe",
      "C:\\Users\\ana\\AppData\\Roaming\\npm\\claude.cmd",
    ]);
  });
});
