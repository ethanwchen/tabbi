import { wallTime } from "../calendar/zonedCalendar";
import { joinSentences } from "../formatting/sentences";
import { tr } from "../localization/tr";
import type { Instant } from "../time";
import type { ConnectionKind } from "./connectionKind";
import { connectionTitle } from "./connectionKind";
import { isConnected, lightTitle, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of ConnectionDiagnosis.swift: the "Something not working?"
 * troubleshooter for one row: its status, the checks behind it in plain
 * words, and a short technical label that only goes into the copied
 * support details. Each connection builds its own diagnosis in its file.
 */

/** Port of ConnectionCheck.Outcome. */
export type ConnectionCheckOutcome =
  | "passed"
  | "failed"
  /** Not checked, because an earlier check failed or a check is still running. */
  | "skipped"
  /** Worth knowing but optional (no Google calendar yet, say). */
  | "note";

/** One yes-or-no question about one piece of the connection, with its answer in one short sentence. Port of ConnectionCheck. */
export interface ConnectionCheck {
  readonly question: string;
  readonly outcome: ConnectionCheckOutcome;
  readonly answer: string;
}

export function connectionCheck(question: string, outcome: ConnectionCheckOutcome, answer: string): ConnectionCheck {
  return { question, outcome, answer };
}

/** The answer for a check that was never reached. */
export function notReachedAnswer(): string {
  return tr("Not checked yet. Fix the step above first.");
}

/** The answer while a check is still running. */
export function stillCheckingAnswer(): string {
  return tr("Still checking.");
}

/**
 * Checks that depend on each other, in order: once one fails, the rest are
 * skipped, because their answers wouldn't mean anything. An undefined
 * outcome means the check is still running, which also stops the chain.
 */
export function chainChecks(
  steps: readonly { readonly question: string; readonly outcome: ConnectionCheckOutcome | undefined; readonly answer: string }[],
): ConnectionCheck[] {
  let stopped = false;
  return steps.map((step) => {
    if (stopped) return connectionCheck(step.question, "skipped", notReachedAnswer());
    if (step.outcome === undefined) {
      stopped = true;
      return connectionCheck(step.question, "skipped", stillCheckingAnswer());
    }
    if (step.outcome === "failed") stopped = true;
    return connectionCheck(step.question, step.outcome, step.answer);
  });
}

/** Port of ConnectionDiagnosis. */
export interface ConnectionDiagnosis {
  readonly kind: ConnectionKind;
  readonly status: ConnectionStatus;
  readonly checks: readonly ConnectionCheck[];
  /**
   * A compact name for the exact state, such as `anki.notRunning`, so
   * support can tell similar-looking cases apart. Never shown in the UI and
   * never holds personal details (no account names, calendar names or links).
   */
  readonly technical: string;
  /**
   * The command line tool the check found (Claude's), so a walkthrough can
   * offer a line that runs it by its full path. Never shown as is and never
   * put in the support details, since it names the user's home folder.
   */
  readonly executable?: string;
  /** Whether this state usually clears by itself within seconds (Anki starting, syncing or behind a dialog). */
  readonly clearsBySelf: boolean;
}

export function connectionDiagnosis(fields: {
  kind: ConnectionKind;
  status: ConnectionStatus;
  checks: readonly ConnectionCheck[];
  technical: string;
  executable?: string | undefined;
  clearsBySelf?: boolean;
}): ConnectionDiagnosis {
  const diagnosis: { -readonly [Key in keyof ConnectionDiagnosis]: ConnectionDiagnosis[Key] } = {
    kind: fields.kind,
    status: fields.status,
    checks: fields.checks,
    technical: fields.technical,
    clearsBySelf: fields.clearsBySelf ?? false,
  };
  if (fields.executable !== undefined) diagnosis.executable = fields.executable;
  return diagnosis;
}

/** The first check that failed, which is what the row's button fixes. */
export function firstFailure(diagnosis: ConnectionDiagnosis): ConnectionCheck | undefined {
  return diagnosis.checks.find((check) => check.outcome === "failed");
}

/** The one-line verdict at the top of the troubleshooter. */
export function diagnosisVerdict(diagnosis: ConnectionDiagnosis): string {
  const status = diagnosis.status;
  if (status.light === "checking") return tr("Tabbi is still checking. This takes a second.");
  if (isConnected(status)) return joinSentences([tr("Everything checks out."), status.detail]);
  /* The headline has no stop of its own; Japanese and Chinese end it with a full-width stop. */
  return joinSentences([tr("%@.", status.headline), status.detail]);
}

/** The tag in copied details. */
function outcomeLabel(outcome: ConnectionCheckOutcome): string {
  switch (outcome) {
    case "passed":
      return "ok";
    case "failed":
      return "problem";
    case "skipped":
      return "skipped";
    case "note":
      return "note";
  }
}

/**
 * Plain text for "Copy details": what a user pastes into a message to
 * support. It names the app and Windows versions so nobody has to ask; the
 * check time is read on the wall clock of `timeZone`.
 */
export function diagnosisDetails(
  diagnosis: ConnectionDiagnosis,
  options: { appVersion: string; systemVersion: string; checkedAt: Instant; timeZone: string },
): string {
  const wall = wallTime(options.checkedAt, options.timeZone);
  const pad = (value: number, width = 2) => String(value).padStart(width, "0");
  const checked = `${pad(wall.year, 4)}-${pad(wall.month)}-${pad(wall.day)} ${pad(wall.hour)}:${pad(wall.minute)}`;
  const status = diagnosis.status;
  const lines = [
    "Tabbi connection details",
    `Connection: ${connectionTitle(diagnosis.kind)}`,
    `Status: ${lightTitle(status.light)} (${status.headline})`,
    `Checked: ${checked}`,
    `Tabbi: ${options.appVersion}`,
    `Windows: ${options.systemVersion}`,
    `State: ${diagnosis.technical}`,
    "",
    ...diagnosis.checks.map((check) => `[${outcomeLabel(check.outcome)}] ${check.question} ${check.answer}`),
  ];
  return lines.join("\n");
}
