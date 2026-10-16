import { base64 } from "../ai/aiWireFormat";
import type { DocumentStore } from "../persistence/documentStore";
import { isJSONObject, stringifyJSON } from "../persistence/json";
import type { Instant } from "../time";
import { aggregateUsage, type ClaudeLocalStats, windowStart } from "./claudeLocalStats";
import { type ClaudeTokenUsage, type ClaudeUsageRecord, parseUsageRecord } from "./claudeUsageRecord";
import { sha256 } from "./sha256";

/** `%USERPROFILE%\.claude\projects`, where Claude Code keeps session transcripts. */
export function claudeProjectsRoot(userProfile: string): string {
  return `${userProfile.replace(/[\\/]+$/, "")}\\.claude\\projects`;
}

/** One transcript the host found under the root (every `*.jsonl`, hidden files skipped). */
export interface TranscriptFile {
  path: string;
  size: number;
  /**
   * Changes when the file is replaced: the 64-bit file id (the NTFS file
   * index, where the Mac uses the inode) as a decimal string. An identity
   * that isn't one is still compared, but the index can't persist it, so
   * that file is read from the start after a relaunch.
   */
  identity: string;
  modified: Instant;
}

/**
 * Reads `path` from byte `offset` to its end. Undefined when it can't be
 * read. The host does the I/O; the core never touches the file system.
 */
export type ReadFrom = (path: string, offset: number) => Promise<Uint8Array | undefined>;

/** Port of the scanner's private FileState. */
export interface ScanFileState {
  offset: number;
  identity: string;
}

/** Port of the scanner's private StoredRecord; `timestamp` is seconds since 1970. */
export interface ScanStoredRecord {
  model: string;
  timestamp: Instant;
  usage: ClaudeTokenUsage;
}

/**
 * What the index holds: each file's read state by path, and the records of
 * the window keyed by their message key (the first 16 bytes of the SHA-256
 * of the message id, as 32 hex digits).
 */
export interface ClaudeUsageScanIndex {
  files: Map<string, ScanFileState>;
  records: Map<string, ScanStoredRecord>;
}

/** Lines longer than this can't be usage records worth the memory; they are skipped. */
export const MAX_LINE_LENGTH = 32 << 20;

/**
 * Port of ClaudeUsageLogScanner.indexURL(in:): `ClaudeUsage/scan-index.json`
 * in the edition's folder. A cache: a missing index only makes the next
 * scan read every transcript.
 */
export const CLAUDE_USAGE_SCAN_INDEX_NAME = "ClaudeUsage/scan-index.json";

/**
 * Port of Index.currentVersion. The index is a cache with its own `version`
 * key, not a VersionedJSON document: any other version is no index at all,
 * so there are no migration steps.
 */
export const SCAN_INDEX_VERSION = 2;

/** Key high, key low, model, timestamp bits, then the four token counts, all little-endian. */
export const PACKED_RECORD_SIZE = 8 + 8 + 4 + 8 + 4 * 8;

const UINT64_MAX = 0xffff_ffff_ffff_ffffn;
const utf8 = new TextEncoder();

/** The record key the Mac's MessageKey holds: the first 128 bits of the id's SHA-256, as hex. */
export function messageKey(messageID: string): string {
  return hex(sha256(utf8.encode(messageID)).subarray(0, 16));
}

function hex(bytes: Uint8Array): string {
  let text = "";
  for (const byte of bytes) text += byte.toString(16).padStart(2, "0");
  return text;
}

function isUInt64(text: string): boolean {
  return /^(0|[1-9][0-9]*)$/.test(text) && BigInt(text) <= UINT64_MAX;
}

/**
 * Port of saveIndex's encoding: `{"version":2,"files":{path:{"offset","identity"}},
 * "models":[...],"records":"<base64>"}` as the default JSONEncoder writes it
 * (no spaces, keys in declaration order). Records are packed into one
 * binary blob so loading a week of them is a single allocation, with model
 * names interned into `models`. Identities are written as bare 64-bit
 * integers, which a JS number can't hold exactly, so this writes the JSON
 * text itself rather than `stringifyJSON` of one value.
 */
