/*
 * Port of ClaudeUsageStore: state for the AI Usage panel. Local token stats
 * come from the Claude Code transcripts under `%USERPROFILE%\.claude` (the
 * incremental scanner, read through the host's log commands), or, while the
 * Codex CLI is the chosen AI (`source`), limits and stats both come from
 * Codex's own session logs under `%USERPROFILE%\.codex`. Reading costs the
 * user nothing, so it runs whenever the panel opens.
 *
 * The live Claude limits probe runs the claude CLI, which Windows does not
 * do yet (the CLI providers ship later), so the Claude Code rings show the
 * last saved snapshot, or nothing, and a refresh only re-reads the
 * transcripts. The saved snapshot keeps the Mac's format, so the probe can
 * fill it in later without a migration.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import type { AISetupState } from "../../core/ai/aiProviderFactory";
import { settingTime, wallTime } from "../../core/calendar/zonedCalendar";
import { decodeLimitsRecord, encodeLimitsRecord, type ClaudeLimitsRecord } from "../../core/claudeUsage/claudeLimits";
import type { ClaudeLocalStats } from "../../core/claudeUsage/claudeLocalStats";
import { usageSourceFor, type AIUsageSource } from "../../core/claudeUsage/claudeUsageHighlights";
import { ClaudeUsageLogScanner, type ReadFrom, type TranscriptFile } from "../../core/claudeUsage/claudeUsageLogScanner";
import { codexFilesToRead, summarizeCodexSessions } from "../../core/claudeUsage/codexUsageLog";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { Instant } from "../../core/time";
import type { AiLogFile, AiLogTool } from "../../host/host";

/** Port of ClaudeUsageStore.CLIStatus: whether the source's command line tool was found. */
export type CLIStatus = "locating" | "available" | "missing";

export interface ClaudeUsageState {
  readonly cliStatus: CLIStatus;
  /** The most recent limits snapshot, possibly from a previous launch. */
  readonly limits: ClaudeLimitsRecord | undefined;
  /** True while the logs are being read. */
  readonly isFetching: boolean;
  /** Set when the latest read failed; `limits` keeps the previous snapshot. */
  readonly probeError: string | undefined;
  /** Undefined until the first scan finishes. */
  readonly stats: ClaudeLocalStats | undefined;
  /** Whose logs the panel shows; follows the chosen AI. */
  readonly source: AIUsageSource;
}

/** The saved Claude limits snapshot, as a document in the module's folder (the Mac keeps it in UserDefaults). */
export const LIMITS_DOCUMENT = "limits-record.json";
export const USAGE_FOLDER = "ClaudeUsage";

/** Where the host's logs are read from, by source. */
export function logTool(source: AIUsageSource): AiLogTool {
  return source === "codex" ? "codex" : "claude";
}

export class ClaudeUsageStore extends Store<ClaudeUsageState> {
  private readonly isDemo: boolean;
  private readonly scanner: ClaudeUsageLogScanner;
  /** Undefined in demo and snapshot runs, which save nothing. */
  private readonly limitsStore: DocumentStore | undefined;
  /** The Claude snapshot, kept while Codex is shown so switching back is instant. */
  private claudeLimits: ClaudeLimitsRecord | undefined;
  private scanning = false;
  /** A scan was requested while one was running; run another when it ends. */
  private rescanPending = false;
  private readingCodex = false;
  /** Bumped per lookup so a slow one for an old source can't win. */
  private statusGeneration = 0;
  private readonly decoder = new TextDecoder();

  constructor(
    private readonly context: ModuleContext,
    source: AIUsageSource = "claudeCode",
  ) {
    super({ cliStatus: "locating", limits: undefined, isFetching: false, probeError: undefined, stats: undefined, source });
    this.isDemo = context.isDemo;
    const ephemeral = context.isDemo || context.isSnapshot;
    this.scanner = new ClaudeUsageLogScanner(ephemeral ? {} : { store: context.storage.root("cache") });
    this.limitsStore = ephemeral ? undefined : context.storage.folder(USAGE_FOLDER);
    if (this.isDemo) {
      this.loadDemoData();
      return;
    }
    void this.loadSavedLimits().then(() => this.load());
  }

  /** Follows the chosen AI: Codex shows its own logs, anything else Claude Code's. */
  followSetup(state: AISetupState): void {
    this.setSource(usageSourceFor(state.kind === "notChosen" ? undefined : state.provider));
  }

