import { characters } from "../anki/ankiConnectError";
import { type AIProviderID, assistantName, displayName, isCommandLineTool } from "../ai/aiProviderID";
import {
  type AIMessage,
  type AIProviderError,
  AIProviderFailure,
  type AIRequest,
  type AIStreamEvent,
  aiRequest,
  providerErrorMessage,
  userMessage,
} from "../ai/aiRequest";
import { ProcessFailure } from "../claude/claudeCLI";
import type { ClaudeStreamEvent } from "../claude/claudeStreamEvent";
import { tr } from "../localization/tr";
import type { Instant } from "../time";
import type { ClaudeAskAttachment } from "./claudeAskAttachment";
import type { ClaudeAskChat, ClaudeAskChatMessage } from "./claudeAskChat";

export type ClaudeAskRole = "user" | "assistant";

/** Lifecycle of an answer; questions are always `complete`. `stopped` keeps what arrived before stop. */
export type ClaudeAskStatus = "streaming" | "complete" | "stopped" | "failed";

/** Port of ClaudeAskMessage: one bubble in the Ask panel. */
export interface ClaudeAskMessage {
  /** Unique within a conversation, across `reset()` too, so a row identity is never reused. */
  readonly id: number;
  readonly role: ClaudeAskRole;
  text: string;
  status: ClaudeAskStatus;
  /** Screenshots sent with a question; always empty on answers. */
  readonly attachments: readonly ClaudeAskAttachment[];
  /** Who was asked for this answer; undefined on questions and restored answers. */
  readonly provider?: AIProviderID;
}

/** Port of ClaudeAskQuestion: a question as it is sent, with any screenshots. */
export interface ClaudeAskQuestion {
  text: string;
  attachments: readonly ClaudeAskAttachment[];
}

/** Port of ClaudeAskFailure: why the last question couldn't be answered. */
export type ClaudeAskFailure =
  /** No AI provider is picked yet, so nothing was sent. */
  | { kind: "noProvider" }
  /** The provider's command line tool was not found. */
  | { kind: "notInstalled"; provider: AIProviderID }
  /** The provider needs an API key and none is saved. */
  | { kind: "needsKey"; provider: AIProviderID }
  /** The provider ran but reported an error; `detail` is one short line safe to show. */
  | { kind: "process"; detail: string };

export type ClaudeAskPhase = { kind: "idle" } | { kind: "streaming" } | { kind: "failed"; failure: ClaudeAskFailure };

/** True when Connections, not Retry, is the way forward. */
export function failureNeedsSetup(failure: ClaudeAskFailure): boolean {
  return failure.kind !== "process";
}

/**
 * What every provider is told about the panel, so answers fit it: short, in
 * Markdown, and with no tools to reach for.
 */
export const CLAUDE_ASK_INSTRUCTIONS =
  "You answer quick questions in Tabbi, a small panel at the top of the screen. " +
  "Be brief and direct, use Markdown sparingly, and keep code samples short.";

/**
 * Reduces raw error output to one readable line: the first non-empty line,
 * capped at `limit` characters. Undefined for empty input.
 */
export function summarize(raw: string | undefined, limit = 140): string | undefined {
  const line = raw
    ?.split(/\r\n|[\n\r\v\f\x85\p{Zl}\p{Zp}]/u)
    .map((part) => part.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, ""))
    .find((part) => part.length > 0);
  if (line === undefined) return undefined;
  const chars = characters(line);
  if (chars.length <= limit) return line;
  return chars.slice(0, limit - 1).join("").replace(/[\p{Zs}\t]+$/u, "") + "…";
}

/** Maps an error thrown by `provider`'s stream to a failure safe to show. */
export function failureFromError(error: unknown, provider: AIProviderID): ClaudeAskFailure {
  if (error instanceof AIProviderFailure) return failureFromProviderError(error.error, provider);
  if (error instanceof ProcessFailure) {
    return {
      kind: "process",
      detail: summarize(error.stderr) ?? `${assistantName(provider)} exited unexpectedly (status ${error.status}).`,
    };
  }
  const description = error instanceof Error ? error.message : typeof error === "string" ? error : undefined;
  return { kind: "process", detail: summarize(description) ?? `Couldn't start ${assistantName(provider)}.` };
}

