import type { BrowserContext, Page } from "@playwright/test";

/*
 * Helpers for the snapshot specs: the harness (`?snapshot=<state>`, see
 * src/ui/shell/snapshot/) draws one state still on a neutral backdrop, and
 * the spec saves its frame as PNG. Nothing here compares pixels; open the
 * PNGs and review them against docs/design/guidelines.md.
 */

/* Every theme in picker order, as the Mac's themes.json lists them (a unit test checks the two agree). */
export const THEMES = [
  "midnight",
  "graphite",
  "liquidGlass",
  "neon",
  "monochrome",
  "cozy",
  "sakura",
  "forest",
  "blueberryMilk",
  "strawberryMilk",
  "taro",
  "matchaLatte",
  "bananaMilk",
  "deepSea",
  "cherrySoda",
  "stargazer",
  "mintChoco",
  "cottonCandy",
];
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

/**
 * Shoots each job on pages from `context`, starting a fresh page every
 * `perPage` shots and closing it after, so a long walk never piles up one
 * renderer's memory: on CI's runner a single page walking 140 states ran
 * out of resources (net::ERR_INSUFFICIENT_RESOURCES, a fonts.ready that
 * never resolved). At most one page per test is open at a time.
 */
export async function shootAll(
  context: BrowserContext,
  jobs: { state: string; query: string; path: string }[],
  perPage = 20,
): Promise<void> {
  let page: Page | undefined;
  try {
    for (const [index, job] of jobs.entries()) {
      if (index % perPage === 0) {
        await page?.close();
        page = await context.newPage();
      }
      await shoot(page as Page, job.state, job.query, job.path);
    }
  } finally {
    await page?.close();
  }
}

/** Every `parts`-th state from `part`, so a long list splits into tests of equal size. */
export function slice<T>(items: T[], part: number, parts: number): T[] {
  return items.filter((_, index) => index % parts === part);
}

/** A file name for a state: `open:study:running` becomes `open-study-running`. */
export function fileName(state: string): string {
  return state.replace(/:/g, "-");
}
