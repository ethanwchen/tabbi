import { type AIKeyStore, hasKey } from "./aiKeyStore";
import { AIHTTPProvider, type AIHTTPTransport, type AIProvider } from "./aiProvider";
import { type AIProviderID, availableProviders, isCommandLineTool, requiresAPIKey } from "./aiProviderID";
import { AIProviderFailure, type AIRequest, type AIStreamEvent } from "./aiRequest";
import { type AISettings, activeProvider, modelFor } from "./aiSettings";

/** Port of AISetupState: where the user's AI setup stands, for every AI feature's setup and empty states. */
export type AISetupState =
  /** No provider picked (or the picked one can't run in this build): nothing may be sent anywhere yet. */
  | { kind: "notChosen" }
  /** The picked API provider has no saved key. */
  | { kind: "needsKey"; provider: AIProviderID }
  /** Ready to send. A command line tool may still turn out to be missing (`notInstalled`). */
  | { kind: "ready"; provider: AIProviderID };

export function setupProvider(state: AISetupState): AIProviderID | undefined {
  return state.kind === "notChosen" ? undefined : state.provider;
}

export function isSetupReady(state: AISetupState): boolean {
  return state.kind === "ready";
}

/** The setup state from the active provider and whether its key is saved; pure, for tests and the UI. */
export function resolveSetupState(active: AIProviderID | undefined, keySaved: boolean): AISetupState {
  if (active === undefined) return { kind: "notChosen" };
  if (requiresAPIKey(active) && !keySaved) return { kind: "needsKey", provider: active };
  return { kind: "ready", provider: active };
}

export interface AIProviderFactoryOptions {
  keys: AIKeyStore;
  /** True in a build that can't run command line tools (a Store build, or until the CLI providers ship). */
  sandboxed: boolean;
  transport: AIHTTPTransport;
  /** Builds a command line provider; without one, a CLI provider fails with `notInstalled`. */
  commandLine?: (id: AIProviderID) => AIProvider;
  /** Ollama's address when the user changed it. */
  ollamaBaseURL?: string;
}

/**
 * Port of AIProviderFactory: builds the provider the user picked, an
 * `AIHTTPProvider` with the saved key for an API, or Ollama on localhost.
 * The provider fills in the user's model for requests that leave it blank,
 * so features only write prompts.
 */
export class AIProviderFactory {
  constructor(private readonly options: AIProviderFactoryOptions) {}

  /** The providers to offer in this build, in picker order. */
  get availableProviders(): AIProviderID[] {
    return availableProviders(this.options.sandboxed);
  }

  async setupState(settings: AISettings): Promise<AISetupState> {
    const active = activeProvider(settings, this.options.sandboxed);
    if (active === undefined) return { kind: "notChosen" };
    return resolveSetupState(active, requiresAPIKey(active) ? await hasKey(this.options.keys, active) : true);
  }

  /**
   * The provider for `settings`, or undefined when none is picked. A
   * provider still missing its key is returned and fails with
   * `missingAPIKey`, so a feature has one error path.
   */
  async provider(settings: AISettings): Promise<AIProvider | undefined> {
    const id = activeProvider(settings, this.options.sandboxed);
    if (id === undefined) return undefined;
    let base: AIProvider;
    if (isCommandLineTool(id)) {
      base = this.options.commandLine?.(id) ?? missingTool(id);
    } else {
      const key = await this.options.keys.key(id);
      base = new AIHTTPProvider(id, key, this.options.transport, id === "ollama" ? this.options.ollamaBaseURL : undefined);
    }
    return modelDefaulting(base, modelFor(settings, id));
  }
}

/** A command line provider this build can't run yet. */
function missingTool(id: AIProviderID): AIProvider {
  return {
    id,
    stream: (): AsyncIterable<AIStreamEvent> => ({
      [Symbol.asyncIterator]: () => ({ next: () => Promise.reject(new AIProviderFailure({ kind: "notInstalled" })) }),
    }),
  };
}

/** Sends the user's model with requests that don't name one. */
function modelDefaulting(base: AIProvider, model: string): AIProvider {
  return {
    id: base.id,
    stream(request: AIRequest, signal?: AbortSignal) {
      const named = request.model.trim().length > 0 ? request : { ...request, model };
      return base.stream(named, signal);
    },
  };
}