export function failureFromProviderError(error: AIProviderError, provider: AIProviderID): ClaudeAskFailure {
  if (error.kind === "notInstalled") return { kind: "notInstalled", provider };
  if (error.kind === "missingAPIKey") return { kind: "needsKey", provider };
  return { kind: "process", detail: summarize(providerErrorMessage(error, provider)) ?? `${assistantName(provider)} couldn't answer.` };
}

/** The failed answer's headline; `assistant` names who was asked. */
export function failureTitle(failure: ClaudeAskFailure, assistant: string): string {
  switch (failure.kind) {
    case "noProvider":
      return "No AI chosen yet";
    case "notInstalled":
      return `${assistantName(failure.provider)} isn't set up yet`;
    case "needsKey":
      return `${displayName(failure.provider)} needs a key`;
    case "process":
      return `${assistant} couldn't answer`;
  }
}

/** The line under the headline. */
export function failureDetail(failure: ClaudeAskFailure): string {
  switch (failure.kind) {
    case "noProvider":
      return "Pick one in Connections. Some are free.";
    case "notInstalled":
      return "Connections shows you how to add it.";
    case "needsKey":
      return "Add your key in Connections.";
    case "process":
      return failure.detail;
  }
}

/** The setup screen's headline, shown before the first question. */
export function failureSetupTitle(failure: ClaudeAskFailure): string {
  switch (failure.kind) {
    case "noProvider":
      return tr("Choose an AI to ask questions");
    case "notInstalled":
      return tr("Set up %@ to ask questions", assistantName(failure.provider));
    case "needsKey":
      return tr("Add your %@ key", displayName(failure.provider));
    case "process":
      return tr("Ask anything");
  }
}

/** The setup screen's sentence. */
export function failureSetupMessage(failure: ClaudeAskFailure): string {
  switch (failure.kind) {
    case "noProvider":
      return tr("Answers come from the AI you pick: Claude, ChatGPT, Gemini or a free model on this Mac.");
    case "notInstalled":
      return tr("%@ isn't on this Mac yet. Connections shows you how to add it.", displayName(failure.provider));
    case "needsKey":
      return tr("Paste a key in Connections to ask %@ questions. It stays in your Keychain.", assistantName(failure.provider));
    case "process":
      return failure.detail;
  }
}

/** The button that opens Connections. */
export function failureSetupAction(failure: ClaudeAskFailure): string {
  switch (failure.kind) {
    case "noProvider":
      return tr("Choose AI");
    case "notInstalled":
      return tr("Set up %@", assistantName(failure.provider));
    case "needsKey":
      return tr("Add key");
    case "process":
      return tr("Open Connections");
  }
}

function join(first: string, second: string): string {
  if (first.length === 0) return second;
  if (second.length === 0) return first;
  return `${first}\n\n${second}`;
}

/**
 * Port of ClaudeAskConversation: an in-memory Ask chat and the pure reducer
 * that folds a provider's stream events into it. Free of process and UI
 * concerns, so streaming semantics (partial text, final result, errors,
 * session capture for resuming) are unit tested.
 */
export class ClaudeAskConversation {
  private messageList: ClaudeAskMessage[] = [];
  private currentPhase: ClaudeAskPhase = { kind: "idle" };
  /** Session to pass to `--resume` so follow-ups keep context. */
  private session: string | undefined;
  /** The command line tool `session` belongs to; another provider can't resume it. */
  private sessionHolder: AIProviderID | undefined;
  /** Text of assistant messages the CLI already finalized in this run. */
  private committedText = "";
  /** Streaming deltas of the assistant message being written. */
  private partialText = "";
  private nextID = 0;

  constructor(
    /** Names this chat in the history; `reset()` starts a new one. */
    private id: string,
    /** When this chat began, kept when it is saved and restored. */
    private started: Instant,
  ) {}