  /** Called when the chosen AI changes, so the panel shows its logs. */
  setSource(source: AIUsageSource): void {
    if (this.isDemo || source === this.state.source) return;
    this.setState({ source, probeError: undefined, stats: undefined, isFetching: source === "codex" ? this.readingCodex : this.scanning });
    this.load();
  }

  /** Shows what is already known for the source and starts reading the rest. */
  private load(): void {
    this.updateCLIStatus();
    if (this.state.source === "codex") {
      this.setState({ limits: undefined });
      this.readCodexLogs();
    } else {
      this.setState({ limits: this.claudeLimits });
      /* Warm the stats so the first open is instant; later scans are incremental. */
      this.scanLocalStats();
    }
  }

  /** Called when the panel becomes visible. */
  panelDidAppear(): void {
    if (this.isDemo) return;
    if (this.state.source === "codex") this.readCodexLogs();
    else this.scanLocalStats();
  }

  /** Re-reads the source's logs. No-op while a read is running. */
  refresh(): void {
    if (this.isDemo) return;
    if (this.state.source === "codex") this.readCodexLogs();
    else this.scanLocalStats(true);
  }

  /** Looks the source's tool up through the host; cancels the previous lookup so a slow one for an old source can't win. */
  private updateCLIStatus(): void {
    this.statusGeneration += 1;
    const generation = this.statusGeneration;
    this.setState({ cliStatus: "locating" });
    const source = this.state.source;
    this.context.host.aiPaths().then(
      (paths) => {
        if (generation !== this.statusGeneration) return;
        const found = source === "codex" ? paths.codex : paths.claude;
        this.setState({ cliStatus: found === null ? "missing" : "available" });
      },
      () => {
        if (generation === this.statusGeneration) this.setState({ cliStatus: "missing" });
      },
    );
  }

  private async loadSavedLimits(): Promise<void> {
    if (!this.limitsStore) return;
    try {
      this.claudeLimits = decodeLimitsRecord(await this.limitsStore.read(LIMITS_DOCUMENT));
    } catch {
      this.claudeLimits = undefined;
    }
  }

  /** Keeps a Claude limits snapshot (a later probe's, or a test's) in the module's folder, as the Mac keeps its record. */
  async saveClaudeLimits(record: ClaudeLimitsRecord): Promise<void> {
    this.claudeLimits = record;
    if (this.state.source === "claudeCode") this.setState({ limits: record });
    const text = encodeLimitsRecord(record);
    if (this.limitsStore && text !== undefined) await this.limitsStore.write(LIMITS_DOCUMENT, text).catch(() => undefined);
  }

  /** Reads what Claude Code appended since the last scan. `shown` turns the footer's spinner on, for a manual refresh. */
  private scanLocalStats(shown = false): void {
    if (this.scanning) {
      this.rescanPending = true;
      return;
    }
    this.scanning = true;
    if (shown) this.setState({ isFetching: true, probeError: undefined });
    const host = this.context.host;
    const read: ReadFrom = (path, offset) => host.aiLogRead("claude", path, offset).catch(() => undefined);
    void (async () => {
      let stats: ClaudeLocalStats | undefined;
      let failed = false;
      try {
        const files: TranscriptFile[] = (await host.aiLogs("claude")).map(transcript);
        stats = await this.scanner.scan(files, read, this.context.now(), this.context.timeZone());
      } catch {
        failed = true;
      }
      this.scanning = false;
      if (this.state.source === "claudeCode") {
        this.setState({
          ...(stats === undefined ? {} : { stats }),
          isFetching: false,
          probeError: failed ? "Couldn't read the Claude Code sessions" : undefined,
        });
      }
      if (this.rescanPending) {
        this.rescanPending = false;
        this.scanLocalStats();
      }
    })();
  }

  /** Reads Codex's session logs of the last seven days whole; a read already running is reused. */
  private readCodexLogs(): void {
    if (this.readingCodex) return;
    this.readingCodex = true;
    this.setState({ isFetching: true });
    const host = this.context.host;
    void (async () => {
      const now = this.context.now();
      const timeZone = this.context.timeZone();
      let usage: ReturnType<typeof summarizeCodexSessions> | undefined;
      try {
        const files = codexFilesToRead(await host.aiLogs("codex"), now, timeZone);
        const sessions = await Promise.all(files.map((file) => host.aiLogRead("codex", file.path, 0).then((bytes) => this.decoder.decode(bytes))));
        usage = summarizeCodexSessions(sessions, now, timeZone);
      } catch {
        usage = undefined;
      }
      this.readingCodex = false;
      /* The user may have switched back to Claude Code meanwhile. */
      if (this.state.source !== "codex") return;
      if (usage) this.setState({ isFetching: false, limits: usage.limits, stats: usage.stats, probeError: undefined });
      else this.setState({ isFetching: false, probeError: "Couldn't read the Codex logs" });
    })();
  }

