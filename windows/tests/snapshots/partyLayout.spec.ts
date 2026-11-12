import { expect, test } from "@playwright/test";
import { LANGUAGES, snapshotStates } from "./snapshot";
import { cutRowProblems, textFitProblems } from "./textFit";

/*
 * Every Party state in every shipped snapshot language and panel size,
 * checked for text that does not fit: the room header (title, code, count
 * and Leave), each member's status under its pet, and the friend
 * code field's placeholder beside Paste, and the friends list showing
 * only whole rows. These caught "Leave" over the
 * Friends header, a title wrapping one character per line in Japanese,
 * German countdowns running into each other, a cut placeholder and a
 * friend row cut in half.
 */

test.use({ viewport: { width: 800, height: 600 } });

const ROWS = [".party-room-header", ".party-room-labels", ".party-member-status", ".party-code-field"];

for (const lang of LANGUAGES) {
  test(`party text fits ${lang}`, async ({ page }) => {
    const states = (await snapshotStates(page)).filter((state) => state.startsWith("open:party"));
    const problems: string[] = [];
    for (const size of ["compact", "regular", "large"]) {
      for (const state of states) {
        await page.goto(`/?still&backdrop&snapshot=${encodeURIComponent(state)}&lang=${lang}&size=${size}`);
        await page.waitForSelector("[data-snapshot-ready]", { timeout: 30_000 });
        await page.evaluate(() => document.fonts.ready);
        await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        for (const problem of await textFitProblems(page, ROWS)) problems.push(`${size} ${state}: ${problem}`);
        for (const problem of await cutRowProblems(page, ".party-friends-scroll")) problems.push(`${size} ${state}: ${problem}`);
      }
    }
    expect(problems).toEqual([]);
  });
}
