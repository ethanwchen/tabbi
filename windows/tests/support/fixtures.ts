import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/*
 * Reads a golden fixture from shared/fixtures, written by the Swift tests on a
 * Mac. Fixtures are never edited from Windows: a failing replay means the
 * port is wrong until proven otherwise (shared/README.md).
 */
export function loadFixture<T = unknown>(path: string): T {
  const url = new URL(`../../../shared/fixtures/${path}`, import.meta.url);
  return JSON.parse(readFileSync(fileURLToPath(url), "utf8")) as T;
}

/* Reads a JSON file from the repo root, for data the Mac app ships (themes, kits, pet art). */
export function loadRepoJson<T = unknown>(path: string): T {
  const url = new URL(`../../../${path}`, import.meta.url);
  return JSON.parse(readFileSync(fileURLToPath(url), "utf8")) as T;
}