export function encodeScanIndex(index: ClaudeUsageScanIndex): string {
  const files: string[] = [];
  for (const [path, state] of index.files) {
    if (!isUInt64(state.identity) || !Number.isSafeInteger(state.offset) || state.offset < 0) continue;
    files.push(`${stringifyJSON(path)}:{"offset":${state.offset},"identity":${state.identity}}`);
  }
  const models: string[] = [];
  const modelIndex = new Map<string, number>();
  const packed = new Uint8Array(index.records.size * PACKED_RECORD_SIZE);
  const view = new DataView(packed.buffer);
  let offset = 0;
  for (const [key, record] of index.records) {
    let model = modelIndex.get(record.model);
    if (model === undefined) {
      model = models.length;
      models.push(record.model);
      modelIndex.set(record.model, model);
    }
    for (let byte = 0; byte < 16; byte++) packed[offset + byte] = Number.parseInt(key.slice(byte * 2, byte * 2 + 2), 16) || 0;
    view.setUint32(offset + 16, model, true);
    view.setFloat64(offset + 20, record.timestamp, true);
    const counts = [record.usage.input, record.usage.output, record.usage.cacheRead, record.usage.cacheCreation];
    counts.forEach((count, slot) => view.setBigInt64(offset + 28 + slot * 8, BigInt(Math.trunc(count)), true));
    offset += PACKED_RECORD_SIZE;
  }
  return `{"version":${SCAN_INDEX_VERSION},"files":{${files.join(",")}},"models":${stringifyJSON(models)},"records":${stringifyJSON(base64(packed))}}`;
}

/* Foundation's Data(base64Encoded:): standard alphabet, padded, nothing else. */
function decodeBase64(text: string): Uint8Array | undefined {
  if (text.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) return undefined;
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

/*
 * Keeps each `identity` as its source digits, since a 64-bit file id can
 * be past what a JS number holds exactly. Where the runtime gives no
 * source text, the rounded number only costs that file a re-read.
 */
function keepIdentityDigits(key: string, value: unknown, context?: { source?: string }): unknown {
  if (key !== "identity" || typeof value !== "number") return value;
  if (context?.source !== undefined) return context.source;
  return Number.isInteger(value) && value >= 0 ? BigInt(value).toString() : value;
}

/**
 * Port of loadIndex's decoding: the index in `text`, or undefined when it
 * isn't version 2 of the right shape, its blob isn't whole records, or a
 * record names a model the list doesn't have. Keys it doesn't know are
 * ignored.
 */
export function decodeScanIndex(text: string): ClaudeUsageScanIndex | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text, keepIdentityDigits);
  } catch {
    return undefined;
  }
  if (!isJSONObject(parsed) || parsed.version !== SCAN_INDEX_VERSION) return undefined;
  const { files: storedFiles, models, records: storedRecords } = parsed;
  if (!isJSONObject(storedFiles) || !Array.isArray(models) || typeof storedRecords !== "string") return undefined;
  const names: string[] = [];
  for (const model of models) {
    if (typeof model !== "string") return undefined;
    names.push(model);
  }

  const files = new Map<string, ScanFileState>();
  for (const [path, state] of Object.entries(storedFiles)) {
    if (!isJSONObject(state)) return undefined;
    const { offset, identity } = state;
    if (typeof offset !== "number" || !Number.isSafeInteger(offset) || offset < 0) return undefined;
    if (typeof identity !== "string" || !isUInt64(identity)) return undefined;
    files.set(path, { offset, identity });
  }

  const packed = decodeBase64(storedRecords);
  if (!packed || packed.length % PACKED_RECORD_SIZE !== 0) return undefined;
  const view = new DataView(packed.buffer);
  const records = new Map<string, ScanStoredRecord>();
  for (let offset = 0; offset < packed.length; offset += PACKED_RECORD_SIZE) {
    const model = names[view.getUint32(offset + 16, true)];
    if (model === undefined) return undefined;
    const count = (slot: number) => Number(view.getBigInt64(offset + 28 + slot * 8, true));
    records.set(hex(packed.subarray(offset, offset + 16)), {
      model,
      timestamp: view.getFloat64(offset + 20, true),
      usage: { input: count(0), output: count(1), cacheRead: count(2), cacheCreation: count(3) },
    });
  }
  return { files, records };
}

export interface ClaudeUsageLogScannerOptions {
  /** Where the index persists between launches; without one it lives in memory only (snapshot runs). */
  store?: DocumentStore;
  /** The index's document name in `store`. */
  indexName?: string;
}

