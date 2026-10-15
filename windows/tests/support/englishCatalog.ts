import { setLookup, type FormatArg } from "../../src/core/localization/tr";
import { loadRepoJson } from "./fixtures";

/*
 * The golden fixtures were recorded in English, plural forms included
 * ("+1 pt", "of 1 card"). Until the localization port installs the real
 * catalog lookup, a suite that checks such strings installs this one: the
 * English values of the Mac catalog, with plural variations picked by the
 * first numeric argument through Intl.PluralRules.
 */

interface StringUnit {
  value: string;
}

interface Localization {
  stringUnit?: StringUnit;
  variations?: { plural?: Record<string, { stringUnit?: StringUnit }> };
}

interface Catalog {
  strings: Record<string, { localizations?: Record<string, Localization> }>;
}

const plural = new Intl.PluralRules("en");

export function englishLookup(): (key: string, args: readonly FormatArg[]) => string | undefined {
  const catalog = loadRepoJson<Catalog>("Sources/TabbiKitCore/Localization/Localizable.xcstrings");
  return (key, args) => {
    const english = catalog.strings[key]?.localizations?.en;
    if (english === undefined) return undefined;
    if (english.stringUnit !== undefined) return english.stringUnit.value;
    const forms = english.variations?.plural;
    if (forms === undefined) return undefined;
    const count = args.find((arg): arg is number => typeof arg === "number") ?? 0;
    return (forms[plural.select(count)] ?? forms.other)?.stringUnit?.value;
  };
}

export function installEnglishCatalog(): void {
  setLookup(englishLookup());
}
