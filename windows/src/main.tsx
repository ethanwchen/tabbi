/*
 * Starts one of Tabbi's windows. Inside the app the Tauri window's label
 * says which: the island (which runs the modules) or Settings (which only
 * draws their settings). Outside the app (the Vite dev server and the
 * Playwright snapshot runs) the page runs on the mock host with demo data,
 * and the query string picks what to draw:
 *
 * - `?phase=open&tab=planner`, `?phase=pill&hover`, `?mode=alwaysVisible`,
 *   plus `?still` (no motion) and `?backdrop` (a desktop color behind it);
 * - `?window=settings&section=look` for the Settings window;
 * - `?snapshot=<state>` for the snapshot harness (ui/shell/snapshot/);
 * - `?lang=de`, `?theme=cozy`, `?size=large`, `?kit=medicine`, `?reduce`, and
 *   for snapshots `?all` (every module on) and `?more` (the overflow list open).
 */

import { StrictMode, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { AppServices } from "./app/appServices";
import { tr } from "./core/localization/tr";
import { DEMO_RUN_MODE, type RunMode } from "./core/modules/runMode";
import { findTheme } from "./core/themes/themeCatalog";
import { isPanelSize } from "./core/settings/panelSize";
import type { Host, Startup } from "./host/host";
import { MOCK_STARTUP, mockHost } from "./host/mock";
import { insideTauri, tauriHost, tauriWindowLabel } from "./host/tauri";
import { loadLanguage } from "./i18n/strings";
import { MODULE_LIST } from "./modules/moduleList";
import { Island } from "./ui/Island";
import { initialState, NOTCH_MODES, type NotchMode, type ShellState } from "./ui/shell/machine";
import { clearTextWidths } from "./ui/shell/measure";
import { SettingsWindow } from "./ui/shell/settings/SettingsWindow";
import { prepareSnapshot, SnapshotView } from "./ui/shell/snapshot/SnapshotView";
import { parseSnapshot } from "./ui/shell/snapshot/snapshotPlan";
import { ThemedRoot } from "./ui/shell/ThemedRoot";
import "./ui/kit/kit.css";
import "./ui/shell/shell.css";

const query = new URLSearchParams(window.location.search);
const inApp = insideTauri();
const role = inApp ? (tauriWindowLabel() === "settings" ? "settings" : "island") : query.get("window") === "settings" ? "settings" : "island";
const host: Host = inApp ? tauriHost() : mockHost({ ...MOCK_STARTUP, demo: true });
document.body.dataset.window = role;
if (!inApp && query.has("backdrop")) document.body.dataset.backdrop = "";

/* The language comes first, so the first frame is already in it (and mirrored for Arabic). */
const override = inApp ? null : query.get("lang");
const { language, direction } = await loadLanguage(override ? [override] : navigator.languages);
document.documentElement.lang = language;
document.documentElement.dir = direction;
/* Measured widths (the title, the pill's wings) were taken before the fonts loaded. */
void document.fonts?.ready.then(clearTextWidths);

const root = document.getElementById("root");
if (!root) throw new Error("index.html has no #root");
const render = (node: ReactNode) => createRoot(root).render(<StrictMode>{node}</StrictMode>);

/** Settings the browser runs start from: the query's theme, panel size and kit. */
function browserSettings(): Record<string, unknown> {
  const entries: Record<string, unknown> = {};
  const theme = findTheme(query.get("theme") ?? "");
  if (theme) entries["settings.theme"] = theme.id;
  const size = query.get("size");
  if (isPanelSize(size)) entries["settings.panelSize"] = size;
  const kit = query.get("kit");
  if (kit) entries["settings.kit"] = kit;
  return entries;
}

async function services(startup: Startup, runMode?: RunMode): Promise<AppServices> {
  return AppServices.create({
    host,
    startup,
    moduleTypes: MODULE_LIST,
    role,
    ...(runMode === undefined ? {} : { runMode }),
    ...(inApp ? {} : { settingsEntries: browserSettings() }),
  });
}

function browserIsland(): { initial: ShellState; still: boolean; tab: string | undefined } {
  const mode = query.get("mode");
  const base = initialState(NOTCH_MODES.includes(mode as NotchMode) ? (mode as NotchMode) : "auto");
  const phase = query.get("phase");
  let initial = base;
  if (phase === "open") initial = { ...base, phase: "open", source: "tray", focused: true };
  if (phase === "pill") initial = { ...base, mode: "alwaysVisible", phase: "pill", pillHovered: query.has("hover") };
  return { initial, still: query.has("still"), tab: query.get("tab") ?? undefined };
}

const snapshot = inApp ? undefined : query.get("snapshot");
const reduce = query.has("reduce") ? true : undefined;

if (snapshot !== null && snapshot !== undefined) {
  const plan = parseSnapshot(snapshot);
  if (plan === undefined) throw new Error(`Unknown snapshot state "${snapshot}"`);
  const app = await services({ ...MOCK_STARTUP, demo: true }, { isDemo: true, isSnapshot: true });
  prepareSnapshot(app, plan, { allModules: query.has("all") });
  render(
    <ThemedRoot settings={app.settings} still reduceMotion={reduce}>
      <SnapshotView plan={plan} app={app} host={host} locale={language} showsMore={query.has("more")} />
    </ThemedRoot>,
  );
} else if (role === "settings") {
  const launch = await host.settingsReady();
  const app = await services(launch.startup, inApp ? undefined : DEMO_RUN_MODE);
  document.title = tr("Tabbi Settings");
  if (inApp) void import("@tauri-apps/api/window").then(({ getCurrentWindow }) => getCurrentWindow().setTitle(document.title));
  render(
    <ThemedRoot settings={app.settings} reduceMotion={reduce}>
      <SettingsWindow app={app} host={host} initialSection={launch.section ?? query.get("section")} />
    </ThemedRoot>,
  );
} else {
  /* The island's region is empty until the machine shapes it, so asking for the startup values first shows nothing early. */
  const startup = await host.ready();
  const app = await services(startup);
  const browser = inApp ? undefined : browserIsland();
  render(
    <ThemedRoot settings={app.settings} still={browser?.still ?? false} reduceMotion={reduce}>
      <Island app={app} host={host} initial={browser?.initial ?? initialState()} still={browser?.still ?? false} initialTab={browser?.tab} locale={language} />
    </ThemedRoot>,
  );
}