  /** Snapshot runs only: puts the panel in a named state for the next shot. */
  showSnapshotState(state: string): void {
    if (!this.context.isSnapshot) return;
    const now = this.context.now();
    switch (state) {
      case "codex":
        this.loadDemoData("codex");
        break;
      case "missing":
        this.loadDemoData();
        this.setState({ cliStatus: "missing", limits: undefined });
        break;
      case "loading":
        this.loadDemoData();
        this.setState({ stats: undefined, isFetching: true });
        break;
      case "no-limits":
        this.loadDemoData();
        this.setState({ limits: undefined });
        break;
      case "critical":
        this.loadDemoData();
        this.setState({
          limits: {
            snapshot: {
              status: "allowed",
              fiveHour: { utilization: 0.94, resetsAt: now + 48 * 60 },
              sevenDay: { utilization: 1.0, resetsAt: demoWeeklyReset(now, this.context.timeZone()) },
            },
            fetchedAt: now - 90,
          },
        });
        break;
      default:
        this.loadDemoData();
    }
  }

  /* Demo */

  /** Realistic sample data for screenshots (`TABBI_DEMO=1`). */
  private loadDemoData(source: AIUsageSource = this.state.source): void {
    const now = this.context.now();
    const stats = source === "codex" ? codexDemoStats() : claudeDemoStats();
    this.setState({
      source,
      cliStatus: "available",
      isFetching: false,
      probeError: undefined,
      limits: {
        snapshot: {
          status: "allowed",
          fiveHour: { utilization: 0.42, resetsAt: now + 2 * 3600 + 14 * 60 + 30 },
          sevenDay: { utilization: 0.76, resetsAt: demoWeeklyReset(now, this.context.timeZone()) },
        },
        fetchedAt: now - 3 * 60,
      },
      stats,
    });
  }
}

/** A host log as the scanner's transcript record. */
function transcript(file: AiLogFile): TranscriptFile {
  return { path: file.path, size: file.size, identity: file.identity, modified: file.modified };
}

/** Next Thursday 9:00 after tomorrow, so the weekly label reads like "resets Thu 9:00 AM". */
export function demoWeeklyReset(now: Instant, timeZone: string): Instant {
  let day = now + 24 * 3600;
  for (let step = 0; step < 8; step++) {
    const wall = wallTime(day, timeZone);
    const candidate = settingTime(day, 9, 0, 0, timeZone);
    if (wall.weekday === 5 && candidate > now + 24 * 3600) return candidate;
    day += 24 * 3600;
  }
  return now + 3 * 24 * 3600;
}

function claudeDemoStats(): ClaudeLocalStats {
  return {
    today: {
      models: [
        { model: "claude-opus-5-5", tokens: { input: 18_400, output: 96_300, cacheRead: 1_642_000, cacheCreation: 212_500 }, messages: 214 },
        { model: "claude-haiku-4-5-20251001", tokens: { input: 6_100, output: 12_800, cacheRead: 148_000, cacheCreation: 31_000 }, messages: 58 },
      ],
    },
    lastSevenDays: {
      models: [
        { model: "claude-opus-5-5", tokens: { input: 96_000, output: 512_000, cacheRead: 9_870_000, cacheCreation: 1_204_000 }, messages: 1_318 },
        { model: "claude-haiku-4-5-20251001", tokens: { input: 31_000, output: 64_000, cacheRead: 702_000, cacheCreation: 158_000 }, messages: 297 },
      ],
    },
  };
}

/** Codex turns: cached input is counted as cache reads, as in its logs. */
function codexDemoStats(): ClaudeLocalStats {
  return {
    today: { models: [{ model: "gpt-5-codex", tokens: { input: 214_000, output: 38_600, cacheRead: 1_186_000, cacheCreation: 0 }, messages: 96 }] },
    lastSevenDays: {
      models: [{ model: "gpt-5-codex", tokens: { input: 1_320_000, output: 241_000, cacheRead: 7_480_000, cacheCreation: 0 }, messages: 612 }],
    },
  };
}

