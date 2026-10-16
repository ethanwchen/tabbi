import { describe, expect, it } from "vitest";
import { formatSpecifiers, setLookup, tr } from "../../../src/core/localization/tr";

describe("tr", () => {
  it("fills Swift format specifiers in order and by position", () => {
    expect(tr("%lld left", 3)).toBe("3 left");
    expect(formatSpecifiers("%@ and %@", ["a", "b"])).toBe("a and b");
    expect(formatSpecifiers("%2$@ before %1$@", ["a", "b"])).toBe("b before a");
    expect(formatSpecifiers("%.1f h, %d%%", [1.25, 80])).toBe("1.3 h, 80%");
    expect(formatSpecifiers("%lld", [4.9])).toBe("4");
  });

  it("leaves a specifier with no argument as it is", () => {
    expect(formatSpecifiers("%@ items", [])).toBe("%@ items");
  });
});

describe("tr's numbers", () => {
  const inLanguage = (language: string, run: () => void) => {
    setLookup(() => undefined, language);
    try {
      run();
    } finally {
      setLookup(() => undefined, "en");
    }
  };

  it("groups whole numbers for the current language, as Foundation does", () => {
    inLanguage("en", () => expect(tr("%lld cards", 1500)).toBe("1,500 cards"));
    inLanguage("de", () => expect(tr("%lld cards", 1500)).toBe("1.500 cards"));
    inLanguage("ar", () => expect(tr("%lld cards", 1500)).toBe("1,500 cards"));
  });

  it("leaves small numbers, text and formatSpecifiers without a locale alone", () => {
    inLanguage("de", () => expect(tr("%lld of %@", 7, "Mo")).toBe("7 of Mo"));
    expect(formatSpecifiers("%lld", [1500])).toBe("1500");
  });
});
