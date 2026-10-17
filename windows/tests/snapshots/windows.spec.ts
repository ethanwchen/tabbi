import { test } from "@playwright/test";
import { fileName, shoot, snapshotStates } from "./snapshot";

/*
 * The Settings window and first-run onboarding, every state, to
 * tests/snapshots/output/<scale>/windows/<theme>-<lang>/<state>.png: the
 * default theme plus Cozy, Liquid Glass and Strawberry Milk (a theme with its
 * own accent and on-accent color), in English, German, Japanese
 * and Arabic, so long words, tall glyphs and mirrored layouts are all seen.
 */

test.use({ viewport: { width: 800, height: 600 } });

const RUNS: { theme: string; lang: string }[] = [
  { theme: "midnight", lang: "en" },
  { theme: "cozy", lang: "en" },
  { theme: "liquidGlass", lang: "en" },
  { theme: "strawberryMilk", lang: "en" },
  { theme: "midnight", lang: "de" },
  { theme: "midnight", lang: "ja" },
  { theme: "midnight", lang: "ar" },
];

for (const { theme, lang } of RUNS) {
  test(`settings and onboarding ${theme} ${lang}`, async ({ page }, info) => {
    const states = (await snapshotStates(page)).filter((state) => state.startsWith("settings:") || state.startsWith("onboarding:"));
    const out = `tests/snapshots/output/${info.project.name}/windows/${theme}-${lang}`;
    for (const state of states) await shoot(page, state, `theme=${theme}&lang=${lang}`, `${out}/${fileName(state)}.png`);
  });
}
