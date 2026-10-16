import { describe, expect, it } from "vitest";
import type { AIProvider } from "../../../src/core/ai/aiProvider";
import type { AIProviderID } from "../../../src/core/ai/aiProviderID";
import { AIProviderFailure, type AIRequest, type AIStreamEvent } from "../../../src/core/ai/aiRequest";
import { decodeClaudeAskChat } from "../../../src/core/claudeAsk/claudeAskChat";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { DEMO_RUN_MODE, LIVE_RUN_MODE } from "../../../src/core/modules/runMode";
import { AskModule } from "../../../src/modules/claudeAsk/askModule";
import { ClaudeAskSession, demoAnswer, type AskAI } from "../../../src/modules/claudeAsk/askSession";
import { ModuleContext } from "../../../src/app/context";
import { testApp } from "../../support/runtime";

/* Port of the ClaudeAskSession tests, over the mock host and a scripted provider. */

const NOW = 1_790_000_000;
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
const settle = async (times = 4) => {
  for (let i = 0; i < times; i++) await tick();
};

/** A provider that plays `script` for every request, remembering what it was asked. */
function scriptedProvider(id: AIProviderID, script: () => AsyncGenerator<AIStreamEvent>, requests: AIRequest[] = []): AIProvider {
  return {
    id,
    stream(request: AIRequest, signal?: AbortSignal) {
      requests.push(request);
      const events = script();
      return {
        [Symbol.asyncIterator]: () => ({
          next: async () => {
            if (signal?.aborted) throw new Error("aborted");
            return events.next();
          },
          return: async () => ({ done: true as const, value: undefined }),
        }),
      };
    },
  };
}

function fakeAI(provider: AIProvider | undefined): AskAI {
  return {
    readyProvider: async () => provider,
    setupState: async () => (provider ? { kind: "ready", provider: provider.id } : { kind: "notChosen" }),
  };
}

async function liveSession(provider: AIProvider | undefined) {
  const { app, host } = await testApp({ moduleTypes: [AskModule], runMode: LIVE_RUN_MODE }, NOW);
  const context = new ModuleContext(MODULE_IDS.claudeAsk, app.environment);
  const session = new ClaudeAskSession(context, fakeAI(provider));
  await settle();
  return { session, host, context };
}

describe("ClaudeAskSession in a demo run", () => {
  it("opens the sample chat, lists the sample history and answers with the demo line without touching the host", async () => {
    const { app, host } = await testApp({ moduleTypes: [AskModule], runMode: DEMO_RUN_MODE }, NOW);
    const session = app.modules.get(MODULE_IDS.claudeAsk) as { session: ClaudeAskSession } | undefined;
    expect(session).toBeDefined();
    if (!session) return;
    const state = session.session.state;
    expect(state.isEmpty).toBe(false);
    expect(state.savedChats.length).toBeGreaterThan(3);
    expect(state.savedChats[0]?.id).toBe(state.chatID);
    expect(state.assistant).toBe("Claude");
    expect(state.setupNeeded).toBeUndefined();
    session.session.ask("Hello?");
    await settle();
    const last = session.session.state.messages[session.session.state.messages.length - 1];
    expect(last?.role).toBe("assistant");
    expect(last?.text).toBe(demoAnswer("Tabbi"));
    expect(last?.status).toBe("complete");
    expect(host.calls.filter((call) => call.name === "httpStream" || call.name === "storageWrite")).toEqual([]);
  });
});

