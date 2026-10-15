import { describe, expect, it } from "vitest";
import { InMemoryAIKeyStore, credentialTarget, hasKey } from "../../../src/core/ai/aiKeyStore";
import { AIHTTPProvider, type AIHTTPResponse, type AIHTTPTransport, answer } from "../../../src/core/ai/aiProvider";
import { AIProviderFactory, resolveSetupState } from "../../../src/core/ai/aiProviderFactory";
import {
  AI_PROVIDER_IDS,
  allAINetworkAccess,
  availableProviders,
  consentMessage,
  consentTitle,
  defaultModel,
  isCommandLineTool,
  isLocalHost,
  networkAccess,
  parseAIProviderID,
  requiresAPIKey,
  sendsDataOffDevice,
  setupHint,
  setupPage,
  setupPageTitle,
  vendorName,
  aiTransport,
} from "../../../src/core/ai/aiProviderID";
import {
  type AIProviderError,
  AIProviderFailure,
  type AIRequest,
  type AIStreamEvent,
  aiRequest,
  assistantMessage,
  promptRequest,
  providerErrorMessage,
  resolvedModel,
  userMessage,
} from "../../../src/core/ai/aiRequest";
import {
  activeProvider,
  aiSettings,
  choose,
  decodeAISettings,
  encodeAISettings,
  modelFor,
  needsConsent,
  setModel,
} from "../../../src/core/ai/aiSettings";
import { LineSplitter, parseStream, splitLines } from "../../../src/core/ai/aiStream";
import { type AIHTTPRequest, base64, errorFromResponse, eventsFromLine, httpRequest, sortedJSON } from "../../../src/core/ai/aiWireFormat";

/* Port of AIProviderTests and AISettingsTests (the API providers and Ollama). */

function failureOf(run: () => unknown): AIProviderError {
  try {
    run();
  } catch (error) {
    if (error instanceof AIProviderFailure) return error.error;
    throw error;
  }
  throw new Error("Expected an AI provider error");
}

async function asyncFailureOf(promise: Promise<unknown>): Promise<AIProviderError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof AIProviderFailure) return error.error;
    throw error;
  }
  throw new Error("Expected an AI provider error");
}

describe("AIProviderID", () => {
  it("offers only the APIs and Ollama in a sandbox", () => {
    expect(availableProviders(true)).toEqual(["anthropic", "openai", "gemini", "ollama"]);
    expect(availableProviders(false)).toEqual([...AI_PROVIDER_IDS]);
  });

  it("lists every HTTP provider's host", () => {
    for (const id of AI_PROVIDER_IDS) expect(networkAccess(id) === undefined, id).toBe(isCommandLineTool(id));
    expect(new Set(allAINetworkAccess().map((access) => access.host))).toEqual(
      new Set(["api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com", "localhost"]),
    );
    const ollama = networkAccess("ollama");
    expect(ollama && isLocalHost(ollama)).toBe(true);
  });

  it("names who gets the data for every provider that leaves the PC", () => {
    for (const id of AI_PROVIDER_IDS) {
      expect(vendorName(id) === undefined, id).toBe(id === "ollama");
      const vendor = vendorName(id);
      if (vendor) expect(consentMessage(id, "Tabbi")).toContain(vendor);
    }
    expect(vendorName("claude-cli")).toBe(vendorName("anthropic"));
    expect(vendorName("gemini-cli")).toBe("Google");
  });

  it("needs a key only for the hosted APIs, which have default models", () => {
    expect(AI_PROVIDER_IDS.filter(requiresAPIKey)).toEqual(["anthropic", "openai", "gemini"]);
    for (const id of AI_PROVIDER_IDS.filter((id) => !isCommandLineTool(id))) expect(defaultModel(id)).not.toBe("");
  });

  it("keeps the Mac's model ids and raw values", () => {
    expect(defaultModel("anthropic")).toBe("claude-sonnet-5-5");
    expect(defaultModel("openai")).toBe("gpt-5-mini");
    expect(defaultModel("gemini")).toBe("gemini-flash-latest");
    expect(defaultModel("ollama")).toBe("llama3.2");
    expect(defaultModel("claude-cli")).toBe("sonnet");
    expect(aiTransport("claude-cli")).toEqual({ kind: "cli", executable: "claude" });
    expect(parseAIProviderID("openai")).toBe("openai");
    expect(parseAIProviderID("someday-ai")).toBeUndefined();
  });

  it("falls back to the default model", () => {
    expect(resolvedModel(promptRequest("hi"), "gemini")).toBe("gemini-flash-latest");
    expect(resolvedModel(promptRequest("hi", "  "), "ollama")).toBe("llama3.2");
    expect(resolvedModel(promptRequest("hi", "qwen3"), "ollama")).toBe("qwen3");
  });

  it("names the provider in error messages", () => {
    expect(providerErrorMessage({ kind: "missingAPIKey" }, "gemini")).toBe("Add your Gemini API key in Settings.");
    expect(providerErrorMessage({ kind: "unreachable" }, "ollama")).toBe("Ollama is not running. Open Ollama and try again.");
    expect(providerErrorMessage({ kind: "unreachable" }, "openai")).toBe("Could not reach OpenAI API. Check your connection.");
    expect(providerErrorMessage({ kind: "invalidAPIKey" }, "anthropic")).toBe("Claude API did not accept the key. Check it in Settings.");
    expect(providerErrorMessage({ kind: "rateLimited", detail: "Overloaded" }, "anthropic")).toBe("Claude API is busy: Overloaded");
    expect(providerErrorMessage({ kind: "rateLimited" }, "gemini")).toBe("Gemini API is out of quota for now. Try again in a minute.");
    expect(providerErrorMessage({ kind: "service", detail: "Bad model" }, "gemini")).toBe("Bad model");
    expect(providerErrorMessage({ kind: "notInstalled" }, "codex-cli")).toBe("Codex CLI is not installed.");
  });
});

