import { afterEach, describe, expect, it } from "vitest";
import { specifierArguments, specifiers } from "../../../src/core/localization/audit";
import { languageTable, type PluralForms } from "../../../src/core/localization/catalog";
import { LANGUAGES } from "../../../src/core/localization/languages";
import { resetLanguage } from "../../../src/core/localization/lookup";
import { formatSpecifiers, tr, type FormatArg } from "../../../src/core/localization/tr";
import { macCatalog, switchLanguage, windowsCatalog } from "../../support/catalogs";

afterEach(resetLanguage);

/* Every text of a table entry: a plain format, or each plural form. */
function texts(entry: string | PluralForms): string[] {
  return typeof entry === "string" ? [entry] : Object.values(entry).filter((v): v is string => v !== undefined);
}

/* Sample arguments for a key: a number for each integer, a word for each string. */
function sampleArgs(key: string): FormatArg[] {
  return specifiers(key).map((specifier, index) => (specifier === "@" ? `word${index}` : 7 + index));
}

const LEFTOVER = /%(?:\d+\$)?[-+ 0#']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGaAcCsSp]/;

describe("format specifiers in the catalogs", () => {
  it("are only forms tr fills: %@ and %lld, in order or by position", () => {
    const forms = new Set<string>();
    for (const catalog of [macCatalog, windowsCatalog]) {
      for (const language of LANGUAGES) {
        const table = languageTable(catalog, language);
        for (const text of [...Object.keys(catalog.strings), ...Object.values(table).flatMap(texts)]) {
          for (const argument of specifierArguments(text)) {
            forms.add(`${argument.position === undefined ? "" : "N$"}${argument.length}${argument.conversion}`);
          }
        }
      }
    }
    expect([...forms].sort()).toEqual(["@", "N$@", "N$lld", "lld"]);
  });

  it("all fill in every translation and plural form, so none shows a raw specifier", () => {
    const leftovers: string[] = [];
    for (const language of LANGUAGES) {
      switchLanguage(language);
      for (const catalog of [macCatalog, windowsCatalog]) {
        for (const key of Object.keys(catalog.strings)) {
          const args = sampleArgs(key);
          const plural = args.some((arg) => typeof arg === "number");
          for (const count of plural ? [0, 1, 2, 3, 11, 100] : [0]) {
            const filled = args.map((arg) => (typeof arg === "number" ? count : arg));
            const text = tr(key, ...filled);
            if (LEFTOVER.test(text)) leftovers.push(`${language}: ${key} -> ${text}`);
          }
        }
      }
    }
    expect(leftovers).toEqual([]);
  });

  it("reorder by position", () => {
    switchLanguage("de");
    expect(tr("Focus for %lld hours during %@.", 5, "Halloween")).toBe("Konzentrier dich 5 Stunden während Halloween.");
    expect(tr("%lld of %lld", 3, 8)).toBe("3 von 8");
    switchLanguage("ja");
    expect(tr("Focus for %lld minutes during %@.", 90, "ハロウィン")).toBe("ハロウィンの期間中に90分集中しよう。");
    expect(formatSpecifiers("%3$@ %1$lld %2$@ %4$lld %5$@", [1, "b", "c", 4, "e"])).toBe("c 1 b 4 e");
  });

  it("are read in argument order, like the Mac's audit", () => {
    expect(specifiers("%2$@ at %1$lld%%")).toEqual(["lld", "@"]);
    expect(specifiers("%.1f h, %@")).toEqual(["f", "@"]);
    expect(specifiers("100%% done")).toEqual([]);
    expect(specifiers("AI usage above 80%")).toEqual([]);
  });
});
