/**
 * Port of RunMode: how this process runs, live, with demo data, rendering
 * snapshots, or both of the latter. Read once at launch and handed to every
 * module, so no store reads the environment itself.
 */
export interface RunMode {
  /** `TABBI_DEMO=1`: realistic sample data, and never the network, media sessions, calendars or CLIs. */
  readonly isDemo: boolean;
  /** `--snapshot <folder>`: render PNGs and exit. No sounds, nothing saved. */
  readonly isSnapshot: boolean;
}

/** The environment variable that turns demo mode on. */
export const DEMO_VARIABLE = "TABBI_DEMO";
/** The argument that renders snapshots. */
export const SNAPSHOT_FLAG = "--snapshot";

/** The real app: real data, saved to disk. */
export const LIVE_RUN_MODE: RunMode = { isDemo: false, isSnapshot: false };
/** Sample data, kept in memory. */
export const DEMO_RUN_MODE: RunMode = { isDemo: true, isSnapshot: false };

/** The mode a process with this environment and these arguments runs in. */
export function runModeFrom(environment: Readonly<Record<string, string | undefined>>, args: readonly string[]): RunMode {
  return { isDemo: environment[DEMO_VARIABLE] === "1", isSnapshot: args.includes(SNAPSHOT_FLAG) };
}

/** True when nothing may be saved: demo data must not overwrite the user's files, and a snapshot run leaves no trace. */
export function isEphemeral(mode: RunMode): boolean {
  return mode.isDemo || mode.isSnapshot;
}
