import { aiService } from "../../app/aiService";
import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { mapped } from "../../app/store";
import { usageHighlights } from "../../core/claudeUsage/claudeUsageHighlights";
import { tr } from "../../core/localization/tr";
import { CLAUDE_ACCENT, MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { moduleProvision } from "../../core/providers/moduleProvision";
import { ClaudeUsagePanel } from "./claudeUsagePanel";
import { ClaudeUsageStore } from "./claudeUsageStore";

/* Port of ClaudeUsageModule: how much of the Claude or Codex plan is used, read from the command line tools' own files. */
export const CLAUDE_USAGE_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.claudeUsage,
    title: "AI Usage",
    symbol: "gauge.with.dots.needle.67percent",
    category: MODULE_CATEGORIES.ai,
    accent: CLAUDE_ACCENT,
    permissions: ["claudeCLI"],
    highlightTitle: "AI usage above 80%",
  },
  {
    title: () => tr("AI Usage"),
    summary: () => tr("How much of your Claude or Codex plan you have used."),
    highlightTitle: () => tr("AI usage above 80%"),
  },
);

/** The panel's named snapshot states besides the Claude Code demo. */
export const CLAUDE_USAGE_SNAPSHOT_STATES = ["codex", "missing", "loading", "no-limits", "critical"] as const;

export const ClaudeUsageModule = defineModule(
  CLAUDE_USAGE_DESCRIPTOR,
  (context) => {
    const ai = aiService(context);
    const store = new ClaudeUsageStore(context);
    /* The tab follows the chosen AI: Codex shows its own logs. A new pick in Settings takes effect live. */
    const follow = () => void ai.setupState().then((state) => store.followSetup(state), () => undefined);
    if (!context.isDemo) {
      follow();
      let lastAI = context.settings.current.ai;
      context.settings.settings.subscribe(() => {
        const next = context.settings.current.ai;
        if (next === lastAI) return;
        lastAI = next;
        follow();
      });
    }

    function Panel() {
      return <ClaudeUsagePanel store={store} context={context} />;
    }

    return {
      store,
      Panel,
      /* A rate-limit window above 80% for the closed island's ticker. */
      provision: mapped(store, (state) => moduleProvision({ highlights: usageHighlights(state.limits?.snapshot, context.now(), context.id, state.source) })),
      showSnapshotState: (state: string) => store.showSnapshotState(state),
    };
  },
  { snapshotStates: CLAUDE_USAGE_SNAPSHOT_STATES },
);
