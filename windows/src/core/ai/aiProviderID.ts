import { tr } from "../localization/tr";

/**
 * Port of AIProviderID: one way Tabbi can reach a language model for Ask AI,
 * Plan my day, Day review and the Schedule's Refine. Three are command line
 * tools the user signed in to, three are hosted APIs called with the user's
 * own key, and Ollama runs models on this PC. Nothing is sent anywhere until
 * the user picks one. The raw values are shared with the Mac's settings.
 */
export const AI_PROVIDER_IDS = ["claude-cli", "codex-cli", "gemini-cli", "anthropic", "openai", "gemini", "ollama"] as const;
export type AIProviderID = (typeof AI_PROVIDER_IDS)[number];

/** Reads a stored id leniently: an id this build doesn't know (from a newer one) is undefined. */
export function parseAIProviderID(value: unknown): AIProviderID | undefined {
  return AI_PROVIDER_IDS.find((id) => id === value);
}

/**
 * How Tabbi talks to the provider, which decides what setup it needs and
 * whether a sandboxed (Store) build can use it.
 */
export type AITransport =
  /** A local command line tool, found on disk and run as a process. */
  | { kind: "cli"; executable: string }
  /** A hosted HTTPS API that takes the user's key. */
  | { kind: "api" }
  /** A server on this PC (Ollama), reached over localhost. */
  | { kind: "local" };

export function aiTransport(id: AIProviderID): AITransport {
  switch (id) {
    case "claude-cli":
      return { kind: "cli", executable: "claude" };
    case "codex-cli":
      return { kind: "cli", executable: "codex" };
    case "gemini-cli":
      return { kind: "cli", executable: "gemini" };
    case "anthropic":
    case "openai":
    case "gemini":
      return { kind: "api" };
    case "ollama":
      return { kind: "local" };
  }
}

/** The name shown in Settings and beside "Ask AI". */
export function displayName(id: AIProviderID): string {
  switch (id) {
    case "claude-cli":
      return "Claude Code";
    case "codex-cli":
      return "Codex CLI";
    case "gemini-cli":
      return "Gemini CLI";
    case "anthropic":
      return "Claude API";
    case "openai":
      return "OpenAI API";
    case "gemini":
      return "Gemini API";
    case "ollama":
      return "Ollama";
  }
}

/** The assistant's name in running text ("Ask Claude"), the same for the CLI and the API of one vendor. */
export function assistantName(id: AIProviderID): string {
  switch (id) {
    case "claude-cli":
    case "anthropic":
      return "Claude";
    case "codex-cli":
      return "Codex";
    case "openai":
      return "OpenAI";
    case "gemini-cli":
    case "gemini":
      return "Gemini";
    case "ollama":
      return "Ollama";
  }
}

/** A one-line note for the provider picker on cost and setup. */
export function setupSummary(id: AIProviderID): string {
  switch (id) {
    case "claude-cli":
      return tr("Uses your Claude subscription through the claude command.");
    case "codex-cli":
      return tr("Uses your ChatGPT plan through the codex command.");
    case "gemini-cli":
      return tr("Free with a Google account through the gemini command.");
    case "anthropic":
      return tr("Pay as you go with an Anthropic API key.");
    case "openai":
      return tr("Pay as you go with an OpenAI API key.");
    case "gemini":
      return tr("Free tier with a Google AI Studio key.");
    case "ollama":
      return tr("Free and offline: runs a model on this Mac.");
  }
}

/**
 * The official page with what setup needs: the API key page for a hosted
 * API, the install page for a tool or Ollama. Opened in the browser, never
 * fetched by Tabbi.
 */
export function setupPage(id: AIProviderID): string {
  switch (id) {
    case "claude-cli":
      return "https://docs.anthropic.com/en/docs/claude-code/setup";
    case "codex-cli":
      return "https://github.com/openai/codex";
    case "gemini-cli":
      return "https://github.com/google-gemini/gemini-cli";
    case "anthropic":
      return "https://console.anthropic.com/settings/keys";
    case "openai":
      return "https://platform.openai.com/api-keys";
    case "gemini":
      return "https://aistudio.google.com/apikey";
    case "ollama":
      return "https://ollama.com/download";
  }
}

/** The button that opens `setupPage`. */
export function setupPageTitle(id: AIProviderID): string {
  return requiresAPIKey(id) ? tr("Get a Key") : tr("Install");
}

/** Where a provider's command line tool stands, which decides the setup hint. */
export type AIToolLookup =
  /** Still looking. */
  | { kind: "looking" }
  /** Not found anywhere Tabbi looks. */
  | { kind: "missing" }
  /** Found at this path, which a hint names in full. */
  | { kind: "found"; path: string };

/**
 * The next step for providers whose setup is more than a key: a command line
 * tool needs installing and signing in once, Ollama needs the model pulled
 * once. It never tells the user to type a tool's bare name, since a found
 * tool may still be missing from a fresh terminal's PATH: it names the full
 * path. `showGuideTitle` is the title of the Claude row's guide button
 * ("Show me how").
 */
export function setupHint(id: AIProviderID, model: string, tool: AIToolLookup, showGuideTitle = tr("Show me how")): string | undefined {
  if (requiresAPIKey(id)) return undefined;
  if (id === "ollama") return tr("With Ollama open, run ollama pull %@ in Terminal once.", model);
  if (tool.kind === "looking") return undefined;
  if (id === "claude-cli") {
    return tool.kind === "missing"
      ? tr("To install it, click %@ on the Claude row below.", showGuideTitle)
      : tr("The Claude row below shows how to sign in, if you still need to.");
  }
  if (tool.kind === "missing") return tr("Click %@ for the official steps, then come back here.", setupPageTitle(id));
  if (id === "codex-cli") return tr("To sign in, run %@ in Terminal once.", commandLine(tool.path, ["login"]));
  return tr("To sign in with Google, run %@ in Terminal once.", commandLine(tool.path));
}

