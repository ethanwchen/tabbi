import { tr } from "../localization/tr";
import { connectionCheck, connectionDiagnosis, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { ConnectionActions, connectionStatus, type ConnectionStatus } from "./connectionStatus";

/*
 * The Windows stand-in for FocusShortcutsConnection.swift. On the Mac,
 * Tabbi switches Do Not Disturb through two shortcuts the user makes, and
 * the row checks that they exist (with a "Test it" button). Windows has no
 * supported way for an app to turn Do not disturb on or off, so the row
 * stays, says so plainly, and opens Windows' notification settings, where
 * the user can turn it on (or schedule it) themselves. The shortcut list,
 * the walkthrough and the test have no Windows counterpart and are not
 * ported.
 */

export function doNotDisturbConnectionStatus(): ConnectionStatus {
  return connectionStatus(
    "unavailable",
    tr("Not available on Windows"),
    tr("Windows doesn't let apps turn on Do not disturb. Turn it on yourself in Settings when you focus."),
    { action: ConnectionActions.openSettings("notifications") },
  );
}

export function doNotDisturbDiagnosis(): ConnectionDiagnosis {
  return connectionDiagnosis({
    kind: "doNotDisturb",
    status: doNotDisturbConnectionStatus(),
    checks: [
      connectionCheck(
        tr("Can Tabbi turn on Do not disturb?"),
        "note",
        tr("No. Windows doesn't let apps do that, so it's up to you in Settings."),
      ),
    ],
    technical: "doNotDisturb.unavailableOnWindows",
  });
}
