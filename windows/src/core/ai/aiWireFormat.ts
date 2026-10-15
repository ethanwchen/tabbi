import { type AIProviderID, requiresAPIKey } from "./aiProviderID";
import {
  type AIProviderError,
  AIProviderFailure,
  type AIRequest,
  type AIStreamEvent,
  resolvedModel,
} from "./aiRequest";

/*
 * Port of AIWireFormat: the HTTP requests and streaming responses of the
 * hosted APIs and Ollama, kept pure so every byte Tabbi sends and every
 * event it reads is tested without a network. Endpoints, headers, model
 * ids and body fields are the Mac's, byte for byte.
 *
 * Anthropic, OpenAI and Gemini stream server-sent events whose `data:` lines
 * each hold one JSON object; Ollama streams one JSON object per line.
 */

export const ANTHROPIC_VERSION = "2023-06-01";
/** Where Ollama listens unless the user changed it. */
export const OLLAMA_BASE_URL = "http://localhost:11434";

/** One streaming POST for the host to make. Header names are lowercase. */
export interface AIHTTPRequest {
  url: string;
  method: "POST";
  headers: Record<string, string>;
  /** The JSON body, keys sorted, slashes unescaped (as the Mac writes it). */
  body: string;
  timeoutSeconds: number;
}

const IMAGE_MEDIA_TYPE = "image/png";

type Json = string | number | boolean | null | Json[] | { [key: string]: Json };

/** JSON text with every object's keys sorted, like `JSONSerialization` with `.sortedKeys`. */
export function sortedJSON(value: Json): string {
  if (Array.isArray(value)) return `[${value.map(sortedJSON).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${sortedJSON(value[key] ?? null)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

/** Standard base64 of bytes, with no dependency on Node's Buffer. */
export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
  }
  return btoa(binary);
}

const pathAllowed = /[A-Za-z0-9!$&'()*+,\-./:;=@_~]/;

/** Percent-encodes a path segment the way Foundation's `.urlPathAllowed` does. */
function encodePath(text: string): string {
  let out = "";
  for (const char of text) {
    if (pathAllowed.test(char)) {
      out += char;
    } else {
      for (const byte of new TextEncoder().encode(char)) out += "%" + byte.toString(16).toUpperCase().padStart(2, "0");
    }
  }
  return out;
}

/**
 * The streaming request for `request` to an HTTP provider. `apiKey` is
 * required for the hosted APIs; `baseURL` overrides Ollama's address.
 * Throws `missingAPIKey` before anything is built when a key is needed.
 */
export function httpRequest(provider: AIProviderID, request: AIRequest, apiKey: string | undefined, baseURL?: string): AIHTTPRequest {
  const model = resolvedModel(request, provider);
  const key = apiKey?.trim() ?? "";
  if (requiresAPIKey(provider) && key.length === 0) throw new AIProviderFailure({ kind: "missingAPIKey" });

  const headers: Record<string, string> = { "content-type": "application/json" };
  let url: string;
  let body: Json;
  switch (provider) {
    case "anthropic":
      url = "https://api.anthropic.com/v1/messages";
      headers["x-api-key"] = key;
      headers["anthropic-version"] = ANTHROPIC_VERSION;
      body = anthropicBody(request, model);
      break;
    case "openai":
      url = "https://api.openai.com/v1/chat/completions";
      headers.authorization = `Bearer ${key}`;
      body = openAIBody(request, model);
      break;
    case "gemini":
      url = `https://generativelanguage.googleapis.com/v1beta/models/${encodePath(model)}:streamGenerateContent?alt=sse`;
      headers["x-goog-api-key"] = key;
      body = geminiBody(request);
      break;
    case "ollama":
      url = `${(baseURL ?? OLLAMA_BASE_URL).replace(/\/+$/, "")}/api/chat`;
      body = ollamaBody(request, model);
      break;
    case "claude-cli":
    case "codex-cli":
    case "gemini-cli":
      throw new Error(`${provider} is a command line tool, not an HTTP provider`);
  }
  return { url, method: "POST", headers, body: sortedJSON(body), timeoutSeconds: 120 };
}

