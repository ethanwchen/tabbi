/*
 * Port of ClaudeAskSession: drives the Ask panel. It sends questions to the
 * AI provider the user picked (through the shared AIService), folds the
 * provider's stream into a ClaudeAskConversation, and supports stop, retry
 * and New chat. Finished exchanges are saved to the chat history on this PC
 * (live runs only), and a saved chat can be reopened. Screenshots are a
 * later Windows feature, so a question here carries none.
 */

import type { AIService } from "../../app/aiService";
import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { assistantName, type AIProviderID } from "../../core/ai/aiProviderID";
import type { AISetupState } from "../../core/ai/aiProviderFactory";
import { ClaudeAskHistory, demoHistory, type ClaudeAskChat } from "../../core/claudeAsk/claudeAskChat";
import {
  CLAUDE_ASK_INSTRUCTIONS,
  ClaudeAskConversation,
  type ClaudeAskFailure,
  type ClaudeAskMessage,
  type ClaudeAskPhase,
  type ClaudeAskQuestion,
  demoConversation,
  failureFromError,
  failureNeedsSetup,
} from "../../core/claudeAsk/claudeAskConversation";
import { newUUID } from "../../core/planner/uuid";

/** What the session needs from the AI service: the provider when it can send, and the setup state otherwise. Tests pass a fake. */
export type AskAI = Pick<AIService, "readyProvider" | "setupState">;

export interface AskState {
  /** The chat's rows; a fresh array on every change, so React redraws streamed text. */
  readonly messages: readonly ClaudeAskMessage[];
  readonly phase: ClaudeAskPhase;
  /** The chat's id, which the history list marks as open. */
  readonly chatID: string;
  readonly isStreaming: boolean;
  readonly isEmpty: boolean;
  /**
   * What the user must set up before asking (no provider picked, a missing
   * key), so the panel explains it before the user types a question.
   * Undefined when ready.
   */
  readonly setupNeeded: ClaudeAskFailure | undefined;
  /** Saved chats, the most recently answered first. Demo runs keep a sample list in memory. */
  readonly savedChats: readonly ClaudeAskChat[];
  /** True while the panel lists saved chats instead of the conversation. */
  readonly isShowingHistory: boolean;
  /** The picked assistant's name for running text ("Ask Claude anything"), or "AI" while none is picked. */
  readonly assistant: string;
}

/** The sentence a demo run answers with, since it sends nothing anywhere. */
export function demoAnswer(appName: string): string {
  return `This is a demo. Run ${appName} without \`TABBI_DEMO\` to get a real answer.`;
}

export class ClaudeAskSession extends Store<AskState> {
  private conversation: ClaudeAskConversation;
  /** Undefined in demo and snapshot runs, which save nothing. */
  private readonly history: ClaudeAskHistory | undefined;
  private readonly isDemo: boolean;
  private readonly isSnapshot: boolean;
  private controller: AbortController | undefined;
  /** Bumped on every ask, stop and New chat so a superseded run can't write into the conversation after it was cancelled. */
  private generation = 0;
  /** Bumped on every setup lookup so a slow one for an old setup can't overwrite `setupNeeded` after a newer one finished. */
  private lookupGeneration = 0;
  /** True between `ask` and the provider lookup it awaits, so two quick sends never start two exchanges. */
  private sending = false;
  /** True while a snapshot shot shows the panel as it is once set up. */
  private snapshotHidesSetup = false;

  constructor(
    private readonly context: ModuleContext,
    readonly ai: AskAI,
  ) {
    const isDemo = context.isDemo;
    const savesNothing = isDemo || context.isSnapshot;
    const history = savesNothing ? undefined : new ClaudeAskHistory(context.storage.root());
    let conversation: ClaudeAskConversation;
    let savedChats: ClaudeAskChat[] = [];
    if (isDemo) {
      savedChats = demoHistory(context.now(), newUUID);
      const first = savedChats[0];
      conversation = first ? ClaudeAskConversation.restoring(first) : demoConversation(newUUID(), context.now());
    } else {
      conversation = new ClaudeAskConversation(newUUID(), context.now());
    }
    super({
      messages: [...conversation.messages],
      phase: conversation.phase,
      chatID: conversation.chatID,
      isStreaming: false,
      isEmpty: conversation.isEmpty,
      setupNeeded: undefined,
      savedChats,
      isShowingHistory: false,
      assistant: isDemo ? assistantName("claude-cli") : "AI",
    });
    this.conversation = conversation;
    this.history = history;
    this.isDemo = isDemo;
    this.isSnapshot = context.isSnapshot;
    if (history) void this.reloadHistory();
  }

  get isStreaming(): boolean {
    return this.conversation.isStreaming;
  }

  /** Sends `prompt`, continuing the current chat when there is one. */
  ask(prompt: string): void {
    void this.send({ text: prompt, attachments: [] });
  }