/**
 * Port of ClaudeUsageLogScanner's logic: incrementally reads Claude Code
 * session transcripts and keeps the usage records of the last seven days.
 * Files last modified before the window are skipped without opening them,
 * each file's read offset is remembered, and persisted with the records so
 * unchanged bytes are never read again, not even after a relaunch. A
 * trailing partial line (still being written) waits for the next scan, and
 * a file that shrank or was replaced is read from the start. Records are
 * keyed by a hash of the message id, so copies of a message (content-block
 * lines, resumed or forked sessions) count once.
 */
export class ClaudeUsageLogScanner {
  private files = new Map<string, ScanFileState>();
  private records = new Map<string, ScanStoredRecord>();
  private indexLoaded = false;
  private readonly decoder = new TextDecoder();
  private readonly store: DocumentStore | undefined;
  private readonly indexName: string;

  constructor(options: ClaudeUsageLogScannerOptions = {}) {
    this.store = options.store;
    this.indexName = options.indexName ?? CLAUDE_USAGE_SCAN_INDEX_NAME;
  }

  /** Reads whatever was appended since the last scan and returns fresh stats. */
  async scan(transcripts: readonly TranscriptFile[], read: ReadFrom, now: Instant, timeZone: string): Promise<ClaudeLocalStats> {
    const start = windowStart(now, timeZone);
    if (!this.indexLoaded) {
      this.indexLoaded = true;
      await this.loadIndex();
    }
    let bytesRead = 0;
    const seen = new Set<string>();
    for (const file of transcripts) {
      seen.add(file.path);
      bytesRead += await this.scanFile(file, read, start);
    }
    const staleFiles = [...this.files.keys()].filter((path) => !seen.has(path));
    for (const path of staleFiles) this.files.delete(path);
    const recordCount = this.records.size;
    for (const [key, record] of this.records) if (record.timestamp < start) this.records.delete(key);
    if (bytesRead > 0 || staleFiles.length > 0 || this.records.size !== recordCount) await this.saveIndex();
    /* Aggregation ignores message ids; records are already unique. */
    const records: ClaudeUsageRecord[] = [...this.records.values()].map((record) => ({ messageID: "", ...record }));
    return aggregateUsage(records, now, timeZone);
  }

  /** Returns the number of bytes read. */
  private async scanFile(file: TranscriptFile, read: ReadFrom, start: Instant): Promise<number> {
    if (file.modified < start) {
      /*
       * Nothing in it can fall inside the window. Forget it: if it is ever
       * appended to, reading from the start is correct because records
       * dedupe by message id.
       */
      this.files.delete(file.path);
      return 0;
    }
    let state = this.files.get(file.path) ?? { offset: 0, identity: file.identity };
    if (file.size < state.offset || state.identity !== file.identity) state = { offset: 0, identity: file.identity };
    this.files.set(file.path, state);
    if (file.size <= state.offset) return 0;
    const bytes = await read(file.path, state.offset);
    if (!bytes) return 0;
    let lineStart = 0;
    for (let index = 0; index < bytes.length; index++) {
      if (bytes[index] !== 0x0a) continue;
      if (index - lineStart <= MAX_LINE_LENGTH) this.ingest(bytes.subarray(lineStart, index), start);
      lineStart = index + 1;
    }
    /* A trailing partial line is left for the next scan, unless it is already too long to matter. */
    const consumed = bytes.length - lineStart > MAX_LINE_LENGTH ? bytes.length : lineStart;
    this.files.set(file.path, { offset: state.offset + consumed, identity: file.identity });
    return bytes.length;
  }

  private ingest(line: Uint8Array, start: Instant): void {
    const record = parseUsageRecord(this.decoder.decode(line));
    if (!record || record.timestamp < start) return;
    this.records.set(messageKey(record.messageID), { model: record.model, timestamp: record.timestamp, usage: record.usage });
  }

  /* A cache: an index that is missing, unreadable or of another version only means a full scan. */
  private async loadIndex(): Promise<void> {
    if (!this.store) return;
    let text: string | undefined;
    try {
      text = await this.store.read(this.indexName);
    } catch {
      return;
    }
    const index = text === undefined ? undefined : decodeScanIndex(text);
    if (!index) return;
    this.files = index.files;
    this.records = index.records;
  }

  /* Best effort: a failed write only costs a re-read next launch. */
  private async saveIndex(): Promise<void> {
    if (!this.store) return;
    try {
      await this.store.write(this.indexName, encodeScanIndex({ files: this.files, records: this.records }));
    } catch {
      /* Nothing to do: the next launch reads the transcripts again. */
    }
  }
}
