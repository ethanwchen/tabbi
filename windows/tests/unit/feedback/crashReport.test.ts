import { describe, expect, it } from "vitest";
import {
  CRASH_BODY_FIELDS,
  CRASH_MAX_ENCODED_BYTES,
  CRASH_MAX_FRAME_LENGTH,
  CRASH_MAX_NAME_LENGTH,
  CRASH_MAX_THREADS,
  CRASH_MAX_THREAD_NAME_LENGTH,
  CRASH_THREAD_BODY_FIELDS,
  CrashReport,
  CrashThread,
  cleanCrashFrame,
  withoutHomeFolders,
} from "../../../src/core/feedback/crashReport";
import { crashLogHeader, crashLogText, crashReportFromLog } from "../../../src/core/feedback/crashLog";
import { DiagnosticEnvironment } from "../../../src/core/feedback/diagnosticEnvironment";
import { SYSTEM_VERSION_FIELD } from "../../../src/core/feedback/systemVersionField";

/* Port of CrashReportTests, plus the Windows home folder rules. */

const environment = new DiagnosticEnvironment("1.4.0 (52)", "10.0.26200", "tabbi");

function make(...args: Parameters<typeof CrashReport.make>): CrashReport {
  const report = CrashReport.make(...args);
  if (!report) throw new Error("expected a report");
  return report;
}

const json = (report: CrashReport) => JSON.parse(report.jsonText()) as Record<string, unknown>;
const bytes = (text: string) => new TextEncoder().encode(text).length;

describe("CrashReport", () => {
  it("carries exactly the backend fields", () => {
    const report = make(environment, "signal", "SIGSEGV", [
      new CrashThread("com.apple.main-thread", true, ["0   Tabbi   0x0000000102a3c4e8 $s5Tabbi4mainyyF + 120"]),
    ]);
    const body = json(report);
    expect(new Set(Object.keys(body))).toEqual(new Set(CRASH_BODY_FIELDS));
    expect(new Set(CRASH_BODY_FIELDS)).toEqual(new Set(["version", "macos", "edition", "kind", "name", "threads"]));
    expect(body.version).toBe("1.4.0 (52)");
    expect(body[SYSTEM_VERSION_FIELD]).toBe("10.0.26200");
    expect(body.edition).toBe("tabbi");
    expect(body.kind).toBe("signal");
    expect(body.name).toBe("SIGSEGV");
    const thread = (body.threads as Record<string, unknown>[])[0] ?? {};
    expect(new Set(Object.keys(thread))).toEqual(new Set(CRASH_THREAD_BODY_FIELDS));
    expect(thread.frames).toEqual(["0 Tabbi 0x0000000102a3c4e8 $s5Tabbi4mainyyF + 120"]);
    expect(CrashReport.fromJSON(body)?.equals(report)).toBe(true);
  });

  it("writes sorted keys and does not escape slashes", () => {
    const report = make(environment, "signal", "SIGSEGV", [new CrashThread("main", true, ["0 a/b 0x1"])]);
    expect(report.jsonText()).toBe(
      '{"edition":"tabbi","kind":"signal","macos":"10.0.26200","name":"SIGSEGV",' +
        '"threads":[{"crashed":true,"frames":["0 a/b 0x1"],"name":"main"}],"version":"1.4.0 (52)"}',
    );
  });

  it("removes home folders and non-ASCII", () => {
    const report = make(environment, "exception", "NSInvalidArgumentException: Jane's note", [
      new CrashThread("Jane\u2019s queue\n", true, [
        "3 Plugin 0x1 /Users/jane.doe/Developer/Tabbi/.build/Plugin.dylib + 4",
        "4 Disk 0x2 /Volumes/Backup HD/Users/jane/lib.dylib",
        "5 Linux 0x3 /home/jane/x",
        "6 Caf\u00e9 0x4",
      ]),
    ]);
    expect(report.name).toBe("NSInvalidArgumentExceptionJanesnote");
    expect(report.threads[0]?.name).toBe("Jane?s queue?");
    expect(report.threads[0]?.frames).toEqual([
      "3 Plugin 0x1 ~/Developer/Tabbi/.build/Plugin.dylib + 4",
      "4 Disk 0x2 ~/lib.dylib",
      "5 Linux 0x3 ~/x",
      "6 Caf? 0x4",
    ]);
    const text = report.jsonText();
    expect(text).not.toContain("/Users/");
    expect(text).not.toContain("/home/");
    expect(text).not.toContain("jane");
    expect(/^[\x20-\x7e]*$/.test(text)).toBe(true);
  });

  it("keeps to the backend's limits", () => {
    const long = "f".repeat(2000);
    const threads = Array.from(
      { length: 100 },
      (_, index) => new CrashThread("t".repeat(200), true, Array<string>(3).fill(`${index} ${long}`)),
    );
    const report = make(environment, "hang", "N".repeat(100), threads);
    expect(report.name.length).toBe(CRASH_MAX_NAME_LENGTH);
    expect(report.threads.length).toBeLessThanOrEqual(CRASH_MAX_THREADS);
    expect(report.threads.filter((thread) => thread.crashed).length).toBe(1);
    expect(report.threads[0]?.crashed).toBe(true);
    for (const thread of report.threads) {
      expect(thread.name.length).toBe(CRASH_MAX_THREAD_NAME_LENGTH);
      expect(thread.frames.every((frame) => frame.length <= CRASH_MAX_FRAME_LENGTH)).toBe(true);
    }
    expect(bytes(report.jsonText())).toBeLessThanOrEqual(CRASH_MAX_ENCODED_BYTES);
  });

  it("keeps the crashed thread when trimming an oversized report", () => {
    const frames = Array.from({ length: 128 }, (_, index) => `${index} ${"x".repeat(500)}`);
    const threads = [
      new CrashThread("worker", false, frames),
      new CrashThread("main", true, frames),
      ...Array.from({ length: 10 }, (_, index) => new CrashThread(`bg ${index}`, false, frames)),
    ];
    const report = make(environment, "signal", "SIGABRT", threads);
    expect(bytes(report.jsonText())).toBeLessThanOrEqual(CRASH_MAX_ENCODED_BYTES);
    const crashed = report.threads.find((thread) => thread.crashed);
    expect(crashed?.name).toBe("main");
    expect(crashed?.frames[0]).toBe(frames[0]);
  });

  it("is not made without frames", () => {
    expect(CrashReport.make(environment, "signal", "SIGSEGV", [])).toBeUndefined();
    expect(CrashReport.make(environment, "signal", "SIGSEGV", [new CrashThread("main", true, ["   ", ""])])).toBeUndefined();
  });

  it("shows the body word for word in the disclosure", () => {
    const report = make(environment, "signal", "SIGTRAP", [new CrashThread("main", true, ["0 Tabbi 0x1 main + 1"])]);
    expect(CrashReport.fromJSON(JSON.parse(report.disclosure))?.equals(report)).toBe(true);
    expect(report.disclosure).toContain('"name" : "SIGTRAP"');
    expect(JSON.parse(report.disclosure)).toEqual(JSON.parse(report.jsonText()));
  });
});

