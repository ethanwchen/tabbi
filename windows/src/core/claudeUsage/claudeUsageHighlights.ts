import type { AIProviderID } from "../ai/aiProviderID";
import type { ClaudeRateLimitSnapshot, ClaudeUsageWindow } from "../claude/claudeStreamEvent";
import { MODULE_IDS, type ModuleID } from "../modules/moduleId";
import { TickerHighlight } from "../providers/tickerHighlight";
import type { Instant } from "../time";
import { percentText } from "./claudeUsageFormat";

/**
 * Port of AIUsageSource: whose local logs the Usage tab reads. Only Claude
 * Code and the Codex CLI keep usage on this PC, so the tab follows the
 * chosen AI when it is Codex and stays on Claude Code otherwise.
 */
export type AIUsageSource = "claudeCode" | "codex";

export function usageSourceFor(provider: AIProviderID | undefined): AIUsageSource {
  return provider === "codex-cli" ? "codex" : "claudeCode";
}

/** The tool's name in the panel, e.g. "Codex not found". */
export function usageToolName(source: AIUsageSource): string {
  return source === "codex" ? "Codex" : "Claude Code";
}

/** The plan's name in the ticker tooltip, e.g. "Codex usage 5h 86%". */
export function usageName(source: AIUsageSource): string {
  return source === "codex" ? "Codex usage" : "Claude usage";
}

/** Whether limits come from a live probe that spends a sliver of the plan, rather than from logs. */
export function probesLimits(source: AIUsageSource): boolean {
  return source === "claudeCode";
}

/** Usage only surfaces once a window is above this fraction. */
export const HIGHLIGHT_THRESHOLD = 0.8;

export type UsageWindowKind = "fiveHour" | "weekly";

/** Short label for the notch, e.g. "5h". */
export function windowLabel(window: UsageWindowKind): string {
  return window === "fiveHour" ? "5h" : "Week";
}

/** The highlight for one window at `utilization`. */
export function usageHighlight(
  window: UsageWindowKind,
  utilization: number,
  resetsAt?: Instant,
  source: ModuleID = MODULE_IDS.claudeUsage,
  usage: AIUsageSource = "claudeCode",
): TickerHighlight {
  const text = `${windowLabel(window)} ${percentText(utilization)}`;
  return new TickerHighlight({
    id: window,
    source,
    text,
    summary: `${usageName(usage)} ${text}`,
    tone: utilization >= 1 ? "danger" : "accent",
    /* Per mille, doubled so the 5-hour window wins a tie: it resets sooner and the user can act on it. */
    priority: Math.round(utilization * 1000) * 2 + (window === "fiveHour" ? 1 : 0),
    isPinned: false,
    expiresAt: resetsAt,
  });
}

/**
 * Port of ClaudeUsageHighlights: one highlight per window above the
 * threshold, each expiring when its window resets. Empty when no window is
 * above the threshold or every such window has reset.
 */
export function usageHighlights(
  snapshot: ClaudeRateLimitSnapshot | undefined,
  now: Instant,
  source: ModuleID = MODULE_IDS.claudeUsage,
  usage: AIUsageSource = "claudeCode",
): TickerHighlight[] {
  const windows: [UsageWindowKind, ClaudeUsageWindow | undefined][] = [
    ["fiveHour", snapshot?.fiveHour],
    ["weekly", snapshot?.sevenDay],
  ];
  return windows.flatMap(([window, value]) => {
    if (!value || value.utilization <= HIGHLIGHT_THRESHOLD) return [];
    if (value.resetsAt !== undefined && value.resetsAt <= now) return [];
    return [usageHighlight(window, value.utilization, value.resetsAt, source, usage)];
  });
}