/**
 * Port of ShellCommandLine.running: a line to paste into a terminal that runs
 * a tool by its full path, each word quoted only when it needs to be.
 */
export function commandLine(executable: string, args: readonly string[] = []): string {
  return [executable, ...args].map(quotedWord).join(" ");
}

/** One word as a shell reads it back unchanged: as is when plain, otherwise in single quotes. */
export function quotedWord(word: string): string {
  if (word.length === 0) return "''";
  if (/^[A-Za-z0-9/._\-+:@%,]+$/.test(word)) return word;
  return "'" + word.replaceAll("'", "'\\''") + "'";
}

export function requiresAPIKey(id: AIProviderID): boolean {
  return aiTransport(id).kind === "api";
}

export function isCommandLineTool(id: AIProviderID): boolean {
  return aiTransport(id).kind === "cli";
}

/**
 * Whether a sandboxed (Store) build can use it: a sandboxed app can't run
 * the user's command line tools, but it can make network requests,
 * localhost included.
 */
export function worksInSandbox(id: AIProviderID): boolean {
  return !isCommandLineTool(id);
}

/**
 * The model a new user gets: fast and inexpensive, good enough for a quick
 * question and a day plan. Empty means the CLI's own default. The same ids
 * as the Mac, so a model setting means the same thing on both.
 */
export function defaultModel(id: AIProviderID): string {
  switch (id) {
    case "claude-cli":
      return "sonnet";
    case "codex-cli":
    case "gemini-cli":
      return "";
    case "anthropic":
      return "claude-sonnet-5-5";
    case "openai":
      return "gpt-5-mini";
    case "gemini":
      /* Google's alias for the newest Flash model, which the free tier covers. */
      return "gemini-flash-latest";
    case "ollama":
      return "llama3.2";
  }
}

/** A host a module's code connects to, and what for (the Mac's ModuleNetworkAccess). */
export interface AINetworkAccess {
  host: string;
  purpose: string;
}

/** True for a service on this PC, which sends nothing off the machine. */
export function isLocalHost(access: AINetworkAccess): boolean {
  return ["localhost", "127.0.0.1", "::1"].includes(access.host.toLowerCase());
}

/** The host the app connects to for this provider; command line tools make their own connections. */
export function networkAccess(id: AIProviderID): AINetworkAccess | undefined {
  switch (id) {
    case "claude-cli":
    case "codex-cli":
    case "gemini-cli":
      return undefined;
    case "anthropic":
      return { host: "api.anthropic.com", purpose: "answers from Claude with your API key" };
    case "openai":
      return { host: "api.openai.com", purpose: "answers from OpenAI with your API key" };
    case "gemini":
      return { host: "generativelanguage.googleapis.com", purpose: "answers from Gemini with your API key" };
    case "ollama":
      return { host: "localhost", purpose: "answers from a model Ollama runs on this PC" };
  }
}

/** Every host an AI feature may connect to, for module descriptors. */
export function allAINetworkAccess(): AINetworkAccess[] {
  return AI_PROVIDER_IDS.flatMap((id) => networkAccess(id) ?? []);
}

/** The providers this build can offer, in picker order. */
export function availableProviders(sandboxed: boolean): AIProviderID[] {
  return AI_PROVIDER_IDS.filter((id) => !sandboxed || worksInSandbox(id));
}

/* Port of AIConsent: the one-time disclosure before a provider that sends data off this PC is picked. */

/** Whether requests leave this PC. Ollama answers on localhost, so it needs no permission. */
export function sendsDataOffDevice(id: AIProviderID): boolean {
  return aiTransport(id).kind !== "local";
}

/** The company that receives requests, named in the disclosure; undefined for Ollama. */
export function vendorName(id: AIProviderID): string | undefined {
  switch (id) {
    case "claude-cli":
    case "anthropic":
      return "Anthropic";
    case "codex-cli":
    case "openai":
      return "OpenAI";
    case "gemini-cli":
    case "gemini":
      return "Google";
    case "ollama":
      return undefined;
  }
}

/** The disclosure's title, e.g. "Send your AI requests to Anthropic?". */
export function consentTitle(id: AIProviderID): string {
  return tr("Send your AI requests to %@?", vendorName(id) ?? displayName(id));
}

/**
 * The disclosure's body: the provider, what each feature sends, and whose
 * terms apply. Each line is its own string, so a translation keeps the
 * list's shape.
 */
export function consentMessage(id: AIProviderID, appName: string): string {
  const vendor = vendorName(id) ?? displayName(id);
  const name = displayName(id);
  const intro = isCommandLineTool(id)
    ? tr("With %@, %@ sends these to %@ through the %@ command you signed in to when you use an AI feature:", name, appName, vendor, name)
    : tr("With %@, %@ sends these to %@ with your API key when you use an AI feature:", name, appName, vendor);
  return [
    intro,
    tr("Ask AI: your questions, the chat so far and any screenshot you attach."),
    tr("Refine and AI day plans: your calendar event titles and times, tasks, goals and the plan."),
    tr(
      "Day review: today's focus and study minutes, sessions and points, your goal counts and the titles of the tasks you finished or are carrying over.",
    ),
    tr(
      "%@ handles them under its own terms and privacy policy. %@'s AI features send nothing else, and nothing until you allow it. You can switch to None in Connections at any time.",
      vendor,
      appName,
    ),
  ].join("\n");
}
