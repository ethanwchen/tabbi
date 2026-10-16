import { tr } from "../localization/tr";
import { chainChecks, connectionDiagnosis, type ConnectionCheckOutcome, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { ConnectionActions, connectionStatus, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of ClaudeConnection.swift: whether the Claude command line tool is
 * installed and signed in, for Plan my day and Ask AI. On Windows the
 * setup lines run in PowerShell (`claude.exe`, the native installer's
 * `install.ps1`) where the Mac's run in Terminal.
 */

/** Whether the user is signed in to Claude, from `claude auth status --json`. Port of ClaudeSignIn. */
export type ClaudeSignIn = "signedIn" | "signedOut" | "unknown";

/**
 * Reads the probe's output. Only the `loggedIn` field counts; Tabbi never
 * reads or keeps the account details the command also prints. An answer we
 * don't understand (an older Claude without the command) is `unknown`,
 * treated as signed in: Claude itself explains if not.
 */
export function parseClaudeSignIn(output: string): ClaudeSignIn {
  const start = output.indexOf("{");
  const end = output.lastIndexOf("}");
  if (start < 0 || end <= start) return "unknown";
  try {
    const object: unknown = JSON.parse(output.slice(start, end + 1));
    if (typeof object !== "object" || object === null || Array.isArray(object)) return "unknown";
    const loggedIn = (object as Record<string, unknown>).loggedIn;
    if (typeof loggedIn !== "boolean") return "unknown";
    return loggedIn ? "signedIn" : "signedOut";
  } catch {
    return "unknown";
  }
}

/** Where the Claude connection stands. Port of ClaudeConnectionState. */
export type ClaudeConnectionState = "checking" | "notInstalled" | "signedOut" | "ready";

export const ClaudeSetup = {
  /** The official setup page, for "Show me how". */
  installPage: "https://code.claude.com/docs/en/setup",
  /** Where the native installer puts `claude.exe`, in PowerShell's words; a fresh window may not have it on its PATH yet. */
  installedExecutable: "$env:USERPROFILE\\.local\\bin\\claude.exe",
  /** The arguments that sign in. They open a sign-in page in the browser, so Tabbi never sees the password. */
  signInArguments: ["auth", "login"] as readonly string[],
  /** The arguments of the sign-in probe. */
  probeArguments: ["auth", "status", "--json"] as readonly string[],
};

/**
 * The one line offered to copy for a first setup: the official Windows
 * installer from the setup page, then the sign-in, run by the path the
 * installer just wrote so it works before PATH knows about it. `if ($?)`
 * skips the sign-in when the install fails, as the Mac's `&&` does.
 */
export function claudeInstallCommand(): string {
  return `irm https://claude.ai/install.ps1 | iex; if ($?) { & "${ClaudeSetup.installedExecutable}" ${ClaudeSetup.signInArguments.join(" ")} }`;
}

/**
 * The sign-in line offered to copy. It runs the `claude.exe` Tabbi found by
 * its full path (quoted for PowerShell), since a new window may not find it
 * by name, and falls back to the plain command only when no path is known.
 */
export function claudeSignInCommand(executable: string | undefined): string {
  const args = ClaudeSetup.signInArguments.join(" ");
  if (executable === undefined || executable.trim() === "") return `claude ${args}`;
  return `& '${executable.replace(/'/g, "''")}' ${args}`;
}

/** The state for a lookup and probe. `signIn` is undefined while the probe runs. */
export function resolveClaudeConnection(isInstalled: boolean, signIn: ClaudeSignIn | undefined): ClaudeConnectionState {
  if (!isInstalled) return "notInstalled";
  switch (signIn) {
    case undefined:
      return "checking";
    case "signedOut":
      return "signedOut";
    case "signedIn":
    case "unknown":
      return "ready";
  }
}

export function claudeConnectionStatus(state: ClaudeConnectionState): ConnectionStatus {
  switch (state) {
    case "checking":
      return connectionStatus("checking", tr("Looking for Claude"), tr("This takes a second."));
    case "notInstalled":
      return connectionStatus(
        "notInstalled",
        tr("Claude is optional"),
        tr("It's an AI helper that can plan your day and answer questions. Everything else works without it."),
        { action: ConnectionActions.showGuide("claudeInstall") },
      );
    case "signedOut":
      return connectionStatus("needsStep", tr("Sign in to Claude"), tr("Claude is installed. Sign in once and Tabbi can use it."), {
        action: ConnectionActions.showGuide("claudeSignIn"),
      });
    case "ready":
      return connectionStatus("connected", tr("Claude is ready"), tr("Plan my day and Ask AI can use it."));
  }
}

/** The diagnosis, carrying where `claude.exe` was found for the sign-in walkthrough's line. */
export function claudeDiagnosis(state: ClaudeConnectionState, executable?: string): ConnectionDiagnosis {
  const installed: ConnectionCheckOutcome | undefined =
    state === "checking" ? undefined : state === "notInstalled" ? "failed" : "passed";
  const checks = chainChecks([
    {
      question: tr("Is %@ on this PC?", "Claude"),
      outcome: installed,
      answer: installed === "failed" ? tr("No. Set it up to use Plan my day and Ask AI with Claude.") : tr("Yes."),
    },
    {
      question: tr("Are you signed in to Claude?"),
      outcome: state === "signedOut" ? "failed" : "passed",
      answer: state === "signedOut" ? tr("No. Sign in once and Tabbi can use it.") : tr("Yes."),
    },
  ]);
  return connectionDiagnosis({
    kind: "claude",
    status: claudeConnectionStatus(state),
    checks,
    technical: `claude.${state}`,
    executable: state === "notInstalled" ? undefined : executable,
  });
}
