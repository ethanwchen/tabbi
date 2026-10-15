import type { AIProviderID } from "./aiProviderID";

/**
 * Port of AIKeyStore: keeps the user's API keys for the hosted providers.
 * Keys never go into settings or a file: the app keeps them in Windows
 * Credential Manager through the host (one generic credential per provider
 * under a `Tabbi/` target), and tests, demo mode and snapshots keep them in
 * memory. Async, because the host answers over IPC.
 */
export interface AIKeyStore {
  key(provider: AIProviderID): Promise<string | undefined>;
  /** Saves `key` for `provider`; undefined or blank deletes it. */
  setKey(key: string | undefined, provider: AIProviderID): Promise<void>;
}

/** Trims a pasted key; blank is no key. */
export function cleanedKey(key: string | undefined): string | undefined {
  const trimmed = key?.trim();
  return trimmed ? trimmed : undefined;
}

export async function hasKey(store: AIKeyStore, provider: AIProviderID): Promise<boolean> {
  return (await store.key(provider)) !== undefined;
}

/** The Credential Manager target the host keeps `provider`'s key under, e.g. `Tabbi/ai/anthropic`. */
export function credentialTarget(provider: AIProviderID, prefix = "Tabbi"): string {
  return `${prefix}/ai/${provider}`;
}

/** Keeps keys in memory only: for tests, demo mode and snapshots, which must never touch the user's credentials. */
export class InMemoryAIKeyStore implements AIKeyStore {
  private readonly keys = new Map<AIProviderID, string>();

  constructor(initial: Partial<Record<AIProviderID, string>> = {}) {
    for (const [provider, key] of Object.entries(initial) as [AIProviderID, string | undefined][]) {
      const cleaned = cleanedKey(key);
      if (cleaned !== undefined) this.keys.set(provider, cleaned);
    }
  }

  async key(provider: AIProviderID): Promise<string | undefined> {
    return this.keys.get(provider);
  }

  async setKey(key: string | undefined, provider: AIProviderID): Promise<void> {
    const cleaned = cleanedKey(key);
    if (cleaned === undefined) this.keys.delete(provider);
    else this.keys.set(provider, cleaned);
  }
}
