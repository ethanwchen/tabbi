/*
 * Looks a key up in one language's table and picks its plural form, the
 * way the Mac's compiled `.stringsdict` does: the plural follows the key's
 * first integer argument (`%lld`), wherever it sits ("Review %@ in Anki:
 * %lld due" counts its second argument), and the form is the language's
 * CLDR category for that number (`Intl.PluralRules`), so Arabic picks among
 * all six forms and Russian by the last digits.
 */

import { setLookup, type FormatArg } from "./tr";
import { PLURAL_CATEGORIES, type LanguageTable, type PluralForms } from "./catalog";
import { specifierArguments } from "./audit";

const INTEGER_CONVERSIONS = new Set(["d", "D", "i", "u", "U", "x", "X", "o", "O"]);

/**
 * The index (0-based) of the argument that selects a plural for `key`: its
 * first integer specifier in argument order, or undefined when it has none.
 */
export function pluralArgumentIndex(key: string): number | undefined {
  let next = 0;
  let selected: number | undefined;
  for (const argument of specifierArguments(key)) {
    const index = argument.position === undefined ? next++ : argument.position - 1;
    if (INTEGER_CONVERSIONS.has(argument.conversion) && (selected === undefined || index < selected)) selected = index;
  }
  return selected;
}

const pluralRules = new Map<string, Intl.PluralRules>();

function rulesFor(language: string): Intl.PluralRules {
  let rules = pluralRules.get(language);
  if (!rules) {
    rules = new Intl.PluralRules(language);
    pluralRules.set(language, rules);
  }
  return rules;
}

/** The form of `forms` that `count` takes in `language`, falling back to `other`. */
export function selectPlural(forms: PluralForms, count: number, language: string): string | undefined {
  const category = Number.isFinite(count) ? rulesFor(language).select(count) : "other";
  if (category in forms) return forms[category as keyof PluralForms];
  return forms.other ?? PLURAL_CATEGORIES.map((form) => forms[form]).find((value) => value !== undefined);
}

/** The format for `key` with `args` in `table` (`language`'s strings), or undefined to show the key. */
export function lookUp(table: LanguageTable, language: string, key: string, args: readonly FormatArg[]): string | undefined {
  if (!Object.hasOwn(table, key)) return undefined;
  const entry = table[key];
  if (entry === undefined || typeof entry === "string") return entry;
  const index = pluralArgumentIndex(key);
  const count = index === undefined ? Number.NaN : Number(args[index]);
  return selectPlural(entry, count, language);
}

/** Makes `tr` read `table`, the strings of `language`; every call site keeps working unchanged. */
export function installLanguage(table: LanguageTable, language: string): void {
  setLookup((key, args) => lookUp(table, language, key, args));
}

/** Puts `tr` back on the English keys. */
export function resetLanguage(): void {
  setLookup(() => undefined);
}