describe("AIWireFormat", () => {
  const png = new Uint8Array([0x89, 0x50]);
  const chat: AIRequest = aiRequest({
    system: "Be brief.",
    messages: [userMessage("What is this?", [png]), assistantMessage("A chart."), userMessage("Thanks")],
    model: "m",
    maxTokens: 100,
  });
  const body = (request: AIHTTPRequest) => JSON.parse(request.body) as Record<string, unknown>;

  it("refuses to build a hosted request without a key", () => {
    for (const id of ["anthropic", "openai", "gemini"] as const) {
      expect(failureOf(() => httpRequest(id, chat, " "))).toEqual({ kind: "missingAPIKey" });
    }
    expect(() => httpRequest("ollama", chat, undefined)).not.toThrow();
  });

  it("builds the Anthropic request", () => {
    const request = httpRequest("anthropic", chat, "sk-ant");
    expect(request.url).toBe("https://api.anthropic.com/v1/messages");
    expect(request.method).toBe("POST");
    expect(request.headers["x-api-key"]).toBe("sk-ant");
    expect(request.headers["anthropic-version"]).toBe("2023-06-01");
    expect(request.headers["content-type"]).toBe("application/json");
    expect(request.timeoutSeconds).toBe(120);
    const json = body(request);
    expect(json.model).toBe("m");
    expect(json.system).toBe("Be brief.");
    expect(json.stream).toBe(true);
    expect(json.max_tokens).toBe(100);
    const messages = json.messages as { role: string; content: { type: string; source?: { data: string } }[] }[];
    expect(messages.map((m) => m.role)).toEqual(["user", "assistant", "user"]);
    expect(messages[0]?.content.map((c) => c.type)).toEqual(["image", "text"]);
    expect(messages[0]?.content[0]?.source?.data).toBe(base64(png));
    expect(base64(png)).toBe("iVA=");
  });

  it("writes the body with sorted keys, as the Mac does", () => {
    const request = httpRequest("anthropic", promptRequest("Hi"), "k");
    expect(request.body).toBe(
      `{"max_tokens":4096,"messages":[{"content":[{"text":"Hi","type":"text"}],"role":"user"}],"model":"claude-sonnet-5-5","stream":true}`,
    );
    expect(sortedJSON({ b: 1, a: [{ d: "x/y", c: null }] })).toBe(`{"a":[{"c":null,"d":"x/y"}],"b":1}`);
  });

  it("builds the OpenAI request", () => {
    const request = httpRequest("openai", chat, "sk-o");
    expect(request.url).toBe("https://api.openai.com/v1/chat/completions");
    expect(request.headers.authorization).toBe("Bearer sk-o");
    const messages = body(request).messages as { role: string; content: unknown }[];
    expect(messages.map((m) => m.role)).toEqual(["system", "user", "assistant", "user"]);
    const parts = messages[1]?.content as { image_url?: { url: string } }[];
    expect(parts[1]?.image_url?.url).toBe(`data:image/png;base64,${base64(png)}`);
    expect(messages[3]?.content).toBe("Thanks");
  });

  it("builds the Gemini request with the key in a header, never the URL", () => {
    const request = httpRequest("gemini", promptRequest("Hi"), "AIza");
    expect(request.url).toBe("https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse");
    expect(request.headers["x-goog-api-key"]).toBe("AIza");
    expect(request.url).not.toContain("key=");
    const chatBody = body(httpRequest("gemini", chat, "AIza"));
    expect((chatBody.contents as { role: string }[]).map((c) => c.role)).toEqual(["user", "model", "user"]);
    expect(chatBody.system_instruction).toBeDefined();
    expect(httpRequest("gemini", promptRequest("Hi", "my model"), "AIza").url).toContain("/models/my%20model:streamGenerateContent");
  });

  it("sends Ollama to localhost or the given address", () => {
    const request = httpRequest("ollama", chat, undefined);
    expect(request.url).toBe("http://localhost:11434/api/chat");
    expect(request.headers.authorization).toBeUndefined();
    const messages = body(request).messages as { images?: string[] }[];
    expect(messages[1]?.images).toEqual([base64(png)]);
    expect(httpRequest("ollama", chat, undefined, "http://127.0.0.1:9999").url).toBe("http://127.0.0.1:9999/api/chat");
  });

  it("reads the Anthropic stream", () => {
    const lines = [
      "event: message_start",
      `data: {"type":"message_start","message":{"id":"m"}}`,
      "",
      `data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}`,
      `data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}`,
      `data: {"type":"ping"}`,
      `data: {"type":"message_stop"}`,
    ];
    expect(lines.flatMap((line) => eventsFromLine(line, "anthropic"))).toEqual([
      { kind: "textDelta", text: "Hel" },
      { kind: "textDelta", text: "lo" },
      { kind: "finished" },
    ]);
    expect(
      failureOf(() => eventsFromLine(`data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`, "anthropic")),
    ).toEqual({ kind: "rateLimited", detail: "Overloaded" });
  });

  it("reads the OpenAI stream", () => {
    const lines = [
      `data: {"choices":[{"delta":{"role":"assistant","content":""}}]}`,
      `data: {"choices":[{"delta":{"content":"Hi"}}]}`,
      `data: {"choices":[{"delta":{},"finish_reason":"stop"}]}`,
      "data: [DONE]",
    ];
    expect(lines.flatMap((line) => eventsFromLine(line, "openai"))).toEqual([{ kind: "textDelta", text: "Hi" }, { kind: "finished" }]);
  });

  it("skips Gemini's thoughts", () => {
    const line = `data: {"candidates":[{"content":{"role":"model","parts":[{"text":"hmm","thought":true},{"text":"Answer"}]}}]}`;
    expect(eventsFromLine(line, "gemini")).toEqual([{ kind: "textDelta", text: "Answer" }]);
  });

  it("reads the Ollama stream", () => {
    expect(eventsFromLine(`{"message":{"role":"assistant","content":"Yo"},"done":false}`, "ollama")).toEqual([{ kind: "textDelta", text: "Yo" }]);
    expect(eventsFromLine(`{"message":{"role":"assistant","content":""},"done":true}`, "ollama")).toEqual([{ kind: "finished" }]);
    expect(failureOf(() => eventsFromLine(`{"error":"model \\"x\\" not found"}`, "ollama"))).toEqual({
      kind: "service",
      detail: `model "x" not found`,
    });
  });

  it("gives reasoning models room to think before the answer", () => {
    const limit = (provider: "openai" | "gemini", model: string) => {
      const json = body(httpRequest(provider, aiRequest({ messages: [userMessage("Hi")], model, maxTokens: 100 }), "k"));
      return provider === "gemini" ? (json.generationConfig as { maxOutputTokens: number }).maxOutputTokens : json.max_completion_tokens;
    };
    expect(limit("openai", "gpt-5-mini")).toBe(8292);
    expect(limit("openai", "o4-mini")).toBe(8292);
    expect(limit("openai", "gpt-4o")).toBe(100);
    expect(limit("gemini", "")).toBe(8292);
    expect(limit("gemini", "gemini-2.0-flash")).toBe(100);
    expect(limit("gemini", "gemma-3-27b-it")).toBe(100);
    expect(body(httpRequest("anthropic", chat, "k")).max_tokens).toBe(100);
  });

  it("treats an answer cut off by the token limit as an error", () => {
    const lines: [Parameters<typeof eventsFromLine>[1], string][] = [
      ["anthropic", `data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}`],
      ["openai", `data: {"choices":[{"delta":{},"finish_reason":"length"}]}`],
      ["gemini", `data: {"candidates":[{"content":{"parts":[{"text":"x"}]},"finishReason":"MAX_TOKENS"}]}`],
      ["ollama", `{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length"}`],
    ];
    for (const [provider, line] of lines) expect(failureOf(() => eventsFromLine(line, provider))).toEqual({ kind: "cutOff" });
    expect(eventsFromLine(`data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}`, "anthropic")).toEqual([]);
    expect(providerErrorMessage({ kind: "cutOff" }, "openai")).toBe("OpenAI API stopped before the answer was complete. Try a shorter question.");
  });

  it("maps HTTP status errors", () => {
    const text = `{"error":{"message":"Quota exceeded"}}`;
    expect(errorFromResponse(401, text)).toEqual({ kind: "invalidAPIKey" });
    expect(errorFromResponse(429, text)).toEqual({ kind: "rateLimited", detail: "Quota exceeded" });
    expect(errorFromResponse(500, text)).toEqual({ kind: "service", detail: "Quota exceeded" });
    expect(errorFromResponse(502, "")).toEqual({ kind: "service", detail: "The request failed (HTTP 502)." });
  });
});