  /** Resolves to false when there was nothing to send. */
  private async send(question: ClaudeAskQuestion): Promise<boolean> {
    if (this.isStreaming || this.sending) return false;
    if (question.text.trim().length === 0) return false;
    this.setState({ isShowingHistory: false });

    if (this.isDemo) {
      if (this.conversation.begin(question.text, question.attachments) === undefined) return false;
      this.conversation.applyClaude({
        type: "result",
        result: { text: demoAnswer(this.context.edition.name), sessionID: this.conversation.sessionID, isError: false },
      });
      this.exchangeEnded();
      return true;
    }

    /* Nothing is sent before the user picks a provider. */
    this.sending = true;
    let provider;
    try {
      provider = await this.ai.readyProvider();
    } catch {
      provider = undefined;
    } finally {
      this.sending = false;
    }
    if (this.isStreaming) return false;
    if (provider === undefined) {
      if (this.conversation.begin(question.text, question.attachments) === undefined) return false;
      this.conversation.fail({ kind: "noProvider" });
      this.setState({ setupNeeded: { kind: "noProvider" } });
      this.exchangeEnded();
      return true;
    }
    const id = provider.id;
    const prompt = this.conversation.begin(question.text, question.attachments, id);
    if (prompt === undefined) return false;
    this.generation += 1;
    const generation = this.generation;
    const controller = new AbortController();
    this.controller = controller;
    this.publish();
    const request = this.conversation.request(prompt, id, { system: CLAUDE_ASK_INSTRUCTIONS });
    void (async () => {
      try {
        for await (const event of provider.stream(request, controller.signal)) {
          this.update(generation, (conversation) => conversation.apply(event, id));
        }
        this.update(generation, (conversation) => conversation.finish(id));
      } catch (error) {
        /* Stop, New chat or another chat took over. */
        if (controller.signal.aborted) return;
        const failure = failureFromError(error, id);
        this.update(generation, (conversation) => {
          if (conversation.isStreaming) conversation.fail(failure);
        });
        if (failureNeedsSetup(failure)) this.setState({ setupNeeded: failure });
      }
    })();
    return true;
  }

  /** Stops the answer in progress, keeping what has arrived so far. */
  stop(): void {
    if (!this.isStreaming) return;
    this.invalidateRun();
    this.conversation.cancel();
    this.exchangeEnded();
  }

  /** Sends the failed question again. */
  retry(): void {
    if (this.isStreaming) return;
    const question = this.conversation.takeRetryQuestion();
    if (question === undefined) return;
    this.publish();
    void this.send(question);
  }

  /**
   * Checks the provider's setup ahead of the first question: the panel calls
   * this when it appears, and the module whenever the settings change.
   * `state` is a setup state already in hand.
   */
  prepare(state?: AISetupState): void {
    if (this.isDemo || this.snapshotHidesSetup) return;
    this.lookupGeneration += 1;
    const lookup = this.lookupGeneration;
    const apply = (setup: AISetupState) => {
      if (lookup !== this.lookupGeneration) return;
      const provider = setup.kind === "notChosen" ? undefined : setup.provider;
      this.setState({
        setupNeeded: setup.kind === "notChosen" ? { kind: "noProvider" } : setup.kind === "needsKey" ? { kind: "needsKey", provider: setup.provider } : undefined,
        assistant: provider === undefined ? "AI" : assistantName(provider),
      });
    };
    if (state) {
      apply(state);
      return;
    }
    this.ai.setupState().then(apply, () => apply({ kind: "notChosen" }));
  }

  /** Clears the chat; the next question starts a fresh one. */
  newChat(): void {
    this.invalidateRun();
    this.conversation.reset(newUUID(), this.context.now());
    this.setState({ isShowingHistory: false });
    this.publish();
  }

  /** Reopens a saved chat; the next question continues it. */
  open(chat: ClaudeAskChat): void {
    if (chat.id === this.conversation.chatID) {
      this.setState({ isShowingHistory: false });
      return;
    }
    /* Stopping a running answer saves what arrived before switching. */
    this.stop();
    this.invalidateRun();
    this.conversation = ClaudeAskConversation.restoring(chat);
    this.setState({ isShowingHistory: false });
    this.publish();
  }

  /** Removes a chat from the history. Deleting the open chat clears it too, rather than saving it again with its next answer. */
  delete(chat: ClaudeAskChat): void {
    void this.history?.delete(chat.id).catch(() => undefined);
    if (this.conversation.chatID === chat.id) {
      this.invalidateRun();
      this.conversation.reset(newUUID(), this.context.now());
      this.publish();
    }
    void this.reloadHistory([chat.id]);
  }

