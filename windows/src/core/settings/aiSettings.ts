/**
 * A narrow stand-in for the AI area's AIProviderID and AISettings, which the
 * AI port owns: only what Settings stores. API keys never live here.
 */
export type AIProviderID = "claude-cli" | "codex-cli" | "gemini-cli" | "anthropic" | "openai" | "gemini" | "ollama";

export const AI_PROVIDER_IDS: readonly AIProviderID[] = [
  "claude-cli",
  "codex-cli",
  "gemini-cli",
  "anthropic",
  "openai",
  "gemini",
  "ollama",
];

export function isAIProviderID(value: unknown): value is AIProviderID {
  return typeof value === "string" && (AI_PROVIDER_IDS as readonly string[]).includes(value);
}

export interface AISettings {
  /** The provider the user picked, or undefined before they pick one. */
  readonly provider?: AIProviderID;
  /** Models the user typed, per provider; a missing entry means the provider's default. */
  readonly models: Readonly<Partial<Record<AIProviderID, string>>>;
  /** Providers the user allowed to receive their requests. */
  readonly consented: ReadonlySet<AIProviderID>;
}

export const DEFAULT_AI_SETTINGS: AISettings = { models: {}, consented: new Set() };
