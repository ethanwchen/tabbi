import { afterEach, describe, expect, it } from "vitest";
import type { LanguageTable } from "../../../src/core/localization/catalog";
import { resetLanguage } from "../../../src/core/localization/lookup";
import { tr } from "../../../src/core/localization/tr";
import { loadLanguage } from "../../../src/i18n/strings";

afterEach(resetLanguage);

/* Stand-ins for the generated files, recording which ones were imported. */
function importers(tables: Record<string, LanguageTable>, imported: string[]) {
  return Object.fromEntries(
    Object.entries(tables).map(([language, table]) => [
      `./generated/${language}.json`,
      async () => {
        imported.push(language);
        return table;
      },
    ]),
  );
}

describe("loadLanguage", () => {
  it("imports only the user's language and installs it into tr", async () => {
    const imported: string[] = [];
    const tables = { en: {}, de: { "Quit Tabbi": "Tabbi beenden" }, ar: { "Quit Tabbi": "إنهاء Tabbi" } };
    const loaded = await loadLanguage(["de-AT", "en-US"], importers(tables, imported));
    expect(loaded).toEqual({ language: "de", direction: "ltr" });
    expect(imported).toEqual(["de"]);
    expect(tr("Quit Tabbi")).toBe("Tabbi beenden");
  });

  it("lays Arabic out right to left", async () => {
    const loaded = await loadLanguage(["ar-EG"], importers({ en: {}, ar: { "Quit Tabbi": "إنهاء Tabbi" } }, []));
    expect(loaded).toEqual({ language: "ar", direction: "rtl" });
    expect(tr("Quit Tabbi")).toBe("إنهاء Tabbi");
  });

  it("shows the English keys when no strings were built", async () => {
    const loaded = await loadLanguage(["fr-FR"], {});
    expect(loaded.language).toBe("en");
    expect(tr("Quit Tabbi")).toBe("Quit Tabbi");
  });
});
