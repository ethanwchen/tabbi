/*
 * Tabbi's String Catalog (`Localizable.xcstrings`, and the Windows-only
 * `Windows.xcstrings` in the same format), read as plain JSON. The key is
 * the English text with Swift format specifiers; each entry has one
 * translation per language, either a `stringUnit` or plural `variations`.
 *
 * The app does not ship the catalog itself: `scripts/build-strings.mjs`
 * flattens it into one small table per language (`languageTable` here is
 * the same flattening, so tests can read the catalog directly).
 */

/** One piece of translated text, as Xcode writes it. */
export interface StringUnit {
  readonly state?: string;
  readonly value?: string;
}

export interface CatalogLocalization {
  readonly stringUnit?: StringUnit;
  readonly variations?: {
    readonly plural?: Readonly<Record<string, CatalogLocalization>>;
    readonly device?: Readonly<Record<string, CatalogLocalization>>;
  };
}

export interface CatalogEntry {
  readonly comment?: string;
  readonly extractionState?: string;
  readonly generatesSymbol?: boolean;
  readonly shouldTranslate?: boolean;
  readonly localizations?: Readonly<Record<string, CatalogLocalization>>;
}

/** An `.xcstrings` file. */
export interface StringCatalog {
  readonly sourceLanguage: string;
  readonly version?: string;
  readonly strings: Readonly<Record<string, CatalogEntry>>;
}

/** The CLDR plural categories `Intl.PluralRules` answers with. */
export type PluralCategory = "zero" | "one" | "two" | "few" | "many" | "other";

export const PLURAL_CATEGORIES: readonly PluralCategory[] = ["zero", "one", "two", "few", "many", "other"];

/** A plural translation: one format per category the language uses. */
export type PluralForms = Readonly<Partial<Record<PluralCategory, string>>>;

/**
 * One language's strings, as `build-strings.mjs` emits them: a key maps to
 * its format, or to its plural forms. A key whose translation is the key
 * itself (most English strings) is left out, since `tr` falls back to the key.
 */
export type LanguageTable = Readonly<Record<string, string | PluralForms>>;

function isPluralCategory(form: string): form is PluralCategory {
  return (PLURAL_CATEGORIES as readonly string[]).includes(form);
}

/** Flattens `catalog` into `language`'s table (see `LanguageTable`). */
export function languageTable(catalog: StringCatalog, language: string): LanguageTable {
  const table: Record<string, string | PluralForms> = {};
  for (const [key, entry] of Object.entries(catalog.strings)) {
    const localization = entry.localizations?.[language];
    const plural = localization?.variations?.plural;
    if (plural) {
      const forms: Partial<Record<PluralCategory, string>> = {};
      for (const [form, variant] of Object.entries(plural)) {
        const value = variant.stringUnit?.value;
        if (isPluralCategory(form) && value !== undefined) forms[form] = value;
      }
      table[key] = forms;
      continue;
    }
    const value = localization?.stringUnit?.value;
    if (value !== undefined && value !== key) table[key] = value;
  }
  return table;
}

/** Merges tables; a later table's key wins over an earlier one's. */
export function mergeTables(...tables: readonly LanguageTable[]): LanguageTable {
  return Object.assign({}, ...tables) as LanguageTable;
}
