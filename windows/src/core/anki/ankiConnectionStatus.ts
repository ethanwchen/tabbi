import { tr } from "../localization/tr";
import { type AnkiConnectError, addOnReminderWithCode, errorTitle, isUnexplained } from "./ankiConnectError";
import type { AnkiConnectionState } from "./ankiConnectionState";

/*
 * The Anki row of Settings > Connections: the parts of the Mac's
 * ConnectionStatus, ConnectionAction and ConnectionDiagnosis that the Anki
 * tab's states use. The rest of Connections is not ported yet, so these
 * stay beside the Anki port until it is.
 */

/** Port of ConnectionLight: the status light on a Connections row. */
export type ConnectionLight = "checking" | "connected" | "needsStep" | "notSetUp" | "notInstalled";

/** Port of the ConnectionGuide cases the Anki row offers. */
export type AnkiConnectionGuide = "ankiAddOn" | "ankiAddOnUpdate" | "ankiAccess";

/** Port of the ConnectionAction cases the Anki row offers: the one button that moves it forward. */
export type AnkiConnectionAction =
  | { kind: "download" }
  | { kind: "openApp" }
  | { kind: "showGuide"; guide: AnkiConnectionGuide }
  | { kind: "checkAgain" };

/** The app the Anki row opens or asks the user to get, by the name it goes by in sentences. */
export const ANKI_APP_NAME = "Anki";

/** Port of ConnectionAction.title for the Anki row's buttons. */
export function connectionActionTitle(action: AnkiConnectionAction): string {
  switch (action.kind) {
    case "download":
      return tr("Get %@", ANKI_APP_NAME);
    case "openApp":
      return tr("Open %@", ANKI_APP_NAME);
    case "showGuide":
      return tr("Show me how");
    case "checkAgain":
      return tr("Check again");
  }
}

/**
 * A stable name for an action, such as `openApp.Anki` or
 * `showGuide.ankiAddOn`, the way the Mac's golden fixture writes it.
 */
export function connectionActionName(action: AnkiConnectionAction): string {
  switch (action.kind) {
    case "download":
    case "openApp":
      return `${action.kind}.${ANKI_APP_NAME}`;
    case "showGuide":
      return `showGuide.${action.guide}`;
    case "checkAgain":
      return "checkAgain";
  }
}

/** Port of ConnectionStatus: a light, a headline, one sentence and at most one button. */
export interface AnkiConnectionStatus {
  light: ConnectionLight;
  headline: string;
  detail: string;
  action?: AnkiConnectionAction;
}

/**
 * Port of AnkiConnectionState.connectionStatus: the Connections row for a
 * state, the Anki tab's setup steps in plain words, each with the one
 * button that moves it forward. The headline for a missing Anki keeps the
 * Mac's catalog key until Windows wording for it lands in Windows.xcstrings.
 */
export function ankiConnectionStatus(state: AnkiConnectionState): AnkiConnectionStatus {
  switch (state.kind) {
    case "checking":
      return { light: "checking", headline: tr("Looking for Anki"), detail: tr("This takes a second.") };
    case "notInstalled":
      return {
        light: "notInstalled",
        headline: tr("Anki isn't on this Mac"),
        detail: tr("It's a free flashcard app. Get it, then come back here."),
        action: { kind: "download" },
      };
    case "notRunning":
      return {
        light: "needsStep",
        headline: tr("Anki is closed"),
        detail: tr("Open Anki so Tabbi can see your cards."),
        action: { kind: "openApp" },
      };
    case "starting":
      return { light: "checking", headline: tr("Anki is starting"), detail: tr("This takes a few seconds.") };
    case "addOnMissing":
      return {
        light: "notSetUp",
        headline: tr("One add-on to go"),
        detail: tr("Anki needs a free add-on called AnkiConnect so Tabbi can count your cards."),
        action: { kind: "showGuide", guide: "ankiAddOn" },
      };
    case "needsPermission":
      if (state.error.kind === "apiKeyRequired") {
        return {
          light: "needsStep",
          headline: tr("Anki has a password on"),
          detail: tr("AnkiConnect is set to ask for a key. Turning that off takes a minute."),
          action: { kind: "showGuide", guide: "ankiAccess" },
        };
      }
      return {
        light: "needsStep",
        headline: tr("Anki said no to Tabbi"),
        detail: tr("When Anki asked whether to let Tabbi in, the answer was no."),
        action: { kind: "showGuide", guide: "ankiAccess" },
      };
    case "addOnOutdated":
      return {
        light: "needsStep",
        headline: tr("Update AnkiConnect"),
        detail: tr("Your copy of the AnkiConnect add-on is too old for Tabbi."),
        action: { kind: "showGuide", guide: "ankiAddOnUpdate" },
      };
    case "ready":
      return { light: "connected", headline: tr("Anki is connected"), detail: tr("Your due cards show up in Tabbi.") };
    case "problem":
      return problemStatus(state.error);
  }
}

function problemStatus(error: AnkiConnectError): AnkiConnectionStatus {
  if (error.kind === "collectionUnavailable") {
    /* AnkiConnect can't tell the profile list from a collection closed for a moment, so say both, likeliest first. */
    return {
      light: "needsStep",
      headline: tr("Waiting for Anki"),
      detail: tr("Anki may be syncing or on its profile list. Tabbi reconnects by itself."),
      action: { kind: "openApp" },
    };
  }
  if (error.kind === "timeout") {
    return {
      light: "needsStep",
      headline: tr("Anki is busy"),
      detail: tr("Close any open window inside Anki, then check again."),
      action: { kind: "checkAgain" },
    };
  }
  if (isUnexplained(error)) {
    /* The row has room for the likeliest fix; Anki's own words are in the troubleshooter. */
    return { light: "needsStep", headline: errorTitle(error), detail: addOnReminderWithCode(), action: { kind: "checkAgain" } };
  }
  return {
    light: "needsStep",
    headline: tr("Anki didn't answer"),
    detail: tr("This is usually short. Check again in a moment."),
    action: { kind: "checkAgain" },
  };
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