  /** Reopens a saved chat so the next question continues it. */
  static restoring(chat: ClaudeAskChat): ClaudeAskConversation {
    const conversation = new ClaudeAskConversation(chat.id, chat.createdAt);
    conversation.session = chat.sessionID;
    conversation.sessionHolder = chat.sessionID === undefined ? undefined : chat.sessionProvider;
    for (const message of chat.messages) conversation.append(message.role, message.text, message.status, message.attachments);
    return conversation;
  }

  get messages(): readonly ClaudeAskMessage[] {
    return this.messageList;
  }

  get phase(): ClaudeAskPhase {
    return this.currentPhase;
  }

  get sessionID(): string | undefined {
    return this.session;
  }

  get sessionProvider(): AIProviderID | undefined {
    return this.sessionHolder;
  }

  get chatID(): string {
    return this.id;
  }

  get startedAt(): Instant {
    return this.started;
  }

  get isStreaming(): boolean {
    return this.currentPhase.kind === "streaming";
  }

  get isEmpty(): boolean {
    return this.messageList.length === 0;
  }

  /** Why the latest exchange failed, while it is still the latest. */
  get failure(): ClaudeAskFailure | undefined {
    return this.currentPhase.kind === "failed" ? this.currentPhase.failure : undefined;
  }

  /**
   * The chat as it should be saved, or undefined while there is nothing
   * worth keeping. A failed exchange is left out (its question can be
   * retried, not reread) and an answer still streaming is saved as stopped,
   * so a restored chat never shows a spinner nothing drives.
   */
  savedChat(updatedAt: Instant): ClaudeAskChat | undefined {
    const kept: ClaudeAskChatMessage[] = [];
    let pendingQuestion: ClaudeAskChatMessage | undefined;
    for (const message of this.messageList) {
      if (message.role === "user") {
        pendingQuestion = { role: "user", text: message.text, status: "complete", attachments: [...message.attachments] };
        continue;
      }
      if (!pendingQuestion || message.status === "failed") continue;
      const status: ClaudeAskStatus = message.status === "streaming" ? "stopped" : message.status;
      if (status === "stopped" && message.text.length === 0) continue;
      kept.push(pendingQuestion, { role: "assistant", text: message.text, status, attachments: [] });
      pendingQuestion = undefined;
    }
    if (kept.length === 0) return undefined;
    const chat: ClaudeAskChat = { id: this.id, createdAt: this.started, updatedAt, messages: kept };
    if (this.session !== undefined) {
      chat.sessionID = this.session;
      if (this.sessionHolder !== undefined) chat.sessionProvider = this.sessionHolder;
    }
    return chat;
  }

  /**
   * Starts a new exchange. Returns the trimmed prompt to send, or undefined
   * if it is blank or an answer is still streaming. `provider` is who will
   * be asked (undefined while none is picked).
   */
  begin(prompt: string, attachments: readonly ClaudeAskAttachment[] = [], provider?: AIProviderID): string | undefined {
    const trimmed = prompt.trim();
    if (trimmed.length === 0 || this.isStreaming) return undefined;
    this.append("user", trimmed, "complete", attachments);
    this.append("assistant", "", "streaming", [], provider);
    this.committedText = "";
    this.partialText = "";
    this.currentPhase = { kind: "streaming" };
    return trimmed;
  }

  /**
   * Applies one event from `claude -p --output-format stream-json`. Events
   * outside a streaming exchange are ignored.
   */
  applyClaude(event: ClaudeStreamEvent): void {
    if (!this.isStreaming) return;
    switch (event.type) {
      case "sessionStarted":
        if (event.sessionID !== undefined) this.holdSession(event.sessionID, "claude-cli");
        break;
      case "textDelta":
        this.partialText += event.text;
        this.updateAnswer(this.displayedText);
        break;
      case "assistantText":
        /* A complete message supersedes the deltas that built it. */
        this.committedText = join(this.committedText, event.text);
        this.partialText = "";
        this.updateAnswer(this.committedText);
        break;
      case "result": {
        const result = event.result;
        if (result.sessionID !== undefined) this.holdSession(result.sessionID, "claude-cli");
        if (result.isError) {
          this.fail({ kind: "process", detail: summarize(result.text) ?? "Claude couldn't finish this answer." });
        } else {
          const final = result.text !== undefined && result.text.length > 0 ? result.text : this.displayedText;
          this.updateAnswer(final, "complete");
          this.currentPhase = { kind: "idle" };
        }
        break;
      }
      case "rateLimit":
      case "other":
        break;
    }
  }

