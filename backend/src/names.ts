// Name filter: display names and pet names are public to friends and party members, so slurs and
// explicit terms are refused. The rules live in shared/name-filter.json, which the app mirrors in
// TabbiKitCore/Party/PartyNameFilter.swift for instant feedback; shared/name-filter-cases.json keeps both
// in agreement.
import rules from "../shared/name-filter.json";

/** A string as runs of one letter: `fuuck` is f1 u2 c1 k1. Repeated letters then compare by count. */
type Runs = { ch: string; n: number }[];

function runs(s: string): Runs {
  const out: Runs = [];
  for (const ch of s) {
    const last = out[out.length - 1];
    if (last && last.ch === ch) last.n++;
    else out.push({ ch, n: 1 });
  }
  return out;
}

const SUBSTITUTIONS = rules.substitutions as Record<string, string>;
const AMBIGUOUS = rules.ambiguous as Record<string, string>;
const ANYWHERE = rules.anywhere.map(runs);
const WORDS = rules.words.map(runs);
const ALLOW = rules.allow;

/** True when `term` matches `text` at run `at`; each letter of the term may repeat in the text. */
function matchesAt(text: Runs, term: Runs, at: number): boolean {
  if (at + term.length > text.length) return false;
  return term.every((t, j) => text[at + j].ch === t.ch && text[at + j].n >= t.n);
}

const contains = (text: Runs, term: Runs) => text.some((_, i) => matchesAt(text, term, i));
const equals = (text: Runs, term: Runs) => text.length === term.length && matchesAt(text, term, 0);

/** A whole word is the term, or the term plus a plural `s` or `es`. */
function isWord(word: string, term: Runs): boolean {
  if (equals(runs(word), term)) return true;
  if (word.endsWith("es") && equals(runs(word.slice(0, -2)), term)) return true;
  return word.endsWith("s") && equals(runs(word.slice(0, -1)), term);
}

/** The words of `text` with every ambiguous character read as its `choice`-th letter. */
function words(text: string, choice: number): string[] {
  let mapped = "";
  for (const ch of text.toLowerCase()) {
    const letter = SUBSTITUTIONS[ch] ?? AMBIGUOUS[ch]?.[choice] ?? ch;
    mapped += /^[a-z]$/.test(letter) ? letter : " ";
  }
  // A run of single letters is one spelled-out word: "f u c k" or "f.u.c.k".
  const out: string[] = [];
  let spelled = "";
  for (const w of mapped.split(" ").filter((w) => w !== "")) {
    if (w.length === 1) {
      spelled += w;
      continue;
    }
    if (spelled !== "") out.push(spelled);
    spelled = "";
    out.push(w);
  }
  if (spelled !== "") out.push(spelled);
  return out;
}

/**
 * True when `name` contains none of the blocked terms, read through accents, case, look-alike letters,
 * leetspeak, separators and repeated letters. Ordinary names that merely contain a short term (Cassandra,
 * Scunthorpe, Dick Van Dyke) pass, because short terms only match whole words.
 */
export function isNameAllowed(name: string): boolean {
  const plain = name.normalize("NFKD").replace(/\p{M}/gu, "");
  const camelSplit = plain.replace(/(\p{Ll})(\p{Lu})/gu, "$1 $2");
  for (let choice = 0; choice < 2; choice++) {
    const plainWords = words(plain, choice);
    let joined = plainWords.join("");
    for (const allowed of ALLOW) joined = joined.replaceAll(allowed, "");
    if (ANYWHERE.some((term) => contains(runs(joined), term))) return false;
    const candidates = [...plainWords, ...words(camelSplit, choice), plainWords.join("")];
    if (candidates.some((w) => WORDS.some((term) => isWord(w, term)))) return false;
  }
  return true;
}