  /** Removes every saved chat and starts a new one. */
  deleteAllChats(): void {
    void this.history?.deleteAll().catch(() => undefined);
    this.invalidateRun();
    this.conversation.reset(newUUID(), this.context.now());
    this.publish();
    void this.reloadHistory(this.state.savedChats.map((chat) => chat.id));
  }

  setShowingHistory(showing: boolean): void {
    this.setState({ isShowingHistory: showing });
  }

  /**
   * Snapshot runs only: puts the panel in a named state for the next shot.
   * The main shot shows the demo chat; the others show their state as set
   * up, except `setup` and `needs-key`, which show the setup screen.
   */
  showSnapshotState(state: string): void {
    if (!this.isSnapshot) return;
    this.invalidateRun();
    this.snapshotHidesSetup = true;
    const now = this.context.now();
    const sample = () => ClaudeAskConversation.restoring(demoHistory(now, newUUID)[0] ?? { id: newUUID(), createdAt: now, updatedAt: now, messages: [] });
    this.setState({ setupNeeded: undefined, isShowingHistory: false, assistant: assistantName("claude-cli") });
    switch (state) {
      case "empty":
        this.conversation = new ClaudeAskConversation(newUUID(), now);
        break;
      case "history":
        this.conversation = sample();
        this.setState({ isShowingHistory: true });
        break;
      case "history-empty":
        this.conversation = new ClaudeAskConversation(newUUID(), now);
        this.setState({ isShowingHistory: true, savedChats: [] });
        break;
      case "thinking":
        this.conversation = sample();
        this.conversation.begin("What's a good name for a retry helper?", [], "claude-cli");
        break;
      case "streaming":
        this.conversation = sample();
        this.conversation.begin("Can you shorten that answer?", [], "claude-cli");
        this.conversation.applyClaude({ type: "textDelta", text: "Sure. Retry a few times, waiting longer after each try, and stop after" });
        break;
      case "failed":
        this.conversation = sample();
        this.conversation.begin("Can you shorten that answer?", [], "anthropic");
        this.conversation.fail({ kind: "process", detail: "Claude API is out of quota for now. Try again in a minute." });
        break;
      case "setup":
        this.conversation = new ClaudeAskConversation(newUUID(), now);
        this.setState({ setupNeeded: { kind: "noProvider" }, assistant: "AI" });
        break;
      case "needs-key":
        this.conversation = new ClaudeAskConversation(newUUID(), now);
        this.setState({ setupNeeded: { kind: "needsKey", provider: "gemini" }, assistant: assistantName("gemini") });
        break;
      default:
        this.conversation = sample();
    }
    this.publish();
  }

  /* Helpers */

  private invalidateRun(): void {
    this.generation += 1;
    this.controller?.abort();
    this.controller = undefined;
  }

  private update(generation: number, change: (conversation: ClaudeAskConversation) => void): void {
    if (generation !== this.generation) return;
    const wasStreaming = this.conversation.isStreaming;
    change(this.conversation);
    this.publish();
    if (!(wasStreaming && !this.conversation.isStreaming)) return;
    /* The CLI deletes old sessions; such a chat goes on as a new one, seeded with what was said so far. */
    const question = this.conversation.takeQuestionForLostSession();
    if (question) {
      this.publish();
      void this.send(question);
    } else {
      this.exchangeEnded();
    }
  }

  /** Saves the chat once an exchange ends (live runs only). */
  private exchangeEnded(): void {
    this.publish();
    const history = this.history;
    const chat = history === undefined ? undefined : this.conversation.savedChat(this.context.now());
    if (!history || !chat) return;
    void history
      .save(chat)
      .catch(() => undefined)
      .then(() => this.reloadHistory());
  }

  /** Rereads the saved chats; demo runs, which have no files, drop `removed` from the sample list instead. */
  private async reloadHistory(removed: readonly string[] = []): Promise<void> {
    if (this.history) {
      try {
        this.setState({ savedChats: await this.history.chats() });
      } catch {
        /* A folder that can't be listed leaves the list as it was. */
      }
    } else {
      this.setState({ savedChats: this.state.savedChats.filter((chat) => !removed.includes(chat.id)) });
    }
  }

  /** Pushes the conversation's current shape into the state. */
  private publish(): void {
    const conversation = this.conversation;
    this.changed({
      ...this.state,
      messages: [...conversation.messages],
      phase: conversation.phase,
      chatID: conversation.chatID,
      isStreaming: conversation.isStreaming,
      isEmpty: conversation.isEmpty,
    });
  }

  /** The provider named on a message, for "Claude couldn't answer". */
  static assistantOf(message: ClaudeAskMessage, fallback: string): string {
    return message.provider === undefined ? fallback : assistantName(message.provider);
  }

  /** Who the setup state names. */
  static providerOf(failure: ClaudeAskFailure): AIProviderID | undefined {
    return failure.kind === "noProvider" || failure.kind === "process" ? undefined : failure.provider;
  }
}
