import { describe, expect, it } from "vitest";
import { catalogIssues, describeIssue } from "../../../src/core/localization/audit";
import type { StringCatalog } from "../../../src/core/localization/catalog";

const unit = (value: string, state = "translated") => ({ stringUnit: { state, value } });

describe("catalogIssues (StringCatalogAudit)", () => {
  it("reports missing and unfinished translations", () => {
    const catalog: StringCatalog = {
      sourceLanguage: "en",
      strings: {
        Done: { localizations: { de: unit("Fertig"), fr: unit("Fini", "needs_review") } },
        Tabbi: { shouldTranslate: false },
      },
    };
    expect(catalogIssues(catalog, ["en", "de", "fr", "ja"]).map(describeIssue)).toEqual([
      `"Done": fr translation is needs_review`,
      `"Done": no ja translation`,
    ]);
  });

  it("reports specifier mismatches in every plural form", () => {
    const catalog: StringCatalog = {
      sourceLanguage: "en",
      strings: {
        "%lld cards": {
          localizations: {
            en: { variations: { plural: { one: unit("%lld card"), other: unit("%lld cards") } } },
            de: { variations: { plural: { one: unit("eine Karte"), other: unit("%lld Karten") } } },
          },
        },
        "%@ of %@": { localizations: { de: unit("%2$@ von %1$@"), fr: unit("%@ sur %d") } },
      },
    };
    const mismatch = { type: "specifierMismatch", expected: ["@", "@"], found: ["@", "d"] } as const;
    expect(catalogIssues(catalog, ["en", "de", "fr"])).toEqual([
      { key: "%@ of %@", language: "fr", kind: mismatch },
      { key: "%lld cards", language: "de", form: "one", kind: { type: "specifierMismatch", expected: ["lld"], found: [] } },
      { key: "%lld cards", language: "fr", kind: { type: "missing" } },
    ]);
    expect(describeIssue({ key: "%@ of %@", language: "fr", kind: mismatch })).toBe(
      `"%@ of %@": fr uses ["@", "d"] where English uses ["@", "@"]`,
    );
  });
});
