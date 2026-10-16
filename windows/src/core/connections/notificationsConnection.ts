import { tr } from "../localization/tr";
import { connectionCheck, connectionDiagnosis, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { ConnectionActions, connectionStatus, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of NotificationsConnection.swift for Windows toasts. Windows never
 * asks the user whether an app may notify, so there is no "not asked yet":
 * the state is the toast notifier's `NotificationSetting`, which says
 * whether toasts are on, turned off for Tabbi or for every app in Windows
 * Settings, blocked by a school or work policy, or impossible for a copy
 * of Tabbi without an app identity (a bare development build).
 */
export const NOTIFICATION_SETTINGS = ["enabled", "disabledForApplication", "disabledForUser", "disabledByGroupPolicy", "disabledByManifest"] as const;
export type NotificationSetting = (typeof NOTIFICATION_SETTINGS)[number];

export function notificationsConnectionStatus(setting: NotificationSetting): ConnectionStatus {
  const openSettings = { action: ConnectionActions.openSettings("notifications") };
  switch (setting) {
    case "enabled":
      return connectionStatus("connected", tr("Alerts are on"), tr("Tabbi tells you when a focus block or break ends."));
    case "disabledForApplication":
      return connectionStatus("needsStep", tr("Alerts are blocked"), tr("Turn on notifications for Tabbi in Windows Settings."), openSettings);
    case "disabledForUser":
      return connectionStatus("needsStep", tr("Alerts are off"), tr("Notifications are off for every app. Turn them on in Windows Settings."), openSettings);
    case "disabledByGroupPolicy":
      return connectionStatus("needsStep", tr("This PC blocks alerts"), tr("A school or work setting may block them. You can check in Windows Settings."), openSettings);
    case "disabledByManifest":
      /* Only a development build gets here, so it has no button and no gallery entry, like the Mac's calendar without a usage description. */
      return connectionStatus("needsStep", tr("This copy can't show alerts"), tr("Install Tabbi with its installer to get alerts."));
  }
}

export function notificationsDiagnosis(setting: NotificationSetting): ConnectionDiagnosis {
  const answer = (() => {
    switch (setting) {
      case "enabled":
        return tr("Yes.");
      case "disabledForApplication":
        return tr("No. They're off for Tabbi in Windows Settings.");
      case "disabledForUser":
        return tr("No. They're off for every app in Windows Settings.");
      case "disabledByGroupPolicy":
        return tr("No. A setting on this PC blocks them.");
      case "disabledByManifest":
        return tr("No. This copy of Tabbi can't show them.");
    }
  })();
  const checks = [connectionCheck(tr("Did you let Tabbi show alerts?"), setting === "enabled" ? "passed" : "failed", answer)];
  return connectionDiagnosis({
    kind: "notifications",
    status: notificationsConnectionStatus(setting),
    checks,
    technical: `notifications.${setting}`,
  });
}
