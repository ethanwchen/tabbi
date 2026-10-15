/* Types for build-strings.mjs, so the tests can run it. */

import type { LanguageTable, StringCatalog } from "../src/core/localization/catalog";

export declare const CATALOGS: readonly string[];
export declare const OUTPUT: string;
export declare const LANGUAGES: readonly string[];

export declare function languageTable(catalog: StringCatalog, language: string): LanguageTable;

export declare function buildStrings(options?: {
  readonly catalogs?: readonly string[];
  readonly output?: string;
  readonly languages?: readonly string[];
}): string[];
