import { DEFAULT_EDITION_ID, FALLBACK_TABBI_EDITION, loadEditionFile, type Edition } from "./edition";

/*
 * The editions that ship, read at build time from the Mac's
 * Editions/BundledEditions folder (never a copy), so a new edition is a file.
 */
const sources = import.meta.glob<string>("@mac/Editions/BundledEditions/*.json", {
  eager: true,
  query: "?raw",
  import: "default",
});

/** Every bundled edition file, in file-name order. */
export const BUNDLED_EDITION_FILES: readonly { readonly name: string; readonly text: string }[] = Object.entries(
  sources,
)
  .map(([path, text]) => ({ name: (path.split("/").pop() ?? path).replace(/\.json$/, ""), text }))
  .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));

const rank = (edition: Edition) => (edition.id === DEFAULT_EDITION_ID ? 0 : 1);

/**
 * Every built-in edition: the default edition first, then the others by id.
 * A file that fails to load is a packaging bug, which the tests catch; it is
 * skipped rather than failing the app.
 */
export const BUILT_IN_EDITIONS: readonly Edition[] = BUNDLED_EDITION_FILES.map((file) =>
  loadEditionFile(file.name, file.text),
)
  .flatMap((result) => (result.ok ? [result.edition] : []))
  .sort((a, b) => rank(a) - rank(b) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

/** The built-in edition with this id (case-insensitive), if any. */
export function namedEdition(id: string): Edition | undefined {
  const key = id.toLowerCase();
  return BUILT_IN_EDITIONS.find((edition) => edition.id === key);
}

/** Tabbi with the Essentials kit, from its file, or the built-in fallback values. */
export const TABBI_EDITION: Edition = namedEdition(DEFAULT_EDITION_ID) ?? FALLBACK_TABBI_EDITION;

/**
 * The edition a running app belongs to, from the edition id its build
 * carries (the Mac reads it from Info.plist; Windows from its build config).
 * A missing or unknown id is `fallback`, by default Tabbi.
 */
export function resolveEdition(editionID: unknown, fallback: Edition = TABBI_EDITION): Edition {
  return (typeof editionID === "string" ? namedEdition(editionID) : undefined) ?? fallback;
}
