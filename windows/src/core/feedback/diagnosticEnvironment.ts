/*
 * Port of DiagnosticEnvironment: the three facts about this copy of Tabbi
 * that a suggestion or a crash report carries (the app version, the system
 * version and the edition id). Nothing else about the PC or the person goes
 * with them, and each value is cleaned to a short run of plain characters.
 * On Windows the system version is the Windows version ("10.0.26200"),
 * which the host passes in.
 */

/** Longest value kept for each field; real ones are far shorter. */
export const MAX_DIAGNOSTIC_FIELD_LENGTH = 32;

const ALLOWED = /[A-Za-z0-9 ._\-()]/;

/** Keeps letters, digits, spaces and `. _ - ( )`, trimmed and capped; undefined when nothing is left. */
export function cleanDiagnosticField(value: string): string | undefined {
  const kept = Array.from(value)
    .filter((char) => ALLOWED.test(char))
    .join("")
    .trim();
  const capped = kept.slice(0, MAX_DIAGNOSTIC_FIELD_LENGTH).trim();
  return capped === "" ? undefined : capped;
}

/**
 * "1.4.0 (52)" from the version and the build number, "1.4.0" without a
 * build number (or one equal to the version), and "development" without a
 * version (a dev build). Port of `DiagnosticEnvironment.appVersion(infoDictionary:)`.
 */
export function diagnosticAppVersion(version: string | undefined, build?: string): string {
  if (version === undefined) return "development";
  if (build === undefined || build === version) return version;
  return `${version} (${build})`;
}

export class DiagnosticEnvironment {
  /** "1.4.0 (52)", or "development". */
  readonly appVersion: string;
  /** The Windows (or macOS) version, "10.0.26200". */
  readonly systemVersion: string;
  /** The edition id, such as "tabbi". */
  readonly edition: string;

  constructor(appVersion: string, systemVersion: string, edition: string) {
    this.appVersion = cleanDiagnosticField(appVersion) ?? "unknown";
    this.systemVersion = cleanDiagnosticField(systemVersion) ?? "unknown";
    this.edition = cleanDiagnosticField(edition) ?? "unknown";
  }

  equals(other: DiagnosticEnvironment): boolean {
    return this.appVersion === other.appVersion && this.systemVersion === other.systemVersion && this.edition === other.edition;
  }
}