function anthropicBody(request: AIRequest, model: string): Json {
  const body: { [key: string]: Json } = {
    model,
    max_tokens: request.maxTokens,
    stream: true,
    messages: request.messages.map((message) => ({
      role: message.role,
      content: [
        ...message.images.map((image) => ({
          type: "image",
          source: { type: "base64", media_type: IMAGE_MEDIA_TYPE, data: base64(image) },
        })),
        { type: "text", text: message.text },
      ],
    })),
  };
  if (request.system !== undefined) body.system = request.system;
  return body;
}

function openAIBody(request: AIRequest, model: string): Json {
  const system: Json[] = request.system === undefined ? [] : [{ role: "system", content: request.system }];
  const messages: Json[] = request.messages.map((message) => {
    if (message.images.length === 0) return { role: message.role, content: message.text };
    return {
      role: message.role,
      content: [
        { type: "text", text: message.text },
        ...message.images.map((image) => ({
          type: "image_url",
          image_url: { url: `data:${IMAGE_MEDIA_TYPE};base64,${base64(image)}` },
        })),
      ],
    };
  });
  return {
    model,
    stream: true,
    max_completion_tokens: request.maxTokens + reasoningHeadroom("openai", model),
    messages: [...system, ...messages],
  };
}

function geminiBody(request: AIRequest): Json {
  const model = resolvedModel(request, "gemini");
  const body: { [key: string]: Json } = {
    contents: request.messages.map((message) => ({
      /* Gemini calls the assistant "model". */
      role: message.role === "user" ? "user" : "model",
      parts: [
        ...message.images.map((image) => ({ inline_data: { mime_type: IMAGE_MEDIA_TYPE, data: base64(image) } })),
        { text: message.text },
      ],
    })),
    generationConfig: { maxOutputTokens: request.maxTokens + reasoningHeadroom("gemini", model) },
  };
  if (request.system !== undefined) body.system_instruction = { parts: [{ text: request.system }] };
  return body;
}

function ollamaBody(request: AIRequest, model: string): Json {
  const system: Json[] = request.system === undefined ? [] : [{ role: "system", content: request.system }];
  const messages: Json[] = request.messages.map((message) => {
    const entry: { [key: string]: Json } = { role: message.role, content: message.text };
    if (message.images.length > 0) entry.images = message.images.map(base64);
    return entry;
  });
  return { model, stream: true, messages: [...system, ...messages] };
}

/**
 * Extra output tokens for a model that reasons before it answers. OpenAI's
 * reasoning models and Gemini's thinking models count their reasoning toward
 * the output limit, so without room for it a long answer (Plan my day's
 * JSON) could be cut off or never start. Older models get none, since some
 * refuse a limit above what they can write.
 */
