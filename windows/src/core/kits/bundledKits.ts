import { KitLibrary, type KitFile } from "./kitLibrary";

/*
 * The kits that ship with Tabbi, read at build time from the Mac's
 * Kits/Bundled folder (never a copy), so shipping a kit is adding its file.
 */
const sources = import.meta.glob<string>("@mac/Kits/Bundled/*.json", {
  eager: true,
  query: "?raw",
  import: "default",
});

/** Every bundled kit file, in file-name order. */
export const BUNDLED_KIT_FILES: readonly KitFile[] = Object.entries(sources)
  .map(([path, text]) => ({ name: (path.split("/").pop() ?? path).replace(/\.json$/, ""), text }))
  .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));

/** The bundled kits, in picker order. */
export const BUNDLED_KITS: KitLibrary = KitLibrary.fromBundledFiles(BUNDLED_KIT_FILES);

/** True for kits that ship with the app (they can't be removed). */
export function isBundledKit(id: string): boolean {
  return BUNDLED_KITS.ids.includes(id);
}
