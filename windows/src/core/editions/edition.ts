import { DEFAULT_KIT_ID } from "../kits/kitLibrary";
import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { ModuleID } from "../modules/moduleId";
import { isJSONObject } from "../persistence/json";

/** Where an edition's builds are published, which decides what it may do. */
export type EditionDistribution = "direct" | "appStore";

/**
 * Port of Edition: a branded build of the same app. An edition only changes
 * identity and first-run defaults (the name, bundle id, preselected kit and
 * data folder) and may leave modules out. Editions are data: each is a
 * `<id>.json` in the Mac's Editions/BundledEditions folder.
 */
export interface Edition {
  /** Stable lowercase id; also the edition file's name. */
  readonly id: string;
  /** User-facing app name, and the name of the edition's data folder. */
  readonly name: string;
  readonly bundleIdentifier: string;
  /** The kit a fresh install starts with, and falls back to. */
  readonly defaultKitID: string;
  /** An icon file name used only by the Mac's packaging; undefined keeps the default icon. */
  readonly icon?: string;
  /** Info.plist strings for the Mac's packaging. */
  readonly infoPlist: Readonly<Record<string, string>>;
  readonly distribution: EditionDistribution;
  /** Modules this edition leaves out; its catalog drops them. */
  readonly excludedModules: readonly ModuleID[];
}

/** Port of EditionError: why an edition file can't be used. */
export type EditionError =
  | { readonly kind: "invalid"; readonly reason: string }
  /** The file needs a newer build (its `formatVersion` is higher). */
  | { readonly kind: "unsupportedFormat"; readonly version: number };

export type EditionLoadResult =
  | { readonly ok: true; readonly edition: Edition }
  | { readonly ok: false; readonly error: EditionError };

/** The edition file format this build reads. */
export const EDITION_FORMAT_VERSION = 1;

/** The Info.plist key that names a packaged Mac app's edition. */
export const EDITION_INFO_KEY = "TabbiEdition";

/** The id of the edition used when none is named. */
export const DEFAULT_EDITION_ID = "tabbi";

/** Tabbi with the Essentials kit, used when its file can't be read, so the app always has an edition. */
export const FALLBACK_TABBI_EDITION: Edition = {
  id: DEFAULT_EDITION_ID,
  name: "Tabbi",
  bundleIdentifier: "dev.tabbi.Tabbi",
  defaultKitID: DEFAULT_KIT_ID,
  infoPlist: {},
  distribution: "direct",
  excludedModules: [],
};

export function isAppStoreEdition(edition: Edition): boolean {
  return edition.distribution === "appStore";
}

/** Whether the app may run helper programs (the claude CLI); a sandboxed store build can't. */
export function editionRunsLocalTools(edition: Edition): boolean {
  return edition.distribution === "direct";
}

/** The modules this edition offers: `catalog` without its excluded modules, remembered as unavailable. */
export function editionCatalog(edition: Edition, catalog: ModuleCatalog): ModuleCatalog {
  return catalog.excluding(edition.excludedModules);
}

function invalid(reason: string): EditionLoadResult {
  return { ok: false, error: { kind: "invalid", reason } };
}

/** Trims spaces and tabs, as Foundation's `.whitespaces` set does (not newlines). */
function trimSpaces(text: string): string {
  return text.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
}

const RESERVED_INFO_KEYS = ["CFBundleName", "CFBundleDisplayName", "CFBundleIdentifier", EDITION_INFO_KEY];

/** The decoded fields, or undefined when the structure is wrong (the Mac's decoding error). */
function readEdition(json: unknown): Edition | EditionError | undefined {
  if (!isJSONObject(json)) return undefined;
  const { formatVersion, id, name, bundleIdentifier, defaultKitID, icon, infoPlist, distribution, excludedModules } = json;
  if (typeof formatVersion !== "number" || !Number.isInteger(formatVersion)) return undefined;
  if (formatVersion < 1 || formatVersion > EDITION_FORMAT_VERSION) return { kind: "unsupportedFormat", version: formatVersion };
  if (typeof id !== "string" || typeof name !== "string") return undefined;
  if (typeof bundleIdentifier !== "string" || typeof defaultKitID !== "string") return undefined;
  if (icon !== undefined && icon !== null && typeof icon !== "string") return undefined;
  let plist: Record<string, string> = {};
  if (infoPlist !== undefined && infoPlist !== null) {
    if (!isJSONObject(infoPlist) || !Object.values(infoPlist).every((value) => typeof value === "string")) return undefined;
    plist = infoPlist as Record<string, string>;
  }
  let channel: EditionDistribution = "direct";
  if (distribution !== undefined && distribution !== null) {
    if (distribution !== "direct" && distribution !== "appStore") return undefined;
    channel = distribution;
  }
  let excluded: string[] = [];
  if (excludedModules !== undefined && excludedModules !== null) {
    if (!Array.isArray(excludedModules) || !excludedModules.every((module) => typeof module === "string")) return undefined;
    excluded = excludedModules as string[];
  }
  const edition: Edition = {
    id,
    name,
    bundleIdentifier,
    defaultKitID,
    infoPlist: plist,
    distribution: channel,
    excludedModules: excluded,
  };
  return typeof icon === "string" ? { ...edition, icon } : edition;
}

/**
 * Port of Edition.decode(from:): reads an edition file and checks the values
 * packaging and the app rely on: a lowercase slug id, a name usable as a
 * folder name, a reverse-DNS bundle id and a plain icon file name. Never throws.
 */
export function decodeEdition(text: string): EditionLoadResult {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return invalid("not a valid edition file");
  }
  const read = readEdition(json);
  if (read === undefined) return invalid("not a valid edition file");
  if ("kind" in read) return { ok: false, error: read };
  const edition = read;
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(edition.id)) {
    return invalid(`id "${edition.id}" must be lowercase letters, digits and hyphens`);
  }
  const name = trimSpaces(edition.name);
  if (name === "" || name !== edition.name || name.includes("/") || name.startsWith(".")) {
    return invalid(`name "${edition.name}" can't be used as an app or folder name`);
  }
  if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(edition.bundleIdentifier)) {
    return invalid(`bundle id "${edition.bundleIdentifier}" isn't reverse-DNS`);
  }
  if (edition.defaultKitID === "") return invalid("defaultKitID is empty");
  if (edition.icon !== undefined) {
    const icon = edition.icon;
    if (!icon.endsWith(".icns") || icon.includes("/") || icon.startsWith(".")) {
      return invalid(`icon "${icon}" must be an .icns file name in Resources`);
    }
  }
  const bad = edition.excludedModules.find((module) => !/^[A-Za-z][A-Za-z0-9]*$/.test(module));
  if (bad !== undefined) return invalid(`excludedModules has "${bad}", which isn't a module id`);
  const reserved = Object.keys(edition.infoPlist)
    .sort()
    .find((key) => RESERVED_INFO_KEYS.includes(key));
  if (reserved !== undefined) return invalid(`infoPlist can't set ${reserved}; it comes from the edition's own fields`);
  return { ok: true, edition };
}

/** Port of Edition.load(from:): one edition file, whose id must match its file name (without `.json`). */
export function loadEditionFile(fileName: string, text: string): EditionLoadResult {
  const result = decodeEdition(text);
  if (!result.ok) return result;
  if (result.edition.id !== fileName) {
    return invalid(`id "${result.edition.id}" doesn't match its file name "${fileName}"`);
  }
  return result;
}
