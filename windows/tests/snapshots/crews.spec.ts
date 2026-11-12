import { test } from "@playwright/test";
import { shoot, snapshotStates } from "./snapshot";

/*
 * The Party tab's Crews mode, every screen and state of the Crews UI spec
 * at every panel size, in English, German, Japanese and Arabic, to
 * tests/snapshots/output/<scale>/crews/<lang>/<size>-<state>.png, for review
 * beside the spec's prototype and the Mac's snapshots.
 */

test.use({ viewport: { width: 800, height: 600 } });

for (const lang of ["en", "de", "ja", "ar"]) {
  test(`crew screens ${lang}`, async ({ page }, info) => {
    const states = (await snapshotStates(page)).filter((state) => state.startsWith("open:party:crew-"));
    const out = `tests/snapshots/output/${info.project.name}/crews/${lang}`;
    for (const size of ["compact", "regular", "large"]) {
      for (const state of states) await shoot(page, state, `lang=${lang}&size=${size}`, `${out}/${size}-${state.slice("open:party:".length)}.png`);
    }
  });
}
