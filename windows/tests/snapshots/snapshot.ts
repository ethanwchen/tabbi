import type { Page } from "@playwright/test";

/*
 * Helpers for the snapshot specs: the harness (`?snapshot=<state>`, see
 * src/ui/shell/snapshot/) draws one state still on a neutral backdrop, and
 * the spec saves its frame as PNG. Nothing here compares pixels; open the
 * PNGs and review them against docs/design/guidelines.md.
 */

export const THEMES = ["midnight", "graphite", "liquidGlass", "neon", "monochrome", "cozy", "sakura", "forest"];
export const LANGUAGES = ["en", "de", "ja", "ar"];

/** Every state the harness can draw, as it lists them. */
export async function snapshotStates(page: Page): Promise<string[]> {
  await page.goto("/?snapshot=index");
  const text = await page.locator("#snapshot-index").textContent();
  return JSON.parse(text ?? "[]") as string[];
}

/** Draws `state` with the extra query and saves its frame to `path`. */
export async function shoot(page: Page, state: string, query: string, path: string): Promise<void> {
  await page.goto(`/?still&backdrop&snapshot=${encodeURIComponent(state)}${query ? `&${query}` : ""}`);
  /* A state that never settles fails here, named, instead of using up the whole test. */
  await page.waitForSelector("[data-snapshot-ready]", { timeout: 30_000 });
  await page.evaluate(() => document.fonts.ready);
  /* One more frame, so text measured after the fonts loaded is drawn. */
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.locator(".snapshot-frame").screenshot({ path });
}

/** A file name for a state: `open:study:running` becomes `open-study-running`. */
export function fileName(state: string): string {
  return state.replace(/:/g, "-");
}
