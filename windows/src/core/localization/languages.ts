/*
 * The languages Tabbi ships and how one is picked. Port of L10n: the same
 * twelve language tags (the Mac's `.lproj` names), the same rule for the
 * user's best translated language, and right-to-left detection. Nothing
 * here reads the machine: the user's preferred languages are passed in.
 */

/** The language the strings are written in; catalog keys are its text. */
export const SOURCE_LANGUAGE = "en";

/** The shipped languages, as the Mac's `.lproj` names (BCP 47 tags). */
export const LANGUAGES = ["en", "ar", "de", "es", "fr", "fil", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"] as const;

export type Language = (typeof LANGUAGES)[number];

export function isLanguage(value: string): value is Language {
  return (LANGUAGES as readonly string[]).includes(value);
}

/* Scripts written right to left (ISO 15924), the ones CLDR marks rtl. */
const RIGHT_TO_LEFT_SCRIPTS = new Set(["Arab", "Hebr", "Thaa", "Syrc", "Nkoo", "Adlm", "Rohg", "Mand", "Samr", "Mend"]);

/* The tag with its likely script and region filled in ("zh-TW" is zh-Hant-TW), or nil for a malformed tag. */
function maximized(tag: string): Intl.Locale | undefined {
  try {
    return new Intl.Locale(tag).maximize();
  } catch {
    return undefined;
  }
}

/** Whether `language` (any BCP 47 tag, such as "ar" or "ar-SA") is written right to left. */
export function isRightToLeft(language: string): boolean {
  const script = maximized(language)?.script;
  return script !== undefined && RIGHT_TO_LEFT_SCRIPTS.has(script);
}

/** The text direction for `dir` on a root element. */
export function textDirection(language: string): "rtl" | "ltr" {
  return isRightToLeft(language) ? "rtl" : "ltr";
}

/**
 * The translated language that best fits `preferences` (the user's
 * languages, most preferred first, such as `navigator.languages`), or the
 * source language. Like Bundle.preferredLocalizations, the first preference
 * that any available language serves wins: an exact tag first, then the
 * same language in the same script ("zh-TW" is zh-Hant, "pt-PT" still
 * reads pt-BR), so a later preference never beats an earlier one.
 */
export function languageFor(preferences: readonly string[], available: readonly string[] = LANGUAGES): string {
  for (const preference of preferences) {
    const exact = available.find((language) => language.toLowerCase() === preference.toLowerCase());
    if (exact) return exact;
    const wanted = maximized(preference);
    if (!wanted) continue;
    const candidates = available.filter((language) => {
      const offered = maximized(language);
      return offered?.language === wanted.language && offered.script === wanted.script;
    });
    const sameRegion = candidates.find((language) => maximized(language)?.region === wanted.region);
    const match = sameRegion ?? candidates[0];
    if (match) return match;
  }
  return available.includes(SOURCE_LANGUAGE) ? SOURCE_LANGUAGE : (available[0] ?? SOURCE_LANGUAGE);
}
