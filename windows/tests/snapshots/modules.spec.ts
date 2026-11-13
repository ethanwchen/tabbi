import { test } from "@playwright/test";
import { fileName, LANGUAGES, shootAll, slice, snapshotStates, THEMES } from "./snapshot";

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

/* Each run's states split into PARTS tests, so shards stay balanced and no test walks too long. */
const PARTS = 3;

for (const { theme, lang } of RUNS) {
  for (let part = 0; part < PARTS; part++) {
    test(`module panels ${theme} ${lang} ${part + 1}/${PARTS}`, async ({ page, context }, info) => {
      const states = slice((await snapshotStates(page)).filter((state) => state.startsWith("open:")), part, PARTS);
      await page.close();
      const out = `tests/snapshots/output/${info.project.name}/modules/${theme}-${lang}`;
      await shootAll(context, states.map((state) => ({ state, query: `theme=${theme}&lang=${lang}`, path: `${out}/${fileName(state)}.png` })));
    });
  }
}
