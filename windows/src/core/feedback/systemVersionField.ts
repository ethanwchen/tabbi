/*
 * The one name under which the system version travels: the crash report
 * body and the Suggest link's query both read it. The backend requires
 * `macos` today; once it also accepts the optional `os` field, switching
 * this constant to "os" moves every Windows report and link over at once.
 */

/** The two names the backend knows (or will know) for the system version. */
export type SystemVersionField = "macos" | "os";

/** The field Windows sends now. Change to "os" once the backend accepts it. */
export const SYSTEM_VERSION_FIELD = "macos" as const satisfies SystemVersionField;

/** The field to send the system version under, for code that should not care which. */
export function systemVersionField(): SystemVersionField {
  return SYSTEM_VERSION_FIELD;
}
