import { test } from "@playwright/test";
import { fileName, shoot, snapshotStates } from "./snapshot";

/*
 * The shell's own states to tests/snapshots/output/<scale>/shell/<name>.png:
 * the hidden island, the pill plain and with each kind of preview, every
 * onboarding setup step in the takeover slot, every Settings section, the
 * open panel at each panel size, and a few of them in Arabic (mirrored).
 * Module panels in every theme and language are modules.spec.ts.
 */

test.use({ viewport: { width: 800, height: 600 } });

test("shell states", async ({ page }, info) => {
  const states = (await snapshotStates(page)).filter((state) => !state.startsWith("open:"));
  const out = `tests/snapshots/output/${info.project.name}/shell`;
  for (const state of states) await shoot(page, state, "", `${out}/${fileName(state)}.png`);
  for (const size of ["compact", "regular", "large"]) {
    await shoot(page, "open:planner", `size=${size}`, `${out}/open-planner-${size}.png`);
  }
  for (const state of ["open:study", "pill:meeting-join", "pill:pet", "onboarding:pet", "settings:general"]) {
    await shoot(page, state, "lang=ar", `${out}/${fileName(state)}-ar.png`);
  }
  await shoot(page, "open:study", "kit=medicine", `${out}/open-study-medicine.png`);
  /* Every module on: the tabs tighten, then overflow behind "more". */
  await shoot(page, "open:system", "all", `${out}/open-all-tabs.png`);
  await shoot(page, "open:schedule", "all&more", `${out}/open-all-tabs-more.png`);
  await shoot(page, "open:schedule", "all&more&lang=ar", `${out}/open-all-tabs-more-ar.png`);
});
