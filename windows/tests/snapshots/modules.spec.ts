import { test } from "@playwright/test";
import { fileName, LANGUAGES, shoot, snapshotStates, THEMES } from "./snapshot";

/*
 * Every registered module's panel, in each of its named states, to
 * tests/snapshots/output/<scale>/modules/<theme>-<lang>/<state>.png: every
 * theme in English, and the default theme in German, Japanese and Arabic.
 * The harness lists the states (`?snapshot=index`), so a module adds a
 * state by naming it in `snapshotStates` and handling it in
 * `showSnapshotState`; nothing here changes.
 */

test.use({ viewport: { width: 800, height: 600 } });

const RUNS: { theme: string; lang: string }[] = [
  ...THEMES.map((theme) => ({ theme, lang: "en" })),
  ...LANGUAGES.filter((lang) => lang !== "en").map((lang) => ({ theme: "midnight", lang })),
];

for (const { theme, lang } of RUNS) {
  test(`module panels ${theme} ${lang}`, async ({ page }, info) => {
    const states = (await snapshotStates(page)).filter((state) => state.startsWith("open:"));
    const out = `tests/snapshots/output/${info.project.name}/modules/${theme}-${lang}`;
    for (const state of states) await shoot(page, state, `theme=${theme}&lang=${lang}`, `${out}/${fileName(state)}.png`);
  });
}
