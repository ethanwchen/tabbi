import type { Instant } from "../time";
import { aggregateUsage, type ClaudeLocalStats, windowStart } from "./claudeLocalStats";
import { type ClaudeTokenUsage, type ClaudeUsageRecord, parseUsageRecord } from "./claudeUsageRecord";

/** `%USERPROFILE%\.claude\projects`, where Claude Code keeps session transcripts. */
export function claudeProjectsRoot(userProfile: string): string {
  return `${userProfile.replace(/[\\/]+$/, "")}\\.claude\\projects`;
}

/** One transcript the host found under the root (every `*.jsonl`, hidden files skipped). */
export interface TranscriptFile {
  path: string;
  size: number;
  /** Changes when the file is replaced (the file index on NTFS). */
  identity: string;
  modified: Instant;
}

/**
 * Reads `path` from byte `offset` to its end. Undefined when it can't be
 * read. The host does the I/O; the core never touches the file system.
 */
export type ReadFrom = (path: string, offset: number) => Promise<Uint8Array | undefined>;

interface FileState {
  offset: number;
  identity: string;
}

interface StoredRecord {
  model: string;
  timestamp: Instant;
  usage: ClaudeTokenUsage;
}

/** Lines longer than this can't be usage records worth the memory; they are skipped. */
export const MAX_LINE_LENGTH = 32 << 20;

/** The scanner's state as JSON, so a relaunch never reads unchanged bytes again. A cache: anything unreadable means a full scan. */
export interface ClaudeUsageScanIndex {
  schemaVersion: 1;
  files: Record<string, FileState>;
  records: Record<string, StoredRecord>;
}

/**
 * Port of ClaudeUsageLogScanner's logic: incrementally reads Claude Code
 * session transcripts and keeps the usage records of the last seven days.
 * Files last modified before the window are skipped without opening them,
 * each file's read offset is remembered so unchanged bytes are never read
 * again, a trailing partial line (still being written) waits for the next
 * scan, and a file that shrank or was replaced is read from the start.
 * Records are keyed by message id, so copies of a message (content-block
 * lines, resumed or forked sessions) count once.
 */
export class ClaudeUsageLogScanner {
  private files = new Map<string, FileState>();
  private records = new Map<string, StoredRecord>();
  private readonly decoder = new TextDecoder();

  constructor(index?: ClaudeUsageScanIndex) {
    if (index) this.restore(index);
  }

  /** Reads whatever was appended since the last scan and returns fresh stats. */
  async scan(transcripts: readonly TranscriptFile[], read: ReadFrom, now: Instant, timeZone: string): Promise<ClaudeLocalStats> {
    const start = windowStart(now, timeZone);
    const seen = new Set<string>();
    for (const file of transcripts) {
      seen.add(file.path);
      await this.scanFile(file, read, start);
    }
    for (const path of [...this.files.keys()]) if (!seen.has(path)) this.files.delete(path);
    for (const [id, record] of this.records) if (record.timestamp < start) this.records.delete(id);
    const records: ClaudeUsageRecord[] = [...this.records.values()].map((record) => ({ messageID: "", ...record }));
    return aggregateUsage(records, now, timeZone);
  }

  private async scanFile(file: TranscriptFile, read: ReadFrom, start: Instant): Promise<void> {
    if (file.modified < start) {
      /*
       * Nothing in it can fall inside the window. Forget it: if it is ever
       * appended to, reading from the start is correct because records
       * dedupe by message id.
       */
      this.files.delete(file.path);
      return;
    }
    let state = this.files.get(file.path) ?? { offset: 0, identity: file.identity };
    if (file.size < state.offset || state.identity !== file.identity) state = { offset: 0, identity: file.identity };
    this.files.set(file.path, state);
    if (file.size <= state.offset) return;
    const bytes = await read(file.path, state.offset);
    if (!bytes) return;
    let lineStart = 0;
    for (let index = 0; index < bytes.length; index++) {
      if (bytes[index] !== 0x0a) continue;
      if (index - lineStart <= MAX_LINE_LENGTH) this.ingest(bytes.subarray(lineStart, index), start);
      lineStart = index + 1;
    }
    /* A trailing partial line is left for the next scan, unless it is already too long to matter. */
    const consumed = bytes.length - lineStart > MAX_LINE_LENGTH ? bytes.length : lineStart;
    this.files.set(file.path, { offset: state.offset + consumed, identity: file.identity });
  }

  private ingest(line: Uint8Array, start: Instant): void {
    const record = parseUsageRecord(this.decoder.decode(line));
    if (!record || record.timestamp < start) return;
    this.records.set(record.messageID, { model: record.model, timestamp: record.timestamp, usage: record.usage });
  }

  /** The state to persist between launches. */
  index(): ClaudeUsageScanIndex {
    return { schemaVersion: 1, files: Object.fromEntries(this.files), records: Object.fromEntries(this.records) };
  }

  private restore(index: ClaudeUsageScanIndex): void {
    this.files = new Map(Object.entries(index.files));
    this.records = new Map(Object.entries(index.records));
  }
}

/** Reads a stored index leniently: anything but version 1 of the right shape is no index. */
export function decodeScanIndex(value: unknown): ClaudeUsageScanIndex | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  const index = value as Partial<ClaudeUsageScanIndex>;
  if (index.schemaVersion !== 1 || typeof index.files !== "object" || typeof index.records !== "object") return undefined;
  if (index.files === null || index.records === null) return undefined;
  const files = Object.values(index.files).every((f) => typeof f?.offset === "number" && typeof f.identity === "string");
  const records = Object.values(index.records).every(
    (r) => typeof r?.model === "string" && typeof r.timestamp === "number" && typeof r.usage === "object" && r.usage !== null,
  );
  return files && records ? (index as ClaudeUsageScanIndex) : undefined;
}