export function reasoningHeadroom(provider: AIProviderID, model: string): number {
  const lower = model.toLowerCase();
  switch (provider) {
    case "openai":
      return ["o1", "o3", "o4", "gpt-5"].some((prefix) => lower.startsWith(prefix)) ? 8192 : 0;
    case "gemini":
      return lower.startsWith("gemini-") && !lower.startsWith("gemini-1.") && !lower.startsWith("gemini-2.0") ? 8192 : 0;
    default:
      return 0;
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function objects(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(isObject) : [];
}

/**
 * The events in one line of `provider`'s streaming response. Blank lines,
 * `event:` names, keep-alives and unknown shapes yield nothing; an error the
 * provider reports mid-stream throws `AIProviderFailure`, and so does an
 * answer the token limit cut off (`cutOff`), so a feature never takes half
 * an answer for a whole one.
 */
export function eventsFromLine(line: string, provider: AIProviderID): AIStreamEvent[] {
  let payload: string;
  if (provider === "ollama") {
    payload = line;
  } else {
    if (!line.startsWith("data:")) return [];
    payload = line.slice(5).replace(/^[ \t]+|[ \t]+$/g, "");
    if (payload === "[DONE]") return [{ kind: "finished" }];
  }
  let object: unknown;
  try {
    object = JSON.parse(payload);
  } catch {
    return [];
  }
  if (!isObject(object)) return [];
  const error = streamError(object);
  if (error) throw new AIProviderFailure(error);
  const cutOff = () => new AIProviderFailure({ kind: "cutOff" });

  switch (provider) {
    case "anthropic": {
      switch (object.type) {
        case "message_delta": {
          const delta = isObject(object.delta) ? object.delta : undefined;
          if (delta?.stop_reason === "max_tokens") throw cutOff();
          return [];
        }
        case "content_block_delta": {
          const delta = isObject(object.delta) ? object.delta : undefined;
          if (delta?.type !== "text_delta" || typeof delta.text !== "string") return [];
          return [{ kind: "textDelta", text: delta.text }];
        }
        case "message_stop":
          return [{ kind: "finished" }];
        default:
          return [];
      }
    }
    case "openai": {
      const choices = objects(object.choices);
      if (choices.some((choice) => choice.finish_reason === "length")) throw cutOff();
      const text = choices
        .map((choice) => (isObject(choice.delta) && typeof choice.delta.content === "string" ? choice.delta.content : ""))
        .join("");
      return text.length === 0 ? [] : [{ kind: "textDelta", text }];
    }
    case "gemini": {
      const candidates = objects(object.candidates);
      if (candidates.some((candidate) => candidate.finishReason === "MAX_TOKENS")) throw cutOff();
      /* Thinking models stream their thoughts as parts marked `thought`. */
      const text = candidates
        .flatMap((candidate) => (isObject(candidate.content) && Array.isArray(candidate.content.parts) ? objects(candidate.content.parts) : []))
        .filter((part) => part.thought !== true)
        .map((part) => (typeof part.text === "string" ? part.text : ""))
        .join("");
      return text.length === 0 ? [] : [{ kind: "textDelta", text }];
    }
    case "ollama": {
      const message = isObject(object.message) ? object.message : undefined;
      const text = typeof message?.content === "string" ? message.content : "";
      const events: AIStreamEvent[] = text.length === 0 ? [] : [{ kind: "textDelta", text }];
      if (object.done === true) {
        if (object.done_reason === "length") throw cutOff();
        events.push({ kind: "finished" });
      }
      return events;
    }
    case "claude-cli":
    case "codex-cli":
    case "gemini-cli":
      return [];
  }
}

/** The error for a response that did not start streaming: its HTTP status and body text. */
export function errorFromResponse(status: number, body: string): AIProviderError {
  let object: unknown;
  try {
    object = JSON.parse(body);
  } catch {
    object = undefined;
  }
  const detail = isObject(object) ? errorMessage(object) : undefined;
  switch (status) {
    case 401:
    case 403:
      return { kind: "invalidAPIKey" };
    case 429:
    case 529:
      return detail === undefined ? { kind: "rateLimited" } : { kind: "rateLimited", detail };
    default:
      return { kind: "service", detail: detail ?? `The request failed (HTTP ${status}).` };
  }
}

function streamError(object: Record<string, unknown>): AIProviderError | undefined {
  if (object.error === undefined || object.error === null) return undefined;
  const message = errorMessage(object);
  if (message === undefined) return undefined;
  const error = isObject(object.error) ? object.error : undefined;
  const type = error?.type;
  const code = error?.code;
  if (type === "overloaded_error" || type === "rate_limit_error" || code === 429) return { kind: "rateLimited", detail: message };
  return { kind: "service", detail: message };
}

/** `{"error":{"message":...}}` (Anthropic, OpenAI, Gemini) or `{"error":"..."}` (Ollama). */
function errorMessage(object: Record<string, unknown>): string | undefined {
  if (typeof object.error === "string") return object.error;
  if (isObject(object.error) && typeof object.error.message === "string") return object.error.message;
  return undefined;
}
