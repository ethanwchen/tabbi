import { type AIProviderID, defaultModel, displayName } from "./aiProviderID";

/** Port of AIMessage: one turn of a conversation sent to a provider. */
export interface AIMessage {
  role: "user" | "assistant";
  text: string;
  /** PNG images (screenshots) sent with a user turn. */
  images: readonly Uint8Array[];
}

export function userMessage(text: string, images: readonly Uint8Array[] = []): AIMessage {
  return { role: "user", text, images };
}

export function assistantMessage(text: string): AIMessage {
  return { role: "assistant", text, images: [] };
}

/**
 * Port of AIRequest: a provider-neutral request. Hosted APIs are stateless,
 * so `messages` carries the whole chat; a CLI that keeps its own session
 * gets `resumeSessionID` and only needs the last message.
 */
export interface AIRequest {
  system?: string;
  messages: readonly AIMessage[];
  /** Empty means the provider's default model. */
  model: string;
  maxTokens: number;
  /** A CLI session to continue. */
  resumeSessionID?: string;
  /**
   * A JSON Schema the answer must follow, where the provider can enforce one.
   * Others only get the prompt's own instructions, so callers still parse
   * the answer leniently.
   */
  responseSchema?: string;
}

export function aiRequest(fields: Partial<AIRequest> & Pick<AIRequest, "messages">): AIRequest {
  return { model: "", maxTokens: 4096, ...fields };
}

/** A one-shot prompt, as Plan my day and Day review send. */
export function promptRequest(text: string, model = "", responseSchema?: string): AIRequest {
  return aiRequest({ messages: [userMessage(text)], model, ...(responseSchema === undefined ? {} : { responseSchema }) });
}

/** The model to send to `provider`. */
export function resolvedModel(request: AIRequest, provider: AIProviderID): string {
  const trimmed = request.model.trim();
  return trimmed.length === 0 ? defaultModel(provider) : trimmed;
}

/** Port of AIStreamEvent: what a provider streams back, the same for every provider. */
export type AIStreamEvent =
  /** A CLI started or resumed a session the next request can continue. */
  | { kind: "sessionStarted"; sessionID: string }
  /** The next piece of the answer. */
  | { kind: "textDelta"; text: string }
  /**
   * The run ended. `text` is the whole answer when the provider reports it
   * (a CLI's final result); otherwise the deltas are the answer.
   */
  | { kind: "finished"; text?: string };

/** Port of AIProviderError: why a provider could not answer, worded for the panel's error state. */
export type AIProviderError =
  /** The command line tool is not installed (or not where Tabbi looks). */
  | { kind: "notInstalled" }
  /** The provider needs an API key and none is saved. */
  | { kind: "missingAPIKey" }
  /** The key was refused (HTTP 401 or 403). */
  | { kind: "invalidAPIKey" }
  /** Too many requests or the quota ran out (HTTP 429). */
  | { kind: "rateLimited"; detail?: string }
  /** Nothing answered at the address (Ollama not running, no network). */
  | { kind: "unreachable"; detail?: string }
  /** The provider answered with an error of its own. */
  | { kind: "service"; detail: string }
  /** The answer reached the output token limit before it was complete. */
  | { kind: "cutOff" };

/** Thrown by providers; `error` says what went wrong. */
export class AIProviderFailure extends Error {
  constructor(readonly error: AIProviderError) {
    super(`AI provider: ${error.kind}${"detail" in error && error.detail !== undefined ? `: ${error.detail}` : ""}`);
    this.name = "AIProviderFailure";
  }
}

/** A sentence for the error state, naming `provider`. Plain English, as on the Mac. */
export function providerErrorMessage(error: AIProviderError, provider: AIProviderID): string {
  const name = displayName(provider);
  switch (error.kind) {
    case "notInstalled":
      return `${name} is not installed.`;
    case "missingAPIKey":
      return `Add your ${name} key in Settings.`;
    case "invalidAPIKey":
      return `${name} did not accept the key. Check it in Settings.`;
    case "rateLimited":
      return error.detail !== undefined ? `${name} is busy: ${error.detail}` : `${name} is out of quota for now. Try again in a minute.`;
    case "unreachable":
      return provider === "ollama" ? "Ollama is not running. Open Ollama and try again." : `Could not reach ${name}. Check your connection.`;
    case "service":
      return error.detail;
    case "cutOff":
      return `${name} stopped before the answer was complete. Try a shorter question.`;
  }
}