  /** Applies one event from `provider`'s stream. Events outside a streaming exchange are ignored. */
  apply(event: AIStreamEvent, provider: AIProviderID): void {
    if (!this.isStreaming) return;
    switch (event.kind) {
      case "sessionStarted":
        this.holdSession(event.sessionID, provider);
        break;
      case "textDelta":
        this.dropSession(provider);
        this.partialText += event.text;
        this.updateAnswer(this.displayedText);
        break;
      case "finished":
        this.dropSession(provider);
        if (event.text !== undefined && event.text.length > 0) {
          this.committedText = event.text;
          this.partialText = "";
        }
        this.finish(provider);
        break;
    }
  }

  /**
   * The stream ended. Without a result, whatever arrived is kept as the
   * answer; an empty answer counts as a failure.
   */
  finish(provider: AIProviderID = "claude-cli"): void {
    if (!this.isStreaming) return;
    const text = this.displayedText;
    if (text.length === 0) {
      this.fail({ kind: "process", detail: `${assistantName(provider)} ended without answering.` });
    } else {
      this.updateAnswer(text, "complete");
      this.currentPhase = { kind: "idle" };
    }
  }

  /** Records a failure for the current exchange (or before one starts). */
  fail(failure: ClaudeAskFailure): void {
    const answer = this.lastAnswer;
    if (answer && answer.status === "streaming") answer.status = "failed";
    this.currentPhase = { kind: "failed", failure };
  }

  /** The user pressed stop: keep the partial answer, mark it stopped. */
  cancel(): void {
    if (!this.isStreaming) return;
    this.updateAnswer(this.displayedText, "stopped");
    this.currentPhase = { kind: "idle" };
  }

  /**
   * Removes the failed exchange and returns its question (with its
   * screenshots) so it can be sent again. Undefined when there's nothing
   * to retry.
   */
  takeRetryQuestion(): ClaudeAskQuestion | undefined {
    if (this.currentPhase.kind !== "failed") return undefined;
    this.currentPhase = { kind: "idle" };
    const userIndex = this.messageList.findLastIndex((message) => message.role === "user");
    const question = this.messageList[userIndex];
    if (!question) return undefined;
    this.messageList = this.messageList.slice(0, userIndex);
    return { text: question.text, attachments: question.attachments };
  }

  /**
   * When the last question failed because the CLI no longer has this chat's
   * session (it deletes old ones), drops the session and returns the
   * question so it can be sent again as a fresh session. Undefined for any
   * other failure, so it never retries more than once.
   */
  takeQuestionForLostSession(): ClaudeAskQuestion | undefined {
    const failure = this.failure;
    if (this.session === undefined || failure?.kind !== "process") return undefined;
    if (!failure.detail.toLowerCase().includes("no conversation found")) return undefined;
    this.session = undefined;
    this.sessionHolder = undefined;
    return this.takeRetryQuestion();
  }