describe("ClaudeAskSession in a live run", () => {
  it("shows the setup state before the first question and sends nothing while no provider is picked", async () => {
    const { session, host } = await liveSession(undefined);
    session.prepare();
    await settle();
    expect(session.state.setupNeeded).toEqual({ kind: "noProvider" });
    expect(session.state.assistant).toBe("AI");
    expect(session.state.isEmpty).toBe(true);
    session.ask("What is a mutex?");
    await settle();
    expect(session.state.phase).toEqual({ kind: "failed", failure: { kind: "noProvider" } });
    expect(host.calls.some((call) => call.name === "httpStream")).toBe(false);
    expect([...host.documents.keys()]).toEqual([]);
  });

  it("streams an answer, saves the finished exchange to the history and lists it", async () => {
    const requests: AIRequest[] = [];
    const provider = scriptedProvider(
      "anthropic",
      async function* () {
        yield { kind: "textDelta", text: "A mutex " };
        yield { kind: "textDelta", text: "locks." };
        yield { kind: "finished" };
      },
      requests,
    );
    const { session, host } = await liveSession(provider);
    session.prepare();
    await settle();
    expect(session.state.setupNeeded).toBeUndefined();
    expect(session.state.assistant).toBe("Claude");
    session.ask("  What is a mutex?  ");
    await settle(8);
    const [question, answer] = session.state.messages;
    expect(question?.text).toBe("What is a mutex?");
    expect(answer?.text).toBe("A mutex locks.");
    expect(answer?.status).toBe("complete");
    expect(answer?.provider).toBe("anthropic");
    expect(requests[0]?.system).toContain("Tabbi");
    expect(requests[0]?.messages.map((message) => message.text)).toEqual(["What is a mutex?"]);
    const saved = [...host.documents.entries()].filter(([key]) => key.startsWith("durable:Claude Chats/"));
    expect(saved).toHaveLength(1);
    const chat = decodeClaudeAskChat(saved[0]?.[1] ?? "");
    expect(chat.messages.map((message) => message.text)).toEqual(["What is a mutex?", "A mutex locks."]);
    expect(session.state.savedChats.map((entry) => entry.id)).toEqual([chat.id]);
    expect(session.state.chatID).toBe(chat.id);

    /* A follow-up sends the earlier exchange along, since an API keeps no session. */
    session.ask("And a semaphore?");
    await settle(8);
    expect(requests[1]?.messages.map((message) => message.text)).toEqual(["What is a mutex?", "A mutex locks.", "And a semaphore?"]);
  });

  it("stops an answer in progress, keeps what arrived, and starts a new chat", async () => {
    let release: (() => void) | undefined;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const provider = scriptedProvider("openai", async function* () {
      yield { kind: "textDelta", text: "Partial" };
      await gate;
      yield { kind: "textDelta", text: " and more" };
      yield { kind: "finished" };
    });
    const { session } = await liveSession(provider);
    session.ask("Go on");
    await settle(6);
    expect(session.state.isStreaming).toBe(true);
    expect(session.state.messages[1]?.text).toBe("Partial");
    session.stop();
    release?.();
    await settle(6);
    expect(session.state.isStreaming).toBe(false);
    expect(session.state.messages[1]?.status).toBe("stopped");
    expect(session.state.messages[1]?.text).toBe("Partial");
    expect(session.state.savedChats).toHaveLength(1);
    session.newChat();
    expect(session.state.isEmpty).toBe(true);
    expect(session.state.chatID).not.toBe(session.state.savedChats[0]?.id);
  });

  it("explains a failure, offers retry, and reopens, deletes and clears saved chats", async () => {
    let failing = true;
    const provider = scriptedProvider("gemini", async function* () {
      if (failing) throw new AIProviderFailure({ kind: "rateLimited" });
      yield { kind: "finished", text: "Fine now." };
    });
    const { session, host } = await liveSession(provider);
    session.ask("Hi");
    await settle(8);
    expect(session.state.phase.kind).toBe("failed");
    expect(session.state.messages[1]?.status).toBe("failed");
    expect(session.state.savedChats).toEqual([]);
    failing = false;
    session.retry();
    await settle(8);
    expect(session.state.messages.map((message) => message.text)).toEqual(["Hi", "Fine now."]);
    const first = session.state.savedChats[0];
    expect(first).toBeDefined();
    if (!first) return;

    session.newChat();
    session.ask("Second");
    await settle(8);
    expect(session.state.savedChats).toHaveLength(2);
    session.setShowingHistory(true);
    session.open(first);
    expect(session.state.isShowingHistory).toBe(false);
    expect(session.state.chatID).toBe(first.id);
    expect(session.state.messages.map((message) => message.text)).toEqual(["Hi", "Fine now."]);

    session.delete(first);
    await settle();
    expect(session.state.isEmpty).toBe(true);
    expect(session.state.savedChats).toHaveLength(1);
    session.deleteAllChats();
    await settle();
    expect(session.state.savedChats).toEqual([]);
    expect([...host.documents.keys()].filter((key) => key.startsWith("durable:Claude Chats/"))).toEqual([]);
  });
});
