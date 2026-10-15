import { afterEach, describe, expect, it } from "vitest";
import { pluralArgumentIndex, resetLanguage, selectPlural } from "../../../src/core/localization/lookup";
import { tr } from "../../../src/core/localization/tr";
import { switchLanguage } from "./catalogs";

afterEach(resetLanguage);

const counts = (key: string, values: readonly number[], ...rest: string[]) => values.map((n) => tr(key, n, ...rest));

describe("plural variations", () => {
  it("pick one or other in English", () => {
    switchLanguage("en");
    expect(counts("%lld streak days", [1, 2, 5, 21])).toEqual(["1 day", "2 days", "5 days", "21 days"]);
    expect(counts("with %lld friends", [0, 1, 2])).toEqual(["with 0 friends", "with 1 friend", "with 2 friends"]);
    expect(counts("%lld cards", [1, 128])).toEqual(["1 card", "128 cards"]);
  });

  it("fill all six Arabic forms: 0, 1, 2, 3 to 10, 11 to 99, 100", () => {
    switchLanguage("ar");
    const values = [0, 1, 2, 3, 11, 100];
    expect(counts("%lld streak days", values)).toEqual(["0 يوم", "1 يوم", "2 يومان", "3 أيام", "11 يومًا", "100 يوم"]);
    expect(counts("%lld sessions", values)).toEqual(["0 جلسة", "1 جلسة", "2 جلستان", "3 جلسات", "11 جلسةً", "100 جلسة"]);
    expect(counts("%lld cores", values)).toEqual(["0 نواة", "1 نواة", "2 نواتان", "3 أنوية", "11 نواةً", "100 نواة"]);
  });

  it("follow the last digits in Russian", () => {
    switchLanguage("ru");
    expect(counts("%lld days", [1, 2, 5, 11, 21, 22, 25])).toEqual([
      "1 день",
      "2 дня",
      "5 дней",
      "11 дней",
      "21 день",
      "22 дня",
      "25 дней",
    ]);
    expect(counts("%lld cores", [1, 2, 5, 21])).toEqual(["1 ядро", "2 ядра", "5 ядер", "21 ядро"]);
    expect(counts("%lld friends are here with you.", [1, 2, 5, 21])).toEqual([
      "С тобой 1 друг.",
      "С тобой 2 друга.",
      "С тобой 5 друзей.",
      "С тобой 21 друг.",
    ]);
  });

  it("have one form in Japanese", () => {
    switchLanguage("ja");
    expect(counts("%lld streak days", [0, 1, 2, 11])).toEqual(["0日", "1日", "2日", "11日"]);
    expect(counts("%lld cards", [1, 128])).toEqual(["1枚", "128枚"]);
  });

  it("count the integer argument, wherever it sits", () => {
    expect(pluralArgumentIndex("%lld pts, %@ to go")).toBe(0);
    expect(pluralArgumentIndex("Review %@ in Anki: %lld due. Pin another deck with its star.")).toBe(1);
    expect(pluralArgumentIndex("%2$lld of %1$@")).toBe(1);
    expect(pluralArgumentIndex("%@ and %@")).toBeUndefined();

    switchLanguage("ru");
    expect(counts("%lld more sessions to %@", [1, 2, 5], "Шапка")).toEqual([
      "Еще 1 сессия до «Шапка»",
      "Еще 2 сессии до «Шапка»",
      "Еще 5 сессий до «Шапка»",
    ]);
    switchLanguage("ar");
    const key = "Review %@ in Anki: %lld due. Pin another deck with its star.";
    expect(tr(key, "Cardio", 2)).toBe("راجع Cardio في Anki: 2 بطاقتان مستحقتان. ثبّت رزمة أخرى بنجمتها.");
    expect(tr(key, "Cardio", 11)).toBe("راجع Cardio في Anki: 11 بطاقةً مستحقة. ثبّت رزمة أخرى بنجمتها.");
  });

  it("fall back to other for a form a translation leaves out", () => {
    expect(selectPlural({ other: "%lld x" }, 1, "en")).toBe("%lld x");
    expect(selectPlural({ one: "%lld x", other: "%lld xs" }, Number.NaN, "en")).toBe("%lld xs");
  });
});
