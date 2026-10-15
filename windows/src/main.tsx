import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import type { Host } from "./host/host";
import { mockHost } from "./host/mock";
import { insideTauri, tauriHost } from "./host/tauri";
import { Island } from "./ui/Island";
import { initialState, NOTCH_MODES, type NotchMode, type ShellState } from "./ui/shell/machine";
import { loadLanguage } from "./i18n/strings";
import { applyTheme } from "./ui/theme";
import "./ui/island.css";

interface Setup {
  readonly host: Host;
  readonly initial: ShellState;
  readonly still: boolean;
  readonly tab?: string;
}

/*
 * Outside the app (the Vite dev server and the Playwright snapshot runs) the
 * island runs on the mock host, and the query string picks the state to draw:
 * ?phase=open&tab=planner, ?phase=pill&hover, ?mode=alwaysVisible, plus
 * ?still to skip motion, ?backdrop to paint a desktop behind it, and
 * ?lang=de to render another language.
 */
function browserSetup(): Setup {
  const query = new URLSearchParams(window.location.search);
  const mode = query.get("mode");
  const base = initialState(NOTCH_MODES.includes(mode as NotchMode) ? (mode as NotchMode) : "auto");
  const phase = query.get("phase");
  let initial = base;
  if (phase === "open") initial = { ...base, phase: "open", source: "tray", focused: true };
  if (phase === "pill") initial = { ...base, mode: "alwaysVisible", phase: "pill", pillHovered: query.has("hover") };
  if (query.has("backdrop")) document.body.dataset.backdrop = "";
  return { host: mockHost(), initial, still: query.has("still"), tab: query.get("tab") ?? undefined };
}

applyTheme(document.documentElement);

const setup: Setup = insideTauri() ? { host: tauriHost(), initial: initialState(), still: false } : browserSetup();

/* The language comes first, so the first frame is already in it (and mirrored for Arabic). */
const override = insideTauri() ? null : new URLSearchParams(window.location.search).get("lang");
const { language, direction } = await loadLanguage(override ? [override] : navigator.languages);
document.documentElement.lang = language;
document.documentElement.dir = direction;

const root = document.getElementById("root");
if (!root) throw new Error("index.html has no #root");

createRoot(root).render(
  <StrictMode>
    <Island host={setup.host} initial={setup.initial} still={setup.still} initialTab={setup.tab} />
  </StrictMode>,
);
