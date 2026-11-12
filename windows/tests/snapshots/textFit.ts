import type { Page } from "@playwright/test";

/*
 * A render-based check that text fits where it is drawn (the owner's
 * no-truncation rule), run in a real browser on a still state: rows that
 * must hold their items show no overflow and keep them on one line, a
 * title stays on one line, and
 * an input's placeholder is not cut. MarqueeText scrolls on purpose and is
 * skipped. Returns one line per problem, empty when everything fits.
 */
export async function textFitProblems(page: Page, rowSelectors: readonly string[]): Promise<string[]> {
  return page.evaluate((selectors) => {
    const problems: string[] = [];
    const describe = (element: Element) =>
      `${element.className || element.tagName} "${(element.textContent ?? "").trim().slice(0, 40)}"`;
    const visible = (element: Element) => {
      const box = element.getBoundingClientRect();
      return box.width > 0 && box.height > 0;
    };
    for (const selector of selectors) {
      for (const element of document.querySelectorAll<HTMLElement>(selector)) {
        if (!visible(element) || element.closest(".kit-marquee")) continue;
        if (element.scrollWidth > element.clientWidth + 1) {
          problems.push(`${selector} overflows by ${element.scrollWidth - element.clientWidth}px: ${describe(element)}`);
        }
      }
    }
    // A one-line row keeps every item on that line: their boxes all share a band.
    for (const selector of selectors) {
      for (const element of document.querySelectorAll<HTMLElement>(selector)) {
        if (!visible(element)) continue;
        const boxes = [...element.querySelectorAll<HTMLElement>("*")]
          .filter((child) => child.children.length === 0 && visible(child))
          .map((child) => child.getBoundingClientRect());
        if (boxes.length < 2) continue;
        const top = Math.max(...boxes.map((box) => box.top));
        const bottom = Math.min(...boxes.map((box) => box.bottom));
        if (top >= bottom) problems.push(`${selector} breaks onto a second line: ${describe(element)}`);
      }
    }
    for (const title of document.querySelectorAll<HTMLElement>(".kit-title")) {
      if (!visible(title)) continue;
      const size = parseFloat(getComputedStyle(title).fontSize);
      if (title.getBoundingClientRect().height > size * 2) problems.push(`title wraps: ${describe(title)}`);
    }
    const canvas = document.createElement("canvas").getContext("2d");
    for (const input of document.querySelectorAll<HTMLInputElement>("input[placeholder]")) {
      if (!visible(input) || input.value !== "" || !canvas) continue;
      const style = getComputedStyle(input, "::placeholder");
      canvas.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
      const width = canvas.measureText(input.placeholder).width;
      if (width > input.clientWidth + 1) {
        problems.push(`placeholder cut by ${Math.round(width - input.clientWidth)}px: "${input.placeholder}"`);
      }
    }
    return problems;
  }, rowSelectors);
}
