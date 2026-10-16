import { isJSONObject } from "../persistence/json";

/**
 * Port of Hotkey: a global keyboard shortcut, stored as the Mac stores it,
 * a macOS virtual key code (`kVK_*`) plus a modifier bit set, so the saved
 * value means the same on both apps. The Windows host maps it to a virtual
 * key and `MOD_*` flags when it registers the shortcut: Option is Alt and
 * Command is the Windows key.
 */
export interface Hotkey {
  readonly keyCode: number;
  readonly modifiers: number;
}

/** Modifier bits, as the Mac's `Hotkey.Modifiers` option set stores them. */
export const HOTKEY_MODIFIERS = {
  control: 1 << 0,
  option: 1 << 1,
  shift: 1 << 2,
  command: 1 << 3,
} as const;

/** ANSI virtual key codes (Carbon's `kVK_*`) and their display names. */
export const HOTKEY_KEY_CODES = {
  space: 49,
  escape: 53,
} as const;

const KEY_NAMES: Readonly<Record<number, string>> = {
  0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
  38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
  15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
  29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
  49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
  123: "\u2190", 124: "\u2192", 125: "\u2193", 126: "\u2191",
  27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
  42: "\\", 50: "`",
  122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
  98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
};

/** Display name for a key code, or undefined for keys Tabbi doesn't support as hotkeys. */
export function hotkeyKeyName(keyCode: number): string | undefined {
  return KEY_NAMES[keyCode];
}

/** Control-Option-Space on the Mac, which is Ctrl+Alt+Space on Windows. */
export const DEFAULT_HOTKEY: Hotkey = {
  keyCode: HOTKEY_KEY_CODES.space,
  modifiers: HOTKEY_MODIFIERS.control | HOTKEY_MODIFIERS.option,
};

const { control, option, shift, command } = HOTKEY_MODIFIERS;

/** A global shortcut needs Control, Option or Command and a key Tabbi can name; Shift alone would swallow typing. */
export function isValidHotkey(hotkey: Hotkey): boolean {
  return (hotkey.modifiers & (control | option | command)) !== 0 && hotkeyKeyName(hotkey.keyCode) !== undefined;
}

/** Modifier symbols in Apple's order, e.g. "\u2303\u2325". */
export function hotkeyModifierSymbols(modifiers: number): string {
  let symbols = "";
  if (modifiers & control) symbols += "\u2303";
  if (modifiers & option) symbols += "\u2325";
  if (modifiers & shift) symbols += "\u21e7";
  if (modifiers & command) symbols += "\u2318";
  return symbols;
}

/** The Mac's form, e.g. "\u2303\u2325Space". */
export function hotkeyDisplayString(hotkey: Hotkey): string {
  return hotkeyModifierSymbols(hotkey.modifiers) + (hotkeyKeyName(hotkey.keyCode) ?? `Key ${hotkey.keyCode}`);
}

/** The form Windows shows, e.g. "Ctrl+Alt+Space", in Windows' own modifier order. */
export function windowsHotkeyLabel(hotkey: Hotkey): string {
  const parts: string[] = [];
  if (hotkey.modifiers & control) parts.push("Ctrl");
  if (hotkey.modifiers & option) parts.push("Alt");
  if (hotkey.modifiers & shift) parts.push("Shift");
  if (hotkey.modifiers & command) parts.push("Win");
  parts.push(hotkeyKeyName(hotkey.keyCode) ?? `Key ${hotkey.keyCode}`);
  return parts.join("+");
}

/** What one key press means while the user records a new shortcut. */
export type HotkeyRecording =
  | { readonly kind: "recorded"; readonly hotkey: Hotkey }
  /** Esc on its own: stop recording and keep the current shortcut. */
  | { readonly kind: "cancelled" }
  /** The combination lacks a modifier that makes it safe to claim system-wide. */
  | { readonly kind: "needsModifier" }
  /** A key Tabbi can't name or register. */
  | { readonly kind: "unsupportedKey" };

/**
 * Interprets one key press in the shortcut recorder. Stricter than
 * `isValidHotkey`: Command on its own is refused too, because a global
 * shortcut like Command-C would swallow that shortcut in every app.
 */
export function recordHotkey(keyCode: number, modifiers: number): HotkeyRecording {
  if (keyCode === HOTKEY_KEY_CODES.escape && modifiers === 0) return { kind: "cancelled" };
  if (hotkeyKeyName(keyCode) === undefined) return { kind: "unsupportedKey" };
  const safe = (modifiers & (control | option)) !== 0 || (modifiers & (command | shift)) === (command | shift);
  if (!safe) return { kind: "needsModifier" };
  return { kind: "recorded", hotkey: { keyCode, modifiers } };
}

/** The stored JSON, as the Mac's `JSONEncoder` writes it: `{"keyCode":49,"modifiers":3}`. */
export function encodeHotkey(hotkey: Hotkey): string {
  return JSON.stringify({ keyCode: hotkey.keyCode, modifiers: hotkey.modifiers });
}

/** Reads a stored hotkey, or undefined when it isn't one. */
export function decodeHotkey(text: string): Hotkey | undefined {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return undefined;
  }
  if (!isJSONObject(json)) return undefined;
  const { keyCode, modifiers } = json;
  if (typeof keyCode !== "number" || !Number.isInteger(keyCode) || keyCode < 0 || keyCode > 0xffffffff) return undefined;
  if (typeof modifiers !== "number" || !Number.isInteger(modifiers)) return undefined;
  return { keyCode, modifiers };
}
