import {
  CONNECTION_APPS,
  ConnectionActions,
  actionTitle,
  connectionActionName as actionName,
  connectionStatus,
  type ConnectionAction,
  type ConnectionStatus,
} from "../connections/connectionStatus";
import { tr } from "../localization/tr";
import { type AnkiConnectError, addOnReminderWithCode, errorTitle, isUnexplained } from "./ankiConnectError";
import type { AnkiConnectionState } from "./ankiConnectionState";

/*
 * Port of AnkiConnection.swift: the Anki row of Settings > Connections, the
 * Anki tab's setup steps in plain words, each with the one button that
 * moves it forward. The row's types live in core/connections with the
 * other rows; its troubleshooter checks are `ankiDiagnosis` there.
 */

/** The app the Anki row opens or asks the user to get, by the name it goes by in sentences. */
export const ANKI_APP_NAME = CONNECTION_APPS.anki.name;

const anki = CONNECTION_APPS.anki;

/** The button's label (ConnectionAction.title). */
export function connectionActionTitle(action: ConnectionAction): string {
  return actionTitle(action);
}

/** A stable name for an action, such as `openApp.Anki`, the way the Mac's golden fixture writes it. */
export function connectionActionName(action: ConnectionAction): string {
  return actionName(action);
}

/**
 * Port of AnkiConnectionState.connectionStatus. The only sentence that
 * names the Mac there ("Anki isn't on this Mac") reads "on this PC" here.
 */
export function ankiConnectionStatus(state: AnkiConnectionState): ConnectionStatus {
  switch (state.kind) {
    case "checking":
      return connectionStatus("checking", tr("Looking for Anki"), tr("This takes a second."));
    case "notInstalled":
      return connectionStatus("notInstalled", tr("%@ isn't on this PC", anki.name), tr("It's a free flashcard app. Get it, then come back here."), {
        action: ConnectionActions.download(anki),
      });
    case "notRunning":
      return connectionStatus("needsStep", tr("Anki is closed"), tr("Open Anki so Tabbi can see your cards."), {
        action: ConnectionActions.openApp(anki),
      });
    case "starting":
      return connectionStatus("checking", tr("Anki is starting"), tr("This takes a few seconds."));
    case "addOnMissing":
      return connectionStatus("notSetUp", tr("One add-on to go"), tr("Anki needs a free add-on called AnkiConnect so Tabbi can count your cards."), {
        action: ConnectionActions.showGuide("ankiAddOn"),
      });
    case "needsPermission":
      return state.error.kind === "apiKeyRequired"
        ? connectionStatus("needsStep", tr("Anki has a password on"), tr("AnkiConnect is set to ask for a key. Turning that off takes a minute."), {
            action: ConnectionActions.showGuide("ankiAccess"),
          })
        : connectionStatus("needsStep", tr("Anki said no to Tabbi"), tr("When Anki asked whether to let Tabbi in, the answer was no."), {
            action: ConnectionActions.showGuide("ankiAccess"),
          });
    case "addOnOutdated":
      return connectionStatus("needsStep", tr("Update AnkiConnect"), tr("Your copy of the AnkiConnect add-on is too old for Tabbi."), {
        action: ConnectionActions.showGuide("ankiAddOnUpdate"),
      });
    case "ready":
      return connectionStatus("connected", tr("Anki is connected"), tr("Your due cards show up in Tabbi."));
    case "problem":
      return problemStatus(state.error);
  }
}

function problemStatus(error: AnkiConnectError): ConnectionStatus {
  if (error.kind === "collectionUnavailable") {
    /* AnkiConnect can't tell the profile list from a collection closed for a moment, so say both, likeliest first. */
    return connectionStatus("needsStep", tr("Waiting for Anki"), tr("Anki may be syncing or on its profile list. Tabbi reconnects by itself."), {
      action: ConnectionActions.openApp(anki),
    });
  }
  if (error.kind === "timeout") {
    return connectionStatus("needsStep", tr("Anki is busy"), tr("Close any open window inside Anki, then check again."), {
      action: ConnectionActions.checkAgain,
    });
  }
  if (isUnexplained(error)) {
    /* The row has room for the likeliest fix; Anki's own words are in the troubleshooter. */
    return connectionStatus("needsStep", errorTitle(error), addOnReminderWithCode(), { action: ConnectionActions.checkAgain });
  }
  return connectionStatus("needsStep", tr("Anki didn't answer"), tr("This is usually short. Check again in a moment."), {
    action: ConnectionActions.checkAgain,
  });
}

/**
 * Port of the Anki diagnosis's technical label: `anki.<state>` plus the
 * error's case for the states that carry one, such as
 * `anki.problem.timeout`, for support details. Never holds message text.
 */
export function ankiConnectionTechnicalLabel(state: AnkiConnectionState): string {
  switch (state.kind) {
    case "needsPermission":
    case "problem":
      return `anki.${state.kind}.${state.error.kind}`;
    default:
      return `anki.${state.kind}`;
  }
}

/** Port of the Anki diagnosis's `clearsBySelf`: Anki starting or a problem usually ends on its own. */
export function ankiConnectionClearsBySelf(state: AnkiConnectionState): boolean {
  return state.kind === "starting" || state.kind === "problem";
}
