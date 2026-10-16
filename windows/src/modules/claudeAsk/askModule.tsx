import { aiService } from "../../app/aiService";
import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { useStore } from "../../app/useStore";
import { allAINetworkAccess } from "../../core/ai/aiProviderID";
import { tr } from "../../core/localization/tr";
import { CLAUDE_ACCENT, MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { SettingsGroup, SettingsRow } from "../../ui/kit/SettingsGroup";
import { AskPanel } from "./askPanel";
import { ClaudeAskSession } from "./askSession";

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

/** The panel's named snapshot states besides the demo chat. */
export const ASK_SNAPSHOT_STATES = ["empty", "history", "history-empty", "thinking", "streaming", "failed", "setup", "needs-key"] as const;

export const AskModule = defineModule(
  ASK_DESCRIPTOR,
  (context) => {
    const ai = aiService(context);
    const session = new ClaudeAskSession(context, ai);
    /* A new provider or key in Settings must take effect live, not on the next launch. */
    let lastAI = context.settings.current.ai;
    context.settings.settings.subscribe(() => {
      const next = context.settings.current.ai;
      if (next === lastAI) return;
      lastAI = next;
      session.prepare();
    });
    session.prepare();

    function Panel() {
      return <AskPanel session={session} context={context} />;
    }

    /* Settings > Tabs > Ask AI options: where chats are kept. The large view is not on Windows, so there is nothing else to set. */
    function SettingsPane() {
      const count = useStore(session, (state) => state.savedChats.length);
      return (
        <SettingsGroup
          title={tr("History")}
          footer={tr("Chats stay on this PC, in %@'s own folder. Delete them from History in the Ask AI tab.", context.edition.name)}
        >
          <SettingsRow label={tr("Saved chats")}>
            <span className="kit-body" style={{ fontVariantNumeric: "tabular-nums" }}>
              {new Intl.NumberFormat().format(count)}
            </span>
          </SettingsRow>
        </SettingsGroup>
      );
    }

    return {
      session,
      Panel,
      SettingsPane,
      showSnapshotState: (state: string) => session.showSnapshotState(state),
    };
  },
  { snapshotStates: ASK_SNAPSHOT_STATES },
);
