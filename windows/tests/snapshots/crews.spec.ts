import { test } from "@playwright/test";
import { shootAll, snapshotStates } from "./snapshot";

/*
 * The Party tab's Crews mode, every screen and state of the Crews UI spec
 * at every panel size, in English, German, Japanese and Arabic, to
 * tests/snapshots/output/<scale>/crews/<lang>/<size>-<state>.png, for review
 * beside the spec's prototype and the Mac's snapshots.
 */

test.use({ viewport: { width: 800, height: 600 } });

for (const lang of ["en", "de", "ja", "ar"]) {
  for (const size of ["compact", "regular", "large"]) {
    test(`crew screens ${lang} ${size}`, async ({ page, context }, info) => {
      const states = (await snapshotStates(page)).filter((state) => state.startsWith("open:party:crew-"));
      await page.close();
      const out = `tests/snapshots/output/${info.project.name}/crews/${lang}`;
      await shootAll(context, states.map((state) => ({
        state, query: `lang=${lang}&size=${size}`, path: `${out}/${size}-${state.slice("open:party:".length)}.png`,
      })));
    });
  }
}
