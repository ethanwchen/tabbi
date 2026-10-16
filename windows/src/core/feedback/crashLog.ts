import { CRASH_KINDS, CrashReport, CrashThread, type CrashKind } from "./crashReport";
import { DiagnosticEnvironment } from "./diagnosticEnvironment";

/*
 * Port of CrashLog: the small text file a crash handler leaves on disk,
 * read on the next launch to build a `CrashReport`. A handler that runs as
 * the process dies cannot build JSON, so it writes this plain format: the
 * header (prepared at launch), a `kind` and a `name` line, then for each
 * thread a `thread` or `crashed-thread` line followed by its frames. The
 * header keeps the Mac's `macos` key: it is a file format, not the wire.
 */

export const CRASH_LOG_MAGIC = "tabbi-crash 1";

export const CrashLogKey = {
  version: "version",
  macos: "macos",
  edition: "edition",
  kind: "kind",
  name: "name",
  thread: "thread",
  crashedThread: "crashed-thread",
} as const;

/** The lines the crash handler writes first, prepared once at launch. */
export function crashLogHeader(environment: DiagnosticEnvironment): string {
  return (
    `${CRASH_LOG_MAGIC}\n${CrashLogKey.version} ${environment.appVersion}\n` +
    `${CrashLogKey.macos} ${environment.systemVersion}\n${CrashLogKey.edition} ${environment.edition}\n`
  );
}

/** The whole file for a crash the app can describe itself (an uncaught exception or a hang). */
export function crashLogText(environment: DiagnosticEnvironment, kind: CrashKind, name: string, threads: readonly CrashThread[]): string {
  let text = `${crashLogHeader(environment)}${CrashLogKey.kind} ${kind}\n${CrashLogKey.name} ${name}\n`;
  for (const thread of threads) {
    text += `${thread.crashed ? CrashLogKey.crashedThread : CrashLogKey.thread} ${thread.name}\n`;
    text += thread.frames.map((frame) => `${frame}\n`).join("");
  }
  return text;
}

function split(line: string): [string, string] {
  const space = line.indexOf(" ");
  return space < 0 ? [line, ""] : [line.slice(0, space), line.slice(space + 1)];
}

/** The report a crash log describes, cleaned; undefined for a file that is not one, has no known kind, or holds no frame. */
export function crashReportFromLog(text: string): CrashReport | undefined {
  /* Swift's isNewline: CR, LF, CRLF, vertical tab, form feed, NEL and the Unicode line and paragraph separators. */
  const lines = text.split(new RegExp("\\r\\n|[\\n\\r\\v\\f\\u0085\\u2028\\u2029]")).filter((line) => line !== "");
  if (lines.shift() !== CRASH_LOG_MAGIC) return undefined;
  const fields = new Map<string, string>();
  const threads: { name: string; crashed: boolean; frames: string[] }[] = [];
  for (const line of lines) {
    const [key, value] = split(line);
    if (key === CrashLogKey.thread || key === CrashLogKey.crashedThread) {
      threads.push({ name: value, crashed: key === CrashLogKey.crashedThread, frames: [] });
    } else if (threads.length > 0) {
      threads[threads.length - 1]?.frames.push(line);
    } else if (!fields.has(key)) {
      fields.set(key, value);
    }
  }
  const kind = fields.get(CrashLogKey.kind);
  if (kind === undefined || !(CRASH_KINDS as readonly string[]).includes(kind)) return undefined;
  const environment = new DiagnosticEnvironment(
    fields.get(CrashLogKey.version) ?? "",
    fields.get(CrashLogKey.macos) ?? "",
    fields.get(CrashLogKey.edition) ?? "",
  );
  return CrashReport.make(
    environment,
    kind as CrashKind,
    fields.get(CrashLogKey.name) ?? "",
    threads.map((thread) => new CrashThread(thread.name, thread.crashed, thread.frames)),
  );
}