describe("streaming parsers over text chunks", () => {
  it("splits lines across chunk boundaries and line endings", () => {
    expect(splitLines(["da", "ta: a\r", "\nb\n\nc"])).toEqual(["data: a", "b", "", "c"]);
    expect(splitLines(["x\ry\r\n"])).toEqual(["x", "y"]);
    const splitter = new LineSplitter();
    expect(splitter.push("{\"a\":")).toEqual([]);
    expect(splitter.push("1}\n{")).toEqual([`{"a":1}`]);
    expect(splitter.finish()).toEqual(["{"]);
  });

  it("parses SSE whose events are split mid-line", () => {
    const body = `data: {"choices":[{"delta":{"content":"Hel"}}]}\n\ndata: {"choices":[{"delta":{"content":"lo"}}]}\n\ndata: [DONE]\n\n`;
    const chunks = body.match(/.{1,7}/gs) ?? [];
    expect(parseStream("openai", chunks)).toEqual([{ kind: "textDelta", text: "Hel" }, { kind: "textDelta", text: "lo" }, { kind: "finished" }]);
  });

  it("parses NDJSON with a final line that has no newline", () => {
    const chunks = [`{"message":{"content":"Pl`, `an "},"done":false}\n{"message":{"content":"ready"},"done":true}`];
    expect(parseStream("ollama", chunks)).toEqual([
      { kind: "textDelta", text: "Plan " },
      { kind: "textDelta", text: "ready" },
      { kind: "finished" },
    ]);
  });

  it("keeps multibyte text that arrives in pieces", () => {
    const chunks = [`data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"caf`, `\u00E9 \u2192 \u65E5"}}\n`];
    expect(parseStream("anthropic", chunks)).toEqual([{ kind: "textDelta", text: "caf\u00E9 \u2192 \u65E5" }]);
  });
});

