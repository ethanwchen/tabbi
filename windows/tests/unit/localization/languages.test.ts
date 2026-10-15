import { describe, expect, it } from "vitest";
import { isRightToLeft, LANGUAGES, languageFor, textDirection } from "../../../src/core/localization/languages";

describe("languages (L10n)", () => {
  it("ship the Mac's twelve", () => {
    expect([...LANGUAGES]).toEqual(["en", "ar", "de", "es", "fr", "fil", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]);
  });

  it("read only Arabic right to left", () => {
    expect(LANGUAGES.filter(isRightToLeft)).toEqual(["ar"]);
    expect(isRightToLeft("ar-SA")).toBe(true);
    expect(isRightToLeft("he")).toBe(true);
    expect(isRightToLeft("en")).toBe(false);
    expect(isRightToLeft("not a tag!")).toBe(false);
    expect(textDirection("ar")).toBe("rtl");
    expect(textDirection("fr")).toBe("ltr");
  });

  it("pick the user's best translated language", () => {
    expect(languageFor(["de-DE", "en-US"])).toBe("de");
    expect(languageFor(["pt-BR"])).toBe("pt-BR");
    expect(languageFor(["zh-Hans-CN"])).toBe("zh-Hans");
    expect(languageFor(["zh-Hant-TW"])).toBe("zh-Hant");
    expect(languageFor(["ar-SA"])).toBe("ar");
    expect(languageFor(["ru-RU"])).toBe("ru");
    expect(languageFor(["fil-PH"])).toBe("fil");
    expect(languageFor(["ja-JP"])).toBe("ja");
    expect(languageFor(["it-IT", "fr-FR"])).toBe("fr");
    expect(languageFor(["it-IT"])).toBe("en");
    expect(languageFor([])).toBe("en");
  });

  it("understand the tags Windows and browsers report", () => {
    expect(languageFor(["zh-CN"])).toBe("zh-Hans");
    expect(languageFor(["zh-TW"])).toBe("zh-Hant");
    expect(languageFor(["zh-HK"])).toBe("zh-Hant");
    expect(languageFor(["pt-PT"])).toBe("pt-BR");
    expect(languageFor(["pt"])).toBe("pt-BR");
    expect(languageFor(["es-419"])).toBe("es");
    expect(languageFor(["EN-gb"])).toBe("en");
    expect(languageFor(["de"], ["en"])).toBe("en");
  });
});
