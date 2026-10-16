/*
 * User-facing text, keyed exactly like the Mac's string catalog
 * (Localizable.xcstrings): the key is the English text with Swift format
 * specifiers, so `String(localized: "\(count) left")` on the Mac is
 * `tr("%lld left", count)` here, and both apps share every translation.
 *
 * This is the English-only first cut that every port can call today; the
 * localization port replaces `lookup` with the catalog for the user's
 * language (plural variations included) without changing any call site.
 */

export type FormatArg = string | number;

type Lookup = (key: string, args: readonly FormatArg[]) => string | undefined;

let lookup: Lookup = () => undefined;
let language = "en";

/** Installs the catalog lookup for `nextLanguage` (the localization port calls this). */
export function setLookup(next: Lookup, nextLanguage = "en"): void {
  lookup = next;
  language = nextLanguage;
}

/**
 * The language `tr` reads, standing in for the Mac's Locale.current where a
 * port formats numbers or arguments the way String(localized:) does.
 */
export function currentLanguage(): string {
  return language;
}

/*
 * Western digits in the locale's grouping: Foundation writes them in every
 * shipped language, while some ICU builds give plain "ar" Arabic-Indic ones.
 */
export function numberLocale(locale: string): string {
  const tag = new Intl.Locale(locale);
  return tag.numberingSystem === undefined && tag.language === "ar" ? `${locale}-u-nu-latn` : locale;
}

/**
 * The localized text for a catalog key, with its arguments filled in. Whole
 * numbers take the language's grouping ("1,500", "1.500"), as Foundation
 * writes them into a String(localized:).
 */
export function tr(key: string, ...args: FormatArg[]): string {
  return formatSpecifiers(localizedFormat(key, ...args), args, currentLanguage());
}

/**
 * The translated format for a catalog key before its arguments are filled
 * in, in the plural form `args` pick, for callers that fill it themselves.
 */
export function localizedFormat(key: string, ...args: FormatArg[]): string {
  return lookup(key, args) ?? key;
}

/**
 * Fills Swift format specifiers: %@, %d, %lld, %ld, %u, %f (with optional
 * precision such as %.1f), positional forms like %1$@ and %2$lld, and %% for
 * a literal percent sign. With a `locale`, whole numbers are grouped for it;
 * without one they are written plainly.
 */
export function formatSpecifiers(format: string, args: readonly FormatArg[], locale?: string): string {
  const integers = locale === undefined ? undefined : new Intl.NumberFormat(numberLocale(locale));
  let next = 0;
  return format.replace(/%(?:(\d+)\$)?(\.\d+)?(@|lld|ld|llu|lu|d|i|u|f|%)/g, (match, position, precision, kind) => {
    if (kind === "%") return "%";
    const index = position ? Number(position) - 1 : next++;
    const value = args[index];
    if (value === undefined) return match;
    if (kind === "f") {
      const digits = precision ? Number(String(precision).slice(1)) : 6;
      return Number(value).toFixed(digits);
    }
    if (kind === "@") return String(value);
    const whole = Math.trunc(Number(value));
    return integers === undefined ? String(whole) : integers.format(whole);
  });
}