async function* chunksOf(chunks: readonly string[]): AsyncGenerator<string> {
  for (const chunk of chunks) yield chunk;
}

function replay(status: number, chunks: readonly string[], seen?: AIHTTPRequest[]): AIHTTPTransport {
  return async (request) => {
    seen?.push(request);
    return { status, chunks: chunksOf(chunks) };
  };
}

async function collect(stream: AsyncIterable<AIStreamEvent>): Promise<AIStreamEvent[]> {
  const events: AIStreamEvent[] = [];
  for await (const event of stream) events.push(event);
  return events;
}

describe("AIHTTPProvider", () => {
  it("streams deltas and finishes once", async () => {
    const seen: AIHTTPRequest[] = [];
    const provider = new AIHTTPProvider(
      "openai",
      "k",
      replay(200, [`data: {"choices":[{"delta":{"content":"A"}}]}\n`, `data: {"choices":[{"delta":{"content":"B"}}]}\n`, "data: [DONE]\n"], seen),
    );
    expect(await collect(provider.stream(promptRequest("q")))).toEqual([
      { kind: "textDelta", text: "A" },
      { kind: "textDelta", text: "B" },
      { kind: "finished" },
    ]);
    expect(new URL(seen[0]?.url ?? "").host).toBe("api.openai.com");
  });

  it("joins the deltas into an answer", async () => {
    const provider = new AIHTTPProvider("ollama", undefined, replay(200, [`{"message":{"content":"Plan "},"done":false}\n`, `{"message":{"content":"ready"},"done":true}\n`]));
    expect(await answer(provider, promptRequest("plan my day"))).toBe("Plan ready");
  });

  it("turns an HTTP error into a provider error", async () => {
    const provider = new AIHTTPProvider("gemini", "bad", replay(403, [`{"error":{"code":403,"message":"API key not valid"}}`]));
    expect(await asyncFailureOf(answer(provider, promptRequest("q")))).toEqual({ kind: "invalidAPIKey" });
  });

  it("fails a missing key without any request", async () => {
    const seen: AIHTTPRequest[] = [];
    const provider = new AIHTTPProvider("anthropic", undefined, replay(200, [], seen));
    expect(await asyncFailureOf(answer(provider, promptRequest("q")))).toEqual({ kind: "missingAPIKey" });
    expect(seen).toEqual([]);
  });

  it("reads a connection failure as unreachable", async () => {
    const provider = new AIHTTPProvider("ollama", undefined, async () => {
      throw new Error("connection refused");
    });
    expect(await asyncFailureOf(answer(provider, promptRequest("q")))).toEqual({ kind: "unreachable", detail: "connection refused" });
  });

  it("times out an answer that never comes", async () => {
    const never: AIHTTPResponse = { status: 200, chunks: { [Symbol.asyncIterator]: () => ({ next: () => new Promise(() => undefined) }) } };
    const provider = new AIHTTPProvider("ollama", undefined, async () => never);
    expect(await asyncFailureOf(answer(provider, promptRequest("q"), AbortSignal.timeout(50)))).toEqual({
      kind: "unreachable",
      detail: "timed out",
    });
  });

  it("lets the user stop a request", async () => {
    const controller = new AbortController();
    const provider = new AIHTTPProvider("ollama", undefined, async () => {
      controller.abort();
      throw new Error("aborted by the host");
    });
    const error = await answer(provider, promptRequest("q"), controller.signal).catch((e: unknown) => e);
    expect(error).not.toBeInstanceOf(AIProviderFailure);
    expect(error).toMatchObject({ name: "AbortError" });
  });
});

