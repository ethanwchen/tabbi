import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { CRASH_BODY_FIELDS, CRASH_THREAD_BODY_FIELDS } from "../../../src/core/feedback/crashReport";
import { SUGGEST_LINK_FIELDS } from "../../../src/core/feedback/feedbackLink";
import * as Wire from "../../../src/core/party/partyWire";
import { APPLE_AUTH_BODY_FIELDS } from "../../../src/core/sync/syncClient";

/*
 * Holds the Windows client to the backend's own TypeScript contract.
 *
 * The type checks live in `contracts/backend.contract.ts`, outside the
 * Windows tsconfig (see its header). This compiles that file with the
 * Windows compiler options and fails on any error reported in it. The
 * values the types can't pin (sizes computed in the backend) are compared
 * at run time, loading the backend's modules by path so the Windows
 * typecheck never follows them.
 */

const windowsRoot = fileURLToPath(new URL("../../../", import.meta.url));
const contractFile = fileURLToPath(new URL("../../../contracts/backend.contract.ts", import.meta.url));
const backendFile = (path: string) => pathToFileURL(fileURLToPath(new URL(`../../../../backend/${path}`, import.meta.url))).href;

function contractDiagnostics(): string[] {
  const configPath = ts.findConfigFile(windowsRoot, ts.sys.fileExists, "tsconfig.json");
  if (configPath === undefined) throw new Error("no tsconfig.json");
  const config = ts.readConfigFile(configPath, ts.sys.readFile);
  const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, windowsRoot);
  const program = ts.createProgram({ rootNames: [contractFile], options: { ...parsed.options, noEmit: true } });
  const source = program.getSourceFile(contractFile);
  if (source === undefined) throw new Error("the contract file was not loaded");
  return [...program.getSyntacticDiagnostics(source), ...program.getSemanticDiagnostics(source)].map((diagnostic) => {
    const where = diagnostic.start === undefined ? "" : `line ${source.getLineAndCharacterOfPosition(diagnostic.start).line + 1}: `;
    return where + ts.flattenDiagnosticMessageText(diagnostic.messageText, "\n");
  });
}

/* Loads a backend module by a path the Windows typecheck does not follow. */
async function backend(path: string): Promise<Readonly<Record<string, unknown>>> {
  const module: unknown = await import(/* @vite-ignore */ backendFile(path));
  return module as Readonly<Record<string, unknown>>;
}

describe("backend contract", () => {
  it("type-checks the client's wire types against the backend's own", () => {
    expect(contractDiagnostics()).toEqual([]);
  }, 60_000);

  it("uses the backend's request fields, limits and paths at run time", async () => {
    const [lib, profile, presence, party, moderation, sync, webauth, apple, crashes, suggestions] = await Promise.all([
      backend("src/lib.ts"),
      backend("src/profile.ts"),
      backend("src/presence.ts"),
      backend("src/party.ts"),
      backend("src/moderation.ts"),
      backend("src/sync.ts"),
      backend("src/webauth.ts"),
      backend("src/apple.ts"),
      backend("src/crashes.ts"),
      backend("src/suggestions.ts"),
    ]);
    expect(Wire.PROFILE_BODY_FIELDS).toEqual(profile.PROFILE_FIELDS);
    expect(Wire.HEARTBEAT_BODY_FIELDS).toEqual(presence.PRESENCE_FIELDS);
    expect(Wire.JOIN_BODY_FIELDS).toEqual(party.JOIN_FIELDS);
    expect(Wire.SESSION_BODY_FIELDS).toEqual(party.SESSION_FIELDS);
    expect(Wire.REPORT_BODY_FIELDS).toEqual(moderation.REPORT_FIELDS);
    expect(Wire.REPORT_REASONS).toEqual(moderation.REPORT_REASONS);
    expect(Wire.MAX_REPORT_NOTE).toBe(moderation.MAX_REPORT_NOTE);
    expect(Wire.SYNC_BODY_FIELDS).toEqual(sync.SYNC_FIELDS);
    expect(Wire.MAX_SYNC_BYTES).toBe(sync.MAX_SYNC_BYTES);
    expect(Wire.MAX_BODY_BYTES).toBe(lib.MAX_BODY_BYTES);
    expect(Wire.PROTOCOL_VERSION).toBe(lib.PROTOCOL_VERSION);
    expect(Wire.PROTOCOL_HEADER).toBe(lib.PROTOCOL_HEADER);
    expect(Wire.WEB_TOKEN_BODY_FIELDS).toEqual(webauth.WEB_TOKEN_FIELDS);
    expect(Wire.WEB_TOKEN_PATH).toBe(webauth.WEB_TOKEN_PATH);
    expect(Wire.WEB_CALLBACK_PATH).toBe(webauth.WEB_CALLBACK_PATH);
    expect(Wire.APP_CALLBACK_URL).toBe(webauth.APP_CALLBACK_URL);
    expect(APPLE_AUTH_BODY_FIELDS).toEqual(apple.APPLE_AUTH_FIELDS);
    expect(CRASH_BODY_FIELDS).toEqual(crashes.CRASH_FIELDS);
    expect(CRASH_THREAD_BODY_FIELDS).toEqual(crashes.CRASH_THREAD_FIELDS);
    expect(suggestions.SUGGESTION_FIELDS).toEqual(expect.arrayContaining([...SUGGEST_LINK_FIELDS]));
  });

  it("derives the web sign-in nonce exactly as the backend does", async () => {
    const webauth = await backend("src/webauth.ts");
    const webNonce = webauth.webNonce as (state: string) => Promise<string>;
    const { webSignInNonce } = await import("../../../src/core/sync/appleWebSignIn");
    for (const state of ["abc", "x".repeat(43), "ab-_CD12".repeat(6)]) expect(await webSignInNonce(state)).toBe(await webNonce(state));
  });
});
