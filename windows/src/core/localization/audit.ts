/*
 * Port of StringCatalogAudit: what a String Catalog still lacks before it
 * can ship. A language with no translation, a translation not marked done,
 * or one whose format specifiers differ from the English, which would show
 * the wrong value when the string is formatted.
 */

import type { CatalogLocalization, StringCatalog, StringUnit } from "./catalog";

export type IssueKind =
  | { readonly type: "missing" }
  | { readonly type: "notTranslated"; readonly state: string }
  | { readonly type: "specifierMismatch"; readonly expected: readonly string[]; readonly found: readonly string[] };

/** One problem with one string. `form` names the plural form (`one`, `other`) it is in, if any. */
export interface CatalogIssue {
  readonly key: string;
  readonly language: string;
  readonly form?: string;
  readonly kind: IssueKind;
}

const quoted = (list: readonly string[]) => `[${list.map((item) => `"${item}"`).join(", ")}]`;

/** The issue as the Mac's audit words it. */
export function describeIssue(issue: CatalogIssue): string {
  const place = issue.form === undefined ? issue.language : `${issue.language} (${issue.form})`;
  switch (issue.kind.type) {
    case "missing":
      return `"${issue.key}": no ${place} translation`;
    case "notTranslated":
      return `"${issue.key}": ${place} translation is ${issue.kind.state}`;
    case "specifierMismatch":
      return `"${issue.key}": ${place} uses ${quoted(issue.kind.found)} where English uses ${quoted(issue.kind.expected)}`;
  }
}

/** A format specifier that takes an argument: its 1-based position if written (`%2$@`), length modifier and conversion. */
export interface SpecifierArgument {
  readonly position?: number;
  readonly length: string;
  readonly conversion: string;
}

const SPECIFIER =
  /%(?:(\d+)\$)?[-+ 0#']*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGaAcCsSp%])/g;

/** Every argument-taking specifier in `text`, in the order written; `%%` is a literal percent sign. */
export function specifierArguments(text: string): SpecifierArgument[] {
  const found: SpecifierArgument[] = [];
  for (const match of text.matchAll(SPECIFIER)) {
    const conversion = match[3] ?? "";
    if (conversion === "%") continue;
    const position = match[1] === undefined ? undefined : Number(match[1]);
    found.push({ position, length: match[2] ?? "", conversion });
  }
  return found;
}

/**
 * The format specifiers in `text`, one per argument in argument order
 * (positional ones such as `%2$@` sorted into place), each as its length
 * modifier and conversion (`@`, `lld`, `.1f` becomes `f`).
 */
export function specifiers(text: string): string[] {
  const positional = new Map<number, string>();
  const sequential: string[] = [];
  for (const argument of specifierArguments(text)) {
    const specifier = argument.length + argument.conversion;
    if (argument.position === undefined) sequential.push(specifier);
    else positional.set(argument.position, specifier);
  }
  if (positional.size === 0) return sequential;
  const ordered = [...positional.entries()].sort((a, b) => a[0] - b[0]).map(([, specifier]) => specifier);
  return [...ordered, ...sequential];
}

/* Every piece of text in a localization: the plain string (no form) or each plural or device form. */
function units(localization: CatalogLocalization): { form?: string; unit: StringUnit }[] {
  const found: { form?: string; unit: StringUnit }[] = localization.stringUnit ? [{ unit: localization.stringUnit }] : [];
  const forms = { ...(localization.variations?.device ?? {}), ...(localization.variations?.plural ?? {}) };
  for (const form of Object.keys(forms).sort()) {
    const variant = forms[form];
    if (!variant) continue;
    for (const inner of units(variant)) {
      found.push({ form: inner.form === undefined ? form : `${form} ${inner.form}`, unit: inner.unit });
    }
  }
  return found;
}

const sameList = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((value, i) => value === b[i]);

/**
 * Everything that keeps `catalog` from shipping in `languages`, sorted by
 * key. Strings marked "Don't translate" are skipped; the source language is
 * checked only where it has text of its own (plural forms), since the key
 * is its text.
 */
export function catalogIssues(catalog: StringCatalog, languages: readonly string[]): CatalogIssue[] {
  const issues: CatalogIssue[] = [];
  for (const key of Object.keys(catalog.strings).sort()) {
    const entry = catalog.strings[key];
    if (!entry || entry.shouldTranslate === false) continue;
    const expected = specifiers(key);
    for (const language of languages) {
      const localization = entry.localizations?.[language];
      if (!localization) {
        if (language !== catalog.sourceLanguage) issues.push({ key, language, kind: { type: "missing" } });
        continue;
      }
      for (const { form, unit } of units(localization)) {
        if (unit.state !== "translated") {
          issues.push({ key, language, form, kind: { type: "notTranslated", state: unit.state ?? "empty" } });
        }
        const found = specifiers(unit.value ?? "");
        if (!sameList(found, expected)) {
          issues.push({ key, language, form, kind: { type: "specifierMismatch", expected, found } });
        }
      }
    }
  }
  return issues;
}