describe("AISettings", () => {
  it("activates nothing until the user picks", () => {
    expect(activeProvider(aiSettings(), false)).toBeUndefined();
    expect(activeProvider(aiSettings({ provider: "gemini", consented: ["gemini"] }), true)).toBe("gemini");
  });

  it("waits for permission before sending data off the PC", () => {
    let settings = aiSettings({ provider: "anthropic" });
    expect(needsConsent(settings, "anthropic")).toBe(true);
    expect(activeProvider(settings, false)).toBeUndefined();
    settings = choose(settings, "anthropic");
    expect(activeProvider(settings, false)).toBe("anthropic");
    expect(needsConsent(settings, "anthropic")).toBe(false);
    settings = choose(choose(settings, undefined), "anthropic");
    expect(activeProvider(settings, false)).toBe("anthropic");
    expect(needsConsent(settings, "openai")).toBe(true);
  });

  it("needs no permission for Ollama", () => {
    const settings = aiSettings({ provider: "ollama" });
    expect(needsConsent(settings, "ollama")).toBe(false);
    expect(activeProvider(settings, true)).toBe("ollama");
    expect(choose(aiSettings(), "ollama").consented.size).toBe(0);
    expect(sendsDataOffDevice("ollama")).toBe(false);
  });

  it("names the receiver and what is sent in the disclosure", () => {
    for (const id of AI_PROVIDER_IDS.filter(sendsDataOffDevice)) {
      const vendor = vendorName(id);
      if (!vendor) throw new Error(`${id} names no receiver`);
      expect(consentTitle(id)).toContain(vendor);
      const message = consentMessage(id, "Tabbi");
      for (const detail of ["Tabbi", vendor, "questions", "screenshot", "calendar event titles", "study minutes", "terms and privacy policy", "None"]) {
        expect(message, `${id}: ${detail}`).toContain(detail);
      }
    }
    expect(consentTitle("anthropic")).toBe("Send your AI requests to Anthropic?");
  });

  it("keeps the sandbox from running a command line tool", () => {
    const settings = aiSettings({ provider: "claude-cli", consented: ["claude-cli"] });
    expect(activeProvider(settings, false)).toBe("claude-cli");
    expect(activeProvider(settings, true)).toBeUndefined();
  });

  it("falls back to default models and does not store defaults", () => {
    let settings = aiSettings();
    expect(modelFor(settings, "ollama")).toBe("llama3.2");
    settings = setModel(settings, "  qwen3 ", "ollama");
    expect(modelFor(settings, "ollama")).toBe("qwen3");
    settings = setModel(settings, "llama3.2", "ollama");
    expect(settings.models).toEqual({});
    settings = setModel(setModel(settings, "gpt-5", "openai"), " ", "openai");
    expect(settings.models).toEqual({});
  });

  it("round-trips its stored form and drops unknown providers", () => {
    const settings = setModel(choose(aiSettings({ consented: ["gemini"] }), "openai"), "gpt-5", "openai");
    expect(decodeAISettings(encodeAISettings(settings))).toEqual(settings);
    expect(encodeAISettings(settings).consented).toEqual(["gemini", "openai"]);
    const lenient = decodeAISettings({ provider: "someday-ai", models: { "someday-ai": "x", ollama: "qwen3" }, consented: ["gemini", "someday-ai"] });
    expect(lenient.provider).toBeUndefined();
    expect(lenient.models).toEqual({ ollama: "qwen3" });
    expect([...lenient.consented]).toEqual(["gemini"]);
    expect(decodeAISettings(undefined)).toEqual(aiSettings());
  });

  it("points setup pages at official HTTPS pages", () => {
    expect(new URL(setupPage("gemini")).host).toBe("aistudio.google.com");
    expect(new URL(setupPage("ollama")).host).toBe("ollama.com");
    for (const id of AI_PROVIDER_IDS) {
      expect(new URL(setupPage(id)).protocol).toBe("https:");
      expect(setupPageTitle(id)).toBe(requiresAPIKey(id) ? "Get a Key" : "Install");
    }
  });

  it("has setup hints for every provider without a key", () => {
    const found = { kind: "found", path: "C:\\Users\\ana\\.local\\bin\\tool.exe" } as const;
    for (const id of AI_PROVIDER_IDS) {
      expect(setupHint(id, "m", { kind: "missing" }) === undefined, id).toBe(requiresAPIKey(id));
      expect(setupHint(id, "m", found) === undefined, id).toBe(requiresAPIKey(id));
    }
    expect(setupHint("ollama", modelFor(aiSettings(), "ollama"), { kind: "looking" })).toBe("With Ollama open, run ollama pull llama3.2 in Terminal once.");
  });

  it("never asks to run a command line tool by its bare name", () => {
    for (const id of ["claude-cli", "codex-cli", "gemini-cli"] as const) {
      const transport = aiTransport(id);
      if (transport.kind !== "cli") throw new Error(id);
      expect(setupHint(id, "", { kind: "looking" })).toBeUndefined();
      const missing = setupHint(id, "", { kind: "missing" }) ?? "";
      expect(missing.includes(`run ${transport.executable}`) || missing.includes(`Run ${transport.executable}`)).toBe(false);
      expect(missing).not.toContain("Terminal");
    }
    expect(setupHint("claude-cli", "", { kind: "missing" })).toBe("To install it, click Show me how on the Claude row below.");
    expect(setupHint("codex-cli", "", { kind: "missing" })).toBe("Click Install for the official steps, then come back here.");
    expect(setupHint("codex-cli", "", { kind: "found", path: "C:\\Users\\Ana Lee\\AppData\\Roaming\\npm\\codex.cmd" })).toBe(
      "To sign in, run 'C:\\Users\\Ana Lee\\AppData\\Roaming\\npm\\codex.cmd' login in Terminal once.",
    );
    expect(setupHint("gemini-cli", "", { kind: "found", path: "/opt/homebrew/bin/gemini" })).toBe(
      "To sign in with Google, run /opt/homebrew/bin/gemini in Terminal once.",
    );
    expect(setupHint("claude-cli", "", { kind: "found", path: "/Users/ana/.local/bin/claude" })).toBe(
      "The Claude row below shows how to sign in, if you still need to.",
    );
  });

  it("trims keys in memory and deletes a blank one", async () => {
    const keys = new InMemoryAIKeyStore({ openai: "  sk-1\n" });
    expect(await keys.key("openai")).toBe("sk-1");
    await keys.setKey("   ", "openai");
    expect(await hasKey(keys, "openai")).toBe(false);
    expect(credentialTarget("anthropic")).toBe("Tabbi/ai/anthropic");
  });
});