  /**
   * The request for the question just begun, sent with `images` to
   * `provider`. A command line tool that holds this chat's session resumes
   * it and gets just `prompt`. Anyone else gets the earlier exchanges as
   * messages, newest kept first: the oldest are left out past
   * `transcriptLimit` characters. Only the new question's screenshots go.
   */
  request(
    prompt: string,
    provider: AIProviderID,
    options: { images?: readonly Uint8Array[]; system?: string; transcriptLimit?: number } = {},
  ): AIRequest {
    const question = userMessage(prompt, options.images ?? []);
    const system = options.system === undefined ? {} : { system: options.system };
    if (isCommandLineTool(provider) && this.session !== undefined && this.sessionHolder === provider) {
      return aiRequest({ ...system, messages: [question], resumeSessionID: this.session });
    }
    const limit = options.transcriptLimit ?? 24_000;
    /* A saved chat's timestamp doesn't matter here, only its exchanges. */
    const earlier = this.savedChat(0)?.messages ?? [];
    const history: AIMessage[] = [];
    let length = 0;
    for (let start = earlier.length - (earlier.length % 2 === 0 ? 2 : 1); start >= 0; start -= 2) {
      const exchange = earlier.slice(start, Math.min(start + 2, earlier.length)).map(
        (message): AIMessage => ({ role: message.role === "user" ? "user" : "assistant", text: message.text, images: [] }),
      );
      const size = exchange.reduce((sum, message) => sum + characters(message.text).length, 0);
      if (length + size > limit && history.length > 0) break;
      history.unshift(...exchange);
      length += size;
    }
    return aiRequest({ ...system, messages: [...history, question] });
  }

  /** Starts a new chat with a new id. Message ids keep increasing. */
  reset(chatID: string, now: Instant): void {
    this.id = chatID;
    this.started = now;
    this.messageList = [];
    this.currentPhase = { kind: "idle" };
    this.session = undefined;
    this.sessionHolder = undefined;
    this.committedText = "";
    this.partialText = "";
  }

  /* Helpers */

  private get displayedText(): string {
    return join(this.committedText, this.partialText);
  }

  private get lastAnswer(): ClaudeAskMessage | undefined {
    return this.messageList.findLast((message) => message.role === "assistant");
  }

  private holdSession(id: string, provider: AIProviderID): void {
    this.session = id;
    this.sessionHolder = provider;
  }

  /**
   * Another provider is answering, so the tool that held the session never
   * sees this exchange. Dropping it sends the whole chat as messages instead.
   */
  private dropSession(provider: AIProviderID): void {
    if (this.sessionHolder === provider) return;
    this.session = undefined;
    this.sessionHolder = undefined;
  }

  private append(
    role: ClaudeAskRole,
    text: string,
    status: ClaudeAskStatus,
    attachments: readonly ClaudeAskAttachment[] = [],
    provider?: AIProviderID,
  ): void {
    const message: ClaudeAskMessage = { id: this.nextID, role, text, status, attachments: [...attachments], ...(provider ? { provider } : {}) };
    this.messageList.push(message);
    this.nextID += 1;
  }

  private updateAnswer(text: string, status?: ClaudeAskStatus): void {
    const answer = this.lastAnswer;
    if (!answer) return;
    answer.text = text;
    if (status) answer.status = status;
  }
}

/** Two finished sample exchanges for demo runs and snapshots, built through the same reducer as live data. */
export function demoConversation(chatID: string, startedAt: Instant): ClaudeAskConversation {
  const conversation = new ClaudeAskConversation(chatID, startedAt);
  conversation.begin("How should an app retry a flaky network call?");
  conversation.applyClaude({ type: "sessionStarted", sessionID: "demo-session" });
  conversation.applyClaude({
    type: "result",
    result: {
      text: [
        "Retry a few times, waiting longer after each try:",
        "",
        "- Start around **0.5 s** and double the wait each time",
        "- Add a little random jitter so clients don't retry in sync",
        "- Stop after 3 to 5 tries and only retry errors that can pass",
      ].join("\n"),
      sessionID: "demo-session",
      isError: false,
    },
  });
  conversation.begin("Name for a function that retries with backoff?");
  conversation.applyClaude({
    type: "result",
    result: {
      text: [
        "I'd go with **`retryWithBackoff`**. It says what it does at the call site:",
        "",
        "```ts",
        "const profile = await retryWithBackoff(3, () =>",
        "  api.fetchProfile(),",
        ");",
        "```",
        "",
        "`withRetries(maxAttempts)` also reads well if you already use the `with...` style.",
      ].join("\n"),
      sessionID: "demo-session",
      isError: false,
    },
  });
  return conversation;
}
