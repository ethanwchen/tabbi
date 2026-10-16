import { tr } from "../localization/tr";
import { MINIMUM_AGE } from "../party/partyAgeCheck";
import { SupportContact } from "../party/partyModeration";
import { cleanedPartyName, partySettings } from "../party/partySettings";
import type { PartyConnection } from "../party/partyState";
import type { Instant } from "../time";
import { chainChecks, connectionDiagnosis, type ConnectionCheckOutcome, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { ConnectionActions, connectionStatus, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of PartyConnection.swift: where Party stands. There's no account to
 * make: the user picks a name and a pet once, and Tabbi registers by
 * itself. Party works the same on Windows, so only the age note changes
 * ("stays on this PC").
 */

/** Port of PartyConnectionState. */
export type PartyConnectionState =
  /** No name chosen yet. */
  | { readonly kind: "notSetUp" }
  /** Waiting for the age check, which the Party tab asks; `tooYoungUntil` is set when it said under 13. */
  | { readonly kind: "ageCheck"; readonly tooYoungUntil: Instant | undefined }
  | { readonly kind: "connecting" }
  /** The server couldn't be reached. */
  | { readonly kind: "offline" }
  | { readonly kind: "connected"; readonly friendCode: string };

/** The state for the Party tab's connection and whether the user has picked a name. */
export function resolvePartyConnection(
  connection: PartyConnection,
  friendCode: string | undefined,
  hasChosenName: boolean,
): PartyConnectionState {
  if (connection.kind === "ageCheck") return { kind: "ageCheck", tooYoungUntil: connection.tooYoungUntil };
  if (!hasChosenName) return { kind: "notSetUp" };
  switch (connection.kind) {
    case "connecting":
      return { kind: "connecting" };
    case "invalidServer":
    case "unreachable":
      return { kind: "offline" };
    case "connected":
      return friendCode === undefined ? { kind: "connecting" } : { kind: "connected", friendCode };
  }
}

export function partyConnectionStatus(state: PartyConnectionState): ConnectionStatus {
  switch (state.kind) {
    case "notSetUp":
      return connectionStatus("notSetUp", tr("Party isn't set up"), tr("Pick a name and a pet to start. No account needed."), {
        action: ConnectionActions.setUp,
      });
    case "ageCheck":
      if (state.tooYoungUntil === undefined) {
        return connectionStatus("notSetUp", tr("Party isn't set up"), tr("Pick a name and a pet, and say when you were born."), {
          action: ConnectionActions.setUp,
        });
      }
      /* Nothing to fix: Party opens once the user is 13, which Check again (or opening the Party tab) notices. */
      return connectionStatus("notSetUp", tr("Party isn't available"), tr("It's for people %lld and older.", MINIMUM_AGE), {
        action: ConnectionActions.checkAgain,
      });
    case "connecting":
      return connectionStatus("checking", tr("Connecting"), tr("This takes a second."));
    case "offline":
      return connectionStatus("needsStep", tr("Party can't connect"), tr("Check that your Wi-Fi is on, then try again."), {
        action: ConnectionActions.checkAgain,
      });
    case "connected":
      return connectionStatus("connected", tr("Party is ready"), tr("Your friend code is %@. Share it so friends can add you.", state.friendCode), {
        suggestion: ConnectionActions.copyFriendCode(state.friendCode),
      });
  }
}

export function partyDiagnosis(state: PartyConnectionState): ConnectionDiagnosis {
  const online: ConnectionCheckOutcome | undefined =
    state.kind === "notSetUp" || state.kind === "connected" ? "passed" : state.kind === "offline" ? "failed" : undefined;
  const age: { outcome: ConnectionCheckOutcome; answer: string } =
    state.kind !== "ageCheck"
      ? { outcome: "passed", answer: tr("Yes.") }
      : state.tooYoungUntil === undefined
        ? { outcome: "failed", answer: tr("Not yet. Open the Party tab to answer.") }
        : { outcome: "failed", answer: tr("Party is for people %lld and older.", MINIMUM_AGE) };
  const checks = chainChecks([
    { question: tr("Did you answer the age question?"), outcome: age.outcome, answer: age.answer },
    {
      question: tr("Did you pick a name?"),
      outcome: state.kind === "notSetUp" ? "failed" : "passed",
      answer: state.kind === "notSetUp" ? tr("Not yet. Pick a name and a pet to start.") : tr("Yes."),
    },
    {
      question: tr("Can Tabbi reach Party?"),
      outcome: online,
      answer: online === "failed" ? tr("No. Check that your Wi-Fi is on, then try again.") : tr("Yes."),
    },
  ]);
  const technical =
    state.kind === "ageCheck" ? (state.tooYoungUntil === undefined ? "party.ageCheck" : "party.tooYoung") : `party.${state.kind}`;
  return connectionDiagnosis({ kind: "party", status: partyConnectionStatus(state), checks, technical });
}

/**
 * Port of PartySetup: the one screen Party needs before it starts, the
 * name and pet friends see. Tabbi registers by itself once it's filled in,
 * so there's no account, email or password to make.
 */
export const PartySetup = {
  title: () => tr("Join Party"),
  intro: () => tr("Pick the name and pet your friends will see. No account or password needed."),
  nameLabel: () => tr("Your name"),
  namePlaceholder: () => tr("Like Sam or Dr. Sam"),
  petLabel: () => tr("Your pet"),
  petNote: () => tr("You can dress your pet up later in the Closet tab."),
  start: () => tr("Start Party"),
  birthLabel: () => tr("When were you born?"),
  birthNote: () => tr("Asked once. Your answer stays on this PC."),
  /** The agreement under the age check, as Markdown with both links. */
  agreement: () =>
    tr("By joining you agree to the [Terms of Use](%@) and the [Privacy Policy](%@).", SupportContact.termsURL, SupportContact.privacyURL),
  /** The header once Party is ready. */
  readyTitle: () => tr("You're in Party"),
  readyIntro: () => tr("Send friends your code so they can add you. They see your name, pet and study timer."),
  /** The name to save, or undefined while nothing usable is typed, so the start button stays off until there's a real name. */
  name: (text: string): string | undefined => cleanedPartyName(partySettings({ name: text })),
} as const;
