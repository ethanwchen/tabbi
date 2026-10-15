import type { LanguageTable, StringCatalog } from "../../../src/core/localization/catalog";
import { languageTable, mergeTables } from "../../../src/core/localization/catalog";
import { installLanguage } from "../../../src/core/localization/lookup";
import { loadRepoJson } from "../../support/fixtures";

/* The two String Catalogs the Windows build reads, straight from the repo. */
export const macCatalog = loadRepoJson<StringCatalog>("Sources/TabbiKitCore/Localization/Localizable.xcstrings");
export const windowsCatalog = loadRepoJson<StringCatalog>("windows/src/i18n/Windows.xcstrings");

/* `language`'s merged table, as the build step writes it. */
export function tableFor(language: string): LanguageTable {
  return mergeTables(languageTable(macCatalog, language), languageTable(windowsCatalog, language));
}

/* Makes `tr` read `language` from the catalogs. */
export function switchLanguage(language: string): void {
  installLanguage(tableFor(language), language);
}
