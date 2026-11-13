import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/*
 * Every stylesheet closes each rule it opens. A missing "}" does not fail
 * the build: CSS nesting quietly folds every later rule into the open one,
 * which once left the closed island's pet wing and `.kit-user-text`
 * unstyled, and the Study Level label wrapping under the pet's name.
 */

const SRC = fileURLToPath(new URL("../../../src", import.meta.url));

function stylesheets(folder: string): string[] {
  return readdirSync(folder).flatMap((name) => {
    const path = join(folder, name);
    if (statSync(path).isDirectory()) return stylesheets(path);
    return name.endsWith(".css") ? [path] : [];
  });
}

/** The lines of rules left open at the end (a negative line for a stray "}"), ignoring braces in comments and strings. */
function unclosedRules(css: string): number[] {
  const open: number[] = [];
  let line = 1;
  for (let index = 0; index < css.length; index++) {
    const char = css[index];
    if (css.startsWith("/*", index)) {
      const end = css.indexOf("*/", index + 2);
      const stop = end < 0 ? css.length : end + 2;
      line += css.slice(index, stop).split("\n").length - 1;
      index = stop - 1;
      continue;
    }
    if (char === '"' || char === "'") {
      const end = css.indexOf(char, index + 1);
      index = end < 0 ? css.length : end;
      continue;
    }
    if (char === "\n") line++;
    if (char === "{") open.push(line);
    if (char === "}") {
      if (open.length === 0) return [-line];
      open.pop();
    }
  }
  return open;
}

describe("stylesheets", () => {
  it("finds an unclosed rule", () => {
    expect(unclosedRules(".a {\n  color: red;\n.b { color: blue; }")).toEqual([1]);
    expect(unclosedRules('.a { content: "}"; } /* { */')).toEqual([]);
  });

  it.each(stylesheets(SRC).map((path) => [path.slice(SRC.length + 1), path] as const))("%s closes every rule", (_, path) => {
    expect(unclosedRules(readFileSync(path, "utf8"))).toEqual([]);
  });
});
