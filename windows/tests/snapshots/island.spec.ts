import { test } from "@playwright/test";

/*
 * Renders every phase 1 island state to tests/snapshots/output/<scale>/<name>.png,
 * on a neutral desktop backdrop so the shape's edges show. Open each PNG and
 * review it against docs/design/guidelines.md; nothing here compares pixels.
 */
const STATES: Record<string, string> = {
  hidden: "",
  pill: "phase=pill",
  "pill-hover": "phase=pill&hover",
  "open-study": "phase=open&tab=study",
  "open-planner": "phase=open&tab=planner",
  "open-spotify": "phase=open&tab=spotify",
  "open-claudeAsk": "phase=open&tab=claudeAsk",
  "open-closet": "phase=open&tab=closet",
};

for (const [name, query] of Object.entries(STATES)) {
  test(name, async ({ page }, info) => {
    await page.goto(`/?still&backdrop&${query}`);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: `tests/snapshots/output/${info.project.name}/${name}.png` });
  });
}
