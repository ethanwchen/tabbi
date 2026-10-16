/*
 * Port of AIService (Modules/AI/ on the Mac): the one AI provider the user
 * picked in Settings > Connections, shared by Ask AI, Plan my day, Day
 * review and the Schedule's Refine. Nothing is sent before a provider is
 * picked: features ask `readyProvider()` and show the shared setup state
 * when it is undefined. Keys live in Windows Credential Manager through the
 * host; demo and snapshot runs keep them in memory and send nothing.
 *
 * The command line providers (claude, codex, gemini) are not offered yet,
 * so the factory runs as a sandboxed build would: APIs and Ollama only.
 */

import { cleanedKey, InMemoryAIKeyStore, type AIKeyStore } from "../core/ai/aiKeyStore";
import type { AIHTTPTransport, AIProvider } from "../core/ai/aiProvider";
import { AIProviderFactory, type AISetupState } from "../core/ai/aiProviderFactory";
import type { AIProviderID } from "../core/ai/aiProviderID";
import type { AISettings } from "../core/ai/aiSettings";
import { isEphemeral } from "../core/modules/runMode";
import type { Host, HttpStreamEvent } from "../host/host";
import type { ModuleContext } from "./context";
import { serviceKey } from "./sharedServices";

/** The user's API keys in Credential Manager, one generic credential per provider (`Tabbi/ai/<provider>`). */
export function hostAIKeyStore(host: Pick<Host, "credentialGet" | "credentialSet" | "credentialDelete">): AIKeyStore {
  return {
    async key(provider: AIProviderID) {
      return cleanedKey((await host.credentialGet(`ai/${provider}`)) ?? undefined);
    },
    async setKey(key: string | undefined, provider: AIProviderID) {
      const cleaned = cleanedKey(key);
      if (cleaned === undefined) await host.credentialDelete(`ai/${provider}`);
      else await host.credentialSet(`ai/${provider}`, cleaned);
    },
  };
}

/**
 * The AI providers' streamed requests through the host, which allows only
 * the listed services. Resolves once the response head is in, then yields
 * the body as it arrives.
 */
export function hostAITransport(host: Pick<Host, "httpStream">): AIHTTPTransport {
  return (request, signal) =>
    new Promise((resolve, reject) => {
      const chunks: string[] = [];
      let done = false;
      let failure: unknown;
      let wake: (() => void) | undefined;
      let headed = false;
      const notify = () => {
        wake?.();
        wake = undefined;
      };
      async function* body(): AsyncGenerator<string> {
        for (;;) {
          const next = chunks.shift();
          if (next !== undefined) {
            yield next;
            continue;
          }
          if (failure !== undefined) throw failure;
          if (done) return;
          await new Promise<void>((resume) => {
            wake = resume;
          });
        }
      }
      const onEvent = (event: HttpStreamEvent) => {
        switch (event.type) {
          case "head":
            headed = true;
            resolve({ status: event.status, chunks: body() });
            return;
          case "chunk":
            chunks.push(event.text);
            return notify();
          case "end":
            done = true;
            return notify();
          case "error":
            if (!headed) reject(event.error);
            failure = event.error;
            return notify();
        }
      };
      host
        .httpStream({ method: request.method, url: request.url, headers: Object.entries(request.headers), body: request.body }, onEvent)
        .then((stream) => {
          if (signal?.aborted) void stream.cancel();
          else signal?.addEventListener("abort", () => void stream.cancel(), { once: true });
        })
        .catch(reject);
    });
}

export class AIService {
  constructor(
    private readonly factory: AIProviderFactory,
    /** Reads the AI settings now. */
    private readonly settings: () => AISettings,
    /** Where the user's keys live. */
    readonly keys: AIKeyStore,
  ) {}

  /** Where the user's AI setup stands, for every AI feature's setup and empty states. */
  setupState(): Promise<AISetupState> {
    return this.factory.setupState(this.settings());
  }

  /** The providers this build offers, in picker order. */
  get availableProviders(): AIProviderID[] {
    return this.factory.availableProviders;
  }

  /** The picked provider when it can send now, or undefined (nothing picked, or its key missing). */
  async readyProvider(): Promise<AIProvider | undefined> {
    const state = await this.setupState();
    return state.kind === "ready" ? this.factory.provider(this.settings()) : undefined;
  }
}

const AI_SERVICE = serviceKey<AIService>("app.ai");

/** The one AIService, over the host in a live run and in memory in demo and snapshot runs. */
export function aiService(context: ModuleContext): AIService {
  return context.shared.resolve(AI_SERVICE, () => {
    const ephemeral = isEphemeral(context.runMode);
    const keys = ephemeral ? new InMemoryAIKeyStore() : hostAIKeyStore(context.host);
    const transport: AIHTTPTransport = ephemeral
      ? () => Promise.reject(new Error("Demo and snapshot runs send nothing"))
      : hostAITransport(context.host);
    const factory = new AIProviderFactory({ keys, sandboxed: true, transport });
    return new AIService(factory, () => context.settings.current.ai, keys);
  });
}