describe("AIProviderFactory", () => {
  function factory(keys = new InMemoryAIKeyStore(), sandboxed = false, seen: AIHTTPRequest[] = []) {
    return new AIProviderFactory({ keys, sandboxed, transport: replay(200, [], seen) });
  }

  it("follows the choice and the key in its setup state", async () => {
    const keys = new InMemoryAIKeyStore();
    const f = factory(keys);
    expect(await f.setupState(aiSettings())).toEqual({ kind: "notChosen" });
    const anthropic = aiSettings({ provider: "anthropic", consented: ["anthropic"] });
    expect(await f.setupState(anthropic)).toEqual({ kind: "needsKey", provider: "anthropic" });
    await keys.setKey("sk-ant", "anthropic");
    expect(await f.setupState(anthropic)).toEqual({ kind: "ready", provider: "anthropic" });
    expect(await f.setupState(aiSettings({ provider: "ollama" }))).toEqual({ kind: "ready", provider: "ollama" });
    expect(await f.setupState(aiSettings({ provider: "codex-cli", consented: ["codex-cli"] }))).toEqual({ kind: "ready", provider: "codex-cli" });
    expect(resolveSetupState(undefined, false)).toEqual({ kind: "notChosen" });
  });

  it("offers no CLI in a sandboxed build and runs none", async () => {
    const f = factory(undefined, true);
    expect(f.availableProviders).toEqual(["anthropic", "openai", "gemini", "ollama"]);
    const cli = aiSettings({ provider: "claude-cli", consented: ["claude-cli"] });
    expect(await f.setupState(cli)).toEqual({ kind: "notChosen" });
    expect(await f.provider(cli)).toBeUndefined();
  });

  it("sends nothing when no provider is picked", async () => {
    expect(await factory().provider(aiSettings())).toBeUndefined();
  });

  it("sends the saved key and the user's model", async () => {
    const seen: AIHTTPRequest[] = [];
    const settings = setModel(aiSettings({ provider: "anthropic", consented: ["anthropic"] }), "claude-haiku-4-5", "anthropic");
    const provider = await factory(new InMemoryAIKeyStore({ anthropic: "sk-ant" }), false, seen).provider(settings);
    if (!provider) throw new Error("no provider");
    expect(provider.id).toBe("anthropic");
    await answer(provider, promptRequest("Hi"));
    await answer(provider, promptRequest("Hi", "claude-opus-5-5"));
    expect(seen[0]?.headers["x-api-key"]).toBe("sk-ant");
    expect(JSON.parse(seen[0]?.body ?? "{}").model).toBe("claude-haiku-4-5");
    expect(JSON.parse(seen[1]?.body ?? "{}").model).toBe("claude-opus-5-5");
  });

  it("fails a missing key with a setup error", async () => {
    const provider = await factory().provider(aiSettings({ provider: "gemini", consented: ["gemini"] }));
    if (!provider) throw new Error("no provider");
    expect(await asyncFailureOf(answer(provider, promptRequest("Hi")))).toEqual({ kind: "missingAPIKey" });
  });

  it("sends Ollama to localhost with the default model", async () => {
    const seen: AIHTTPRequest[] = [];
    const provider = await factory(undefined, false, seen).provider(aiSettings({ provider: "ollama" }));
    if (!provider) throw new Error("no provider");
    await answer(provider, promptRequest("Hi"));
    expect(new URL(seen[0]?.url ?? "").hostname).toBe("localhost");
    expect(JSON.parse(seen[0]?.body ?? "{}").model).toBe("llama3.2");
  });

  it("reports a command line tool this build can't run as not installed", async () => {
    const provider = await factory().provider(aiSettings({ provider: "codex-cli", consented: ["codex-cli"] }));
    if (!provider) throw new Error("no provider");
    expect(await asyncFailureOf(answer(provider, promptRequest("Hi")))).toEqual({ kind: "notInstalled" });
  });
});
