import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { tr } from "../../core/localization/tr";
import { CLAUDE_ACCENT, MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { placeholderPanel } from "../placeholderPanel";

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

export const ClaudeUsageModule = defineModule(CLAUDE_USAGE_DESCRIPTOR, () => ({
  Panel: placeholderPanel(CLAUDE_USAGE_DESCRIPTOR),
}));
