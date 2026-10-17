import { test } from "@playwright/test";
import { LANGUAGES, THEMES } from "./snapshot";

/*
 * Renders the kit gallery (gallery.html) to tests/snapshots/output/<scale>/gallery-*.png:
 * the default theme in English, German, Japanese and Arabic, and every theme
 * in English. Each page is a still render (no motion, loaders at their first
 * frame). Open the PNGs and review them against docs/design/guidelines.md;
 * nothing here compares pixels.
 */

const PAGES: Record<string, string> = {};
for (const lang of LANGUAGES) PAGES[`gallery-midnight-${lang}`] = `theme=midnight&lang=${lang}`;
for (const theme of THEMES.slice(1)) PAGES[`gallery-${theme}-en`] = `theme=${theme}&lang=en`;

for (const [name, query] of Object.entries(PAGES)) {
  test(name, async ({ page }, info) => {
    await page.setViewportSize({ width: 1240, height: 900 });
    await page.goto(`/gallery.html?still&${query}`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForSelector(".gallery-section");
    await page.screenshot({ path: `tests/snapshots/output/${info.project.name}/${name}.png`, fullPage: true });
  });
}
