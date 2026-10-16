import { tr } from "../localization/tr";
import { MODULE_IDS, type ModuleID } from "../modules/moduleId";
import { ankiDiagnosis } from "./ankiConnection";
import { calendarDiagnosis } from "./calendarConnection";
import { claudeDiagnosis } from "./claudeConnection";
import type { ConnectionDiagnosis } from "./connectionDiagnosis";
import type { ConnectionStatus } from "./connectionStatus";
import { doNotDisturbDiagnosis } from "./doNotDisturbConnection";
import { mediaAppsDiagnosis, spotifyDiagnosis } from "./musicConnection";
import { notificationsDiagnosis } from "./notificationsConnection";
import { partyDiagnosis } from "./partyConnection";

/*
 * Port of ConnectionKind: one row in Settings > Connections, an app or
 * setting some tabs need. Each kind names the modules it serves, so
 * Connections lists only what the current tabs use, in this order.
 *
 * On Windows `music` is the system's media controls (any app's media
 * session) instead of Apple Music, and `doNotDisturb` stays as a row that
 * says Windows can't switch it for Tabbi.
 */

export const CONNECTION_KINDS = ["calendar", "anki", "spotify", "music", "notifications", "doNotDisturb", "claude", "party"] as const;
export type ConnectionKind = (typeof CONNECTION_KINDS)[number];

/** The row's name. */
export function connectionTitle(kind: ConnectionKind): string {
  switch (kind) {
    case "calendar":
      return tr("Calendar");
    case "anki":
      return "Anki";
    case "spotify":
      return "Spotify";
    case "music":
      return tr("Media apps");
    case "notifications":
      return tr("Alerts");
    case "doNotDisturb":
      return tr("Do not disturb");
    case "claude":
      return "Claude";
    case "party":
      return tr("Party");
  }
}

/** An SF Symbol name for the row, as the Mac names it (core/symbols draws it). */
export function connectionSymbol(kind: ConnectionKind): string {
  switch (kind) {
    case "calendar":
      return "calendar";
    case "anki":
      return "rectangle.stack.fill";
    case "spotify":
      return "music.note";
    case "music":
      return "music.note.list";
    case "notifications":
      return "bell.badge.fill";
    case "doNotDisturb":
      return "moon.fill";
    case "claude":
      return "sparkles";
    case "party":
      return "person.3.fill";
  }
}

/** What connecting it unlocks, in one plain line short enough to fit beside the widest button. */
export function connectionUnlocks(kind: ConnectionKind): string {
  switch (kind) {
    case "calendar":
      return tr("See today's events in Tabbi.");
    case "anki":
      return tr("See due cards and start reviews.");
    case "spotify":
      return tr("Play, pause and skip on Spotify.");
    case "music":
      return tr("Control music playing in other apps.");
    case "notifications":
      return tr("Get an alert when a timer ends.");
    case "doNotDisturb":
      return tr("Turn it on yourself while you focus.");
    case "claude":
      return tr("Powers Claude usage and answers.");
    case "party":
      return tr("Study with friends, see their timers.");
  }
}

/** The modules that use this connection. */
export function connectionModules(kind: ConnectionKind): readonly ModuleID[] {
  switch (kind) {
    case "calendar":
      return [MODULE_IDS.planner];
    case "anki":
      return [MODULE_IDS.anki];
    case "spotify":
    case "music":
      return [MODULE_IDS.spotify];
    case "notifications":
    case "doNotDisturb":
      return [MODULE_IDS.planner, MODULE_IDS.focus, MODULE_IDS.study];
    case "claude":
      return [MODULE_IDS.claudeUsage];
    case "party":
      return [MODULE_IDS.party];
  }
}

/**
 * Whether the connection runs a helper program (the `claude` command line
 * tool), which a sandboxed build can't (`Edition.runsLocalTools`). On the
 * Mac Do Not Disturb runs Shortcuts too; on Windows it runs nothing.
 */
export function needsLocalTools(kind: ConnectionKind): boolean {
  return kind === "claude";
}

/**
 * The connections the enabled modules use, in row order, leaving out those
 * that need helper programs when `localTools` is false. `usesClaudeCode`
 * adds the Claude row when the user picked Claude Code to answer Ask and
 * Plan my day; any other AI is set up in the AI section.
 */
export function relevantConnections(
  enabled: Iterable<ModuleID>,
  options: { localTools?: boolean; usesClaudeCode?: boolean } = {},
): ConnectionKind[] {
  const modules = new Set(enabled);
  const localTools = options.localTools ?? true;
  return CONNECTION_KINDS.filter((kind) => {
    const used = connectionModules(kind).some((module) => modules.has(module)) || (kind === "claude" && options.usesClaudeCode === true);
    return used && (localTools || !needsLocalTools(kind));
  });
}

/** The troubleshooter's checks for a believable spread of demo states: most rows connected, a couple with one step left. */
export function demoDiagnosis(kind: ConnectionKind): ConnectionDiagnosis {
  switch (kind) {
    case "calendar":
      return calendarDiagnosis({
        feeds: [
          { name: "Classes", hasData: true, isGoogle: true },
          { name: "Holidays", hasData: true, isGoogle: false },
        ],
      });
    case "anki":
      return ankiDiagnosis({ kind: "ready" });
    case "spotify":
      return spotifyDiagnosis({ isInstalled: true });
    case "music":
      return mediaAppsDiagnosis({ available: true });
    case "notifications":
      return notificationsDiagnosis("disabledForApplication");
    case "doNotDisturb":
      return doNotDisturbDiagnosis();
    case "claude":
      /* A path with no personal folder in it, for the sign-in line. */
      return claudeDiagnosis("ready", "C:\\Program Files\\Claude\\claude.exe");
    case "party":
      return partyDiagnosis({ kind: "connected", friendCode: "PUFF-42" });
  }
}

/** The row's demo status (`demoDiagnosis`'s). */
export function demoStatus(kind: ConnectionKind): ConnectionStatus {
  return demoDiagnosis(kind).status;
}