describe("Windows home folders", () => {
  const cases: [string, string][] = [
    ["0 app 0x1 C:\\Users\\jane\\AppData\\Local\\Tabbi\\tabbi.dll + 4", "0 app 0x1 ~\\AppData\\Local\\Tabbi\\tabbi.dll + 4"],
    ["0 app 0x1 d:\\users\\JANE\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 C:/Users/jane/x.dll", "0 app 0x1 ~/x.dll"],
    ["0 app 0x1 C:\\Users/jane\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 C:/Users\\jane/x.dll", "0 app 0x1 ~/x.dll"],
    ["0 app 0x1 \\Users\\jane\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 \\\\fileserver\\home$\\Users\\jane\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 \\\\?\\C:\\Users\\jane\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 \\\\.\\C:\\Users\\jane\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 C:\\Users\\Jane Doe\\AppData\\x.dll + 4", "0 app 0x1 ~\\AppData\\x.dll + 4"],
    ["0 app 0x1 C:\\Users\\jane", "0 app 0x1 ~"],
    ["0 app 0x1 C:\\Documents and Settings\\jane\\x.dll", "0 app 0x1 ~\\x.dll"],
    ["0 app 0x1 C:\\Program Files\\Tabbi\\tabbi.exe", "0 app 0x1 C:\\Program Files\\Tabbi\\tabbi.exe"],
  ];

  it.each(cases)("scrubs %s", (input, expected) => {
    expect(withoutHomeFolders(input)).toBe(expected);
    expect(cleanCrashFrame(input)).toBe(expected);
  });

  it("never leaves a path the backend would refuse, or the name", () => {
    for (const [input] of cases) {
      const cleaned = cleanCrashFrame(input) ?? "";
      expect(/[\\/](users|home)[\\/]/i.test(cleaned)).toBe(false);
      expect(cleaned.toLowerCase()).not.toContain("jane");
    }
    expect(withoutHomeFolders("C:\\Users\\a\\x C:\\Users\\b\\y /Users/c/z")).toBe("~\\x ~\\y ~/z");
  });
});

describe("CrashLog", () => {
  it("turns the handler's output into a report", () => {
    const text =
      crashLogHeader(environment) +
      [
        "kind signal",
        "name SIGSEGV",
        "crashed-thread com.apple.main-thread",
        "0   Tabbi                               0x0000000102a3c4e8 crashHandler + 52",
        "1   libsystem_platform.dylib            0x000000018e2a2584 _sigtramp + 56",
        "thread",
        "0   libsystem_kernel.dylib              0x000000018e1f1c34 mach_msg2_trap + 8",
        "",
      ].join("\n");
    const report = crashReportFromLog(text);
    expect(report?.environment.equals(environment)).toBe(true);
    expect(report?.kind).toBe("signal");
    expect(report?.name).toBe("SIGSEGV");
    const expected = [
      new CrashThread("com.apple.main-thread", true, [
        "0 Tabbi 0x0000000102a3c4e8 crashHandler + 52",
        "1 libsystem_platform.dylib 0x000000018e2a2584 _sigtramp + 56",
      ]),
      new CrashThread("", false, ["0 libsystem_kernel.dylib 0x000000018e1f1c34 mach_msg2_trap + 8"]),
    ];
    expect(report?.threads.length).toBe(2);
    report?.threads.forEach((thread, index) => {
      const want = expected[index];
      expect(want && thread.equals(want)).toBe(true);
    });
  });

  it("reads back what it wrote", () => {
    const threads = [new CrashThread("main", true, ["0 Tabbi 0x1 f + 2", "1 Tabbi 0x2 g + 3"])];
    const text = crashLogText(environment, "exception", "NSRangeException", threads);
    const expected = make(environment, "exception", "NSRangeException", threads);
    expect(crashReportFromLog(text)?.equals(expected)).toBe(true);
  });

  it("ignores broken logs", () => {
    expect(crashReportFromLog("")).toBeUndefined();
    expect(crashReportFromLog("something else\nkind signal\nthread main\n0 x")).toBeUndefined();
    expect(crashReportFromLog(`${crashLogHeader(environment)}kind meltdown\nthread main\n0 x\n`)).toBeUndefined();
    /* The handler died before it wrote a frame. */
    expect(crashReportFromLog(`${crashLogHeader(environment)}kind signal\nname SIGBUS\ncrashed-thread main\n`)).toBeUndefined();
  });
});
