import { type AIProviderID, defaultModel, parseAIProviderID, sendsDataOffDevice, worksInSandbox } from "./aiProviderID";

/**
 * Port of AISettings: which provider answers Ask AI, Plan my day, Day review
 * and Refine, the model each provider uses, and which providers the user
 * allowed to receive their data. There is no default provider: until the
 * user picks one, every AI feature shows its setup state and nothing is
 * sent anywhere. Immutable; the update functions return a new value.
 */
export interface AISettings {
  /**
   * The provider the user picked, or undefined before they pick one. Kept
   * as saved even when this build can't use it, so going back restores it;
   * `activeProvider` decides what runs.
   */
  readonly provider?: AIProviderID;
  /** Models the user typed, per provider. Missing or blank means the default. */
  readonly models: Readonly<Partial<Record<AIProviderID, string>>>;
  /**
   * Providers the user allowed to receive their requests, after the
   * disclosure that names the provider and what is sent. A provider that
   * sends data off this PC stays inactive until it is in here.
   */
  readonly consented: ReadonlySet<AIProviderID>;
}

export function aiSettings(fields: { provider?: AIProviderID; models?: Partial<Record<AIProviderID, string>>; consented?: Iterable<AIProviderID> } = {}): AISettings {
  return {
    ...(fields.provider === undefined ? {} : { provider: fields.provider }),
    models: { ...(fields.models ?? {}) },
    consented: new Set(fields.consented ?? []),
  };
}

/** Whether picking `provider` must first ask the user's permission. */
export function needsConsent(settings: AISettings, provider: AIProviderID): boolean {
  return sendsDataOffDevice(provider) && !settings.consented.has(provider);
}

/**
 * The provider that answers in this build, or undefined when the user hasn't
 * picked one this build can run and allowed it to receive their data.
 */
export function activeProvider(settings: AISettings, sandboxed: boolean): AIProviderID | undefined {
  const provider = settings.provider;
  if (provider === undefined) return undefined;
  if (sandboxed && !worksInSandbox(provider)) return undefined;
  if (needsConsent(settings, provider)) return undefined;
  return provider;
}

/** Picks `provider` once the user has allowed it, recording the permission so it is asked once. */
export function choose(settings: AISettings, provider: AIProviderID | undefined): AISettings {
  const consented = new Set(settings.consented);
  if (provider !== undefined && sendsDataOffDevice(provider)) consented.add(provider);
  const next: AISettings = { models: settings.models, consented };
  return provider === undefined ? next : { ...next, provider };
}

/** The model to request from `provider`: the user's, or the default. */
export function modelFor(settings: AISettings, provider: AIProviderID): string {
  const typed = settings.models[provider]?.trim() ?? "";
  return typed.length === 0 ? defaultModel(provider) : typed;
}

/**
 * Records `model` for `provider`; blank or the default clears the entry, so
 * a later change of the default reaches this user too.
 */
export function setModel(settings: AISettings, model: string, provider: AIProviderID): AISettings {
  const trimmed = model.trim();
  const models = Object.fromEntries(Object.entries(settings.models).filter(([id]) => id !== provider));
  if (trimmed.length > 0 && trimmed !== defaultModel(provider)) models[provider] = trimmed;
  return { ...settings, models };
}

/** The stored form, the same keys the Mac keeps under `settings.ai.*`. */
export interface StoredAISettings {
  provider?: string;
  models?: Record<string, string>;
  consented?: string[];
}

export function encodeAISettings(settings: AISettings): StoredAISettings {
  const stored: StoredAISettings = { models: { ...settings.models }, consented: [...settings.consented].sort() };
  if (settings.provider !== undefined) stored.provider = settings.provider;
  return stored;
}

/** Reads stored settings leniently: unknown providers (from a newer build) are dropped. */
export function decodeAISettings(stored: StoredAISettings | undefined): AISettings {
  const models: Partial<Record<AIProviderID, string>> = {};
  for (const [key, value] of Object.entries(stored?.models ?? {})) {
    const id = parseAIProviderID(key);
    if (id !== undefined && typeof value === "string") models[id] = value;
  }
  const consented = (stored?.consented ?? []).flatMap((value) => parseAIProviderID(value) ?? []);
  return aiSettings({ provider: parseAIProviderID(stored?.provider), models, consented });
}
