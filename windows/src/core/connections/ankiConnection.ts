import { errorMessage } from "../anki/ankiConnectError";
import { ankiConnectionClearsBySelf, ankiConnectionStatus, ankiConnectionTechnicalLabel } from "../anki/ankiConnectionStatus";
import type { AnkiConnectionState } from "../anki/ankiConnectionState";
import { tr } from "../localization/tr";
import { chainChecks, connectionDiagnosis, type ConnectionCheck, type ConnectionCheckOutcome, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { CONNECTION_APPS } from "./connectionStatus";

/*
 * The Anki part of ConnectionDiagnosis.swift: the troubleshooter's checks
 * for the Anki row (its status is core/anki/ankiConnectionStatus). Only the
 * question that names the Mac changes ("on this PC").
 */

const anki = CONNECTION_APPS.anki;

export function ankiDiagnosis(state: AnkiConnectionState): ConnectionDiagnosis {
  let checks: ConnectionCheck[];
  if (state.kind === "checking") {
    checks = chainChecks([{ question: tr("Is %@ on this PC?", anki.name), outcome: undefined, answer: "" }]);
  } else {
    const installed = state.kind !== "notInstalled";
    const open = installed && state.kind !== "notRunning";
    let addOn: ConnectionCheckOutcome | undefined = "passed";
    let addOnAnswer = tr("Yes, AnkiConnect answers.");
    if (state.kind === "starting") addOn = undefined;
    if (state.kind === "addOnMissing") {
      addOn = "failed";
      addOnAnswer = tr("No. Install it, or restart Anki if you just did.");
    }
    let cards: ConnectionCheckOutcome = "passed";
    let cardsAnswer = tr("Yes, Tabbi can count your cards.");
    if (state.kind === "problem") {
      cards = "failed";
      const error = state.error;
      switch (error.kind) {
        case "collectionUnavailable":
          cardsAnswer = tr("Not right now. Anki has no cards open: it may be syncing or on its profile list.");
          break;
        case "timeout":
          cardsAnswer = tr("No. Anki is busy. A window inside Anki may be open.");
          break;
        case "anki":
          cardsAnswer = tr("No. Anki said “%@”.", errorMessage(error) ?? "");
          break;
        case "invalidResponse":
        case "transport":
          cardsAnswer = tr("No. Tabbi couldn't read the cards (%@).", errorMessage(error) ?? "");
          break;
        default:
          cardsAnswer = tr("No. Anki didn't answer this time.");
      }
    }
    const needsPermission = state.kind === "needsPermission";
    const accessAnswer =
      state.kind === "needsPermission" && state.error.kind === "apiKeyRequired"
        ? tr("No. AnkiConnect is set to ask for a key.")
        : tr("No. Anki turned Tabbi down when it asked.");
    const outdated = state.kind === "addOnOutdated";
    checks = chainChecks([
      {
        question: tr("Is %@ on this PC?", anki.name),
        outcome: installed ? "passed" : "failed",
        answer: installed ? tr("Yes, Anki is installed.") : tr("No. Anki is a free app from apps.ankiweb.net."),
      },
      {
        question: tr("Is Anki open?"),
        outcome: open ? "passed" : "failed",
        answer: open ? tr("Yes, Anki is open.") : tr("No. Tabbi can only see your cards while Anki is open."),
      },
      { question: tr("Is the AnkiConnect add-on on?"), outcome: addOn, answer: addOnAnswer },
      {
        question: tr("Is AnkiConnect up to date?"),
        outcome: outdated ? "failed" : "passed",
        answer: outdated ? tr("No. This copy is too old for Tabbi.") : tr("Yes."),
      },
      { question: tr("Does Anki let Tabbi in?"), outcome: needsPermission ? "failed" : "passed", answer: needsPermission ? accessAnswer : tr("Yes.") },
      { question: tr("Can Tabbi see your cards?"), outcome: cards, answer: cardsAnswer },
    ]);
  }
  return connectionDiagnosis({
    kind: "anki",
    status: ankiConnectionStatus(state),
    checks,
    technical: ankiConnectionTechnicalLabel(state),
    clearsBySelf: ankiConnectionClearsBySelf(state),
  });
}
