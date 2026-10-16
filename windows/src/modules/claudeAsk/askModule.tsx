import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { allAINetworkAccess } from "../../core/ai/aiProviderID";
import { tr } from "../../core/localization/tr";
import { CLAUDE_ACCENT, MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { placeholderPanel } from "../placeholderPanel";

/* Port of AskClaudeModule: a quick question to the AI the user picked in Settings > Connections. */
export const ASK_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.claudeAsk,
    title: "Ask AI",
    symbol: "sparkles",
    category: MODULE_CATEGORIES.ai,
    accent: CLAUDE_ACCENT,
    network: allAINetworkAccess(),
  },
  {
    title: () => tr("Ask AI"),
    summary: () => tr("Ask Claude, Gemini or another AI a quick question."),
  },
);

export const AskModule = defineModule(ASK_DESCRIPTOR, () => ({
  Panel: placeholderPanel(ASK_DESCRIPTOR),
}));
