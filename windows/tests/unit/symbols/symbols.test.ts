import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { FALLBACK_ICON, iconId, SYMBOL_ICONS } from "../../../src/core/symbols/symbols";
import { loadRepoJson } from "../../support/fixtures";

/*
 * Finds every SF Symbol name the Mac uses where the Windows build will meet
 * it, so a new name on the Mac fails here until the table maps it.
 *
 * Extraction rules:
 * - JSON (bundled kits and the Party catalog): every string value of a key
 *   named `symbol` or `icon`, at any depth.
 * - Swift (Sources/TabbiKitCore and Sources/Tabbi/Modules), comment lines
 *   skipped:
 *   1. a labeled argument or assignment whose name is `symbol`,
 *      `symbolName`, `systemName`, `systemImage` or ends in `Symbol`
 *      (`symbol: "timer"`, `symbol = "calendar"`, `statusSymbol: ...`): the
 *      string literals in the expression after it, up to the next top-level
 *      comma or closing bracket, so a ternary (`copied ? "checkmark" :
 *      "doc.on.doc"`) gives both names;
 *   2. the body of a computed property or function whose name contains
 *      `symbol` and that returns a String (`var symbol: String { switch ... }`,
 *      `func symbol(for:) -> String`): every string literal in it.
 * - A literal counts only when it looks like a symbol name: lowercase
 *   letters and digits in dot-separated parts (`pawprint.fill`). Titles,
 *   interpolations and ids with other characters never match.
 */

const NAME = /^[a-z0-9]+(?:\.[a-z0-9]+)*$/;
const repo = (path: string) => fileURLToPath(new URL(`../../../../${path}`, import.meta.url));

function swiftFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = `${dir}/${entry}`;
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith(".swift") ? [path] : [];
  });
}

function literals(text: string): string[] {
  return [...text.matchAll(/"((?:[^"\\]|\\.)*)"/g)].flatMap((m) => (m[1] !== undefined && NAME.test(m[1]) ? [m[1]] : []));
}

/* The expression after a label: up to a top-level comma or a closing bracket that opened before it. */
function expressionAfter(line: string, start: number): string {
  let depth = 0;
  let i = start;
  for (; i < line.length; i++) {
    const ch = line[i];
    if (ch === "(" || ch === "[" || ch === "{") depth++;
    else if (ch === ")" || ch === "]" || ch === "}") {
      if (depth === 0) break;
      depth--;
    } else if (ch === "," && depth === 0) break;
    else if (ch === '"') {
      i++;
      while (i < line.length && line[i] !== '"') i += line[i] === "\\" ? 2 : 1;
    }
  }
  return line.slice(start, i);
}

const LABEL = /\b(?:symbol|symbolName|systemName|systemImage|[a-z]\w*Symbol)\s*(?::|=(?!=))\s*/g;
const BODY =
  /\b(?:var|func)\s+(?:symbol\w*|\w*Symbol\w*)\b[^{]*->\s*String\??\s*\{|\bvar\s+(?:symbol\w*|\w*Symbol\w*)\s*:\s*String\??\s*\{/;

function swiftSymbols(root: string): Map<string, string> {
  const found = new Map<string, string>();
  const add = (name: string, where: string) => {
    if (!found.has(name)) found.set(name, where);
  };
  for (const file of swiftFiles(repo(root))) {
    const lines = readFileSync(file, "utf8").split("\n");
    lines.forEach((line, index) => {
      if (/^\s*(?:\/\/|\*)/.test(line)) return;
      const where = `${file}:${index + 1}`;
      for (const match of line.matchAll(LABEL)) {
        for (const name of literals(expressionAfter(line, match.index + match[0].length))) add(name, where);
      }
      if (!BODY.test(line)) return;
      let depth = 0;
      for (let j = index; j < lines.length; j++) {
        const body = lines[j] ?? "";
        if (j > index) for (const name of literals(body)) add(name, `${file}:${j + 1}`);
        depth += (body.match(/\{/g) ?? []).length - (body.match(/\}/g) ?? []).length;
        if (depth <= 0 && j > index) break;
      }
    });
  }
  return found;
}

function jsonSymbols(value: unknown, found: Set<string>): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) jsonSymbols(item, found);
  } else if (value !== null && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      if ((key === "symbol" || key === "icon") && typeof item === "string") found.add(item);
      else jsonSymbols(item, found);
    }
  }
  return found;
}

const unmapped = (names: Iterable<string>) => [...names].filter((name) => !Object.hasOwn(SYMBOL_ICONS, name)).sort();

describe("SF Symbol table", () => {
  it("maps every symbol a bundled kit names", () => {
    const kits = readdirSync(repo("Sources/TabbiKitCore/Kits/Bundled")).filter((file) => file.endsWith(".json"));
    expect(kits.length).toBeGreaterThan(0);
    const names = new Set<string>();
    for (const kit of kits) jsonSymbols(loadRepoJson(`Sources/TabbiKitCore/Kits/Bundled/${kit}`), names);
    expect(names.has("square.grid.2x2.fill")).toBe(true);
    expect(unmapped(names)).toEqual([]);
  });

  it("maps every symbol the Party catalog names", () => {
    expect(unmapped(jsonSymbols(loadRepoJson("backend/shared/catalog.json"), new Set()))).toEqual([]);
  });

  it("maps every symbol in the module descriptors and panels", () => {
    const found = swiftSymbols("Sources/Tabbi/Modules");
    /* Spot checks that the scan reads descriptors, ternaries and switch bodies. */
    for (const name of ["timer", "checklist", "pawprint.fill", "cpu", "doc.on.doc", "speaker.wave.3.fill"]) {
      expect(found.has(name), name).toBe(true);
    }
    expect(unmapped(found.keys()).map((name) => `${name} (${found.get(name) ?? ""})`)).toEqual([]);
  });

  it("maps every symbol the core names", () => {
    const found = swiftSymbols("Sources/TabbiKitCore");
    for (const name of ["square.dashed", "square.grid.2x2", "calendar.badge.plus", "water.waves", "slider.horizontal.3"]) {
      expect(found.has(name), name).toBe(true);
    }
    expect(unmapped(found.keys()).map((name) => `${name} (${found.get(name) ?? ""})`)).toEqual([]);
  });

  it("gives every name a kebab case id", () => {
    for (const [name, id] of Object.entries(SYMBOL_ICONS)) {
      expect(NAME.test(name), name).toBe(true);
      expect(id, name).toMatch(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
    }
  });

  it("looks up known names and falls back for unknown ones", () => {
    expect(iconId("timer")).toBe("timer");
    expect(iconId("pawprint.fill")).toBe("paw-filled");
    expect(iconId("heart")).not.toBe(iconId("heart.fill"));
    expect(iconId("not.a.symbol")).toBe(FALLBACK_ICON);
    expect(iconId("")).toBe(FALLBACK_ICON);
    expect(iconId("toString")).toBe(FALLBACK_ICON);
    expect(iconId("square.dashed")).toBe(FALLBACK_ICON);
  });
});
