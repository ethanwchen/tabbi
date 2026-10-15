import rulesFile from "@backend/shared/name-filter.json";

/*
 * Port of PartyNameFilter: the friends server refuses display names and pet
 * names with slurs or explicit terms (`name_not_allowed`,
 * `pet_name_not_allowed`), since friends and party members see them. This
 * is the same check, run in the app so a rejected name gets an inline
 * message as it is typed. The Mac copies the rules into Swift; here they
 * are read in place from `backend/shared/name-filter.json`, the server's own
 * file, and `name-filter-cases.json` holds both to the same cases.
 */

export interface NameFilterRules {
  readonly substitutions: Readonly<Record<string, string>>;
  readonly ambiguous: Readonly<Record<string, string>>;
  readonly anywhere: readonly string[];
  readonly allow: readonly string[];
  readonly words: readonly string[];
}

export const NAME_FILTER_RULES: NameFilterRules = {
  substitutions: rulesFile.substitutions as Record<string, string>,
  ambiguous: rulesFile.ambiguous as Record<string, string>,
  anywhere: rulesFile.anywhere,
  allow: rulesFile.allow,
  words: rulesFile.words,
};

/** A string as runs of one letter: `fuuck` is f1 u2 c1 k1. Repeated letters then compare by count. */
interface Run {
  readonly ch: string;
  n: number;
}

function runs(text: string): Run[] {
  const out: Run[] = [];
  for (const ch of text) {
    const last = out[out.length - 1];
    if (last !== undefined && last.ch === ch) last.n += 1;
    else out.push({ ch, n: 1 });
  }
  return out;
}

const ANYWHERE = NAME_FILTER_RULES.anywhere.map(runs);
const WORDS = NAME_FILTER_RULES.words.map(runs);

/** True when `term` matches `text` at run `at`; each letter of the term may repeat in the text. */
function matchesAt(text: readonly Run[], term: readonly Run[], at: number): boolean {
  if (at + term.length > text.length) return false;
  return term.every((run, j) => {
    const found = text[at + j];
    return found !== undefined && found.ch === run.ch && found.n >= run.n;
  });
}

function contains(text: readonly Run[], term: readonly Run[]): boolean {
  return text.some((_, index) => matchesAt(text, term, index));
}

function equals(text: readonly Run[], term: readonly Run[]): boolean {
  return text.length === term.length && matchesAt(text, term, 0);
}

/** A whole word is the term, or the term plus a plural `s` or `es`. */
function isWord(word: string, term: readonly Run[]): boolean {
  if (equals(runs(word), term)) return true;
  if (word.endsWith("es") && equals(runs(word.slice(0, -2)), term)) return true;
  return word.endsWith("s") && equals(runs(word.slice(0, -1)), term);
}

function hasOwn(record: Readonly<Record<string, string>>, key: string): string | undefined {
  return Object.hasOwn(record, key) ? record[key] : undefined;
}

/** The words of `text` with every ambiguous character read as its `choice`-th letter. */
function words(text: string, choice: number): string[] {
  let mapped = "";
  for (const ch of text.toLowerCase()) {
    const letter = hasOwn(NAME_FILTER_RULES.substitutions, ch) ?? hasOwn(NAME_FILTER_RULES.ambiguous, ch)?.[choice] ?? ch;
    mapped += /^[a-z]$/.test(letter) ? letter : " ";
  }
  /* A run of single letters is one spelled-out word: "f u c k" or "f.u.c.k". */
  const out: string[] = [];
  let spelled = "";
  for (const word of mapped.split(" ").filter((part) => part !== "")) {
    if (word.length === 1) {
      spelled += word;
      continue;
    }
    if (spelled !== "") out.push(spelled);
    spelled = "";
    out.push(word);
  }
  if (spelled !== "") out.push(spelled);
  return out;
}

/**
 * The words joined into one, so a term split across words (`sh it`) still
 * matches. A last initial is left out, so `Ana L.` does not read as one word.
 */
function wholeName(list: readonly string[]): string {
  const last = list[list.length - 1];
  return (list.length > 1 && last !== undefined && last.length === 1 ? list.slice(0, -1) : list).join("");
}

/**
 * True when `name` contains none of the blocked terms, read through accents,
 * case, look-alike letters, leetspeak, separators and repeated letters.
 * Ordinary names that merely contain a short term (Cassandra, Scunthorpe,
 * Dick Van Dyke) pass, because short terms only match whole words.
 */
export function isNameAllowed(name: string): boolean {
  const plain = name.normalize("NFKD").replace(/\p{M}/gu, "");
  const camelSplit = plain.replace(/(\p{Ll})(\p{Lu})/gu, "$1 $2");
  for (let choice = 0; choice < 2; choice += 1) {
    const plainWords = words(plain, choice);
    let joined = plainWords.join("");
    for (const allowed of NAME_FILTER_RULES.allow) joined = joined.replaceAll(allowed, "");
    const joinedRuns = runs(joined);
    if (ANYWHERE.some((term) => contains(joinedRuns, term))) return false;
    const candidates = [...plainWords, ...words(camelSplit, choice), wholeName(plainWords)];
    if (candidates.some((word) => WORDS.some((term) => isWord(word, term)))) return false;
  }
  return true;
}
