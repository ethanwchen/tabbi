/*
 * The Windows side of recording a shortcut: a browser `KeyboardEvent` turned
 * into the core's `Hotkey` (a macOS key code plus modifier bits, so the
 * saved value means the same on both apps). `code` names the physical key,
 * so the shortcut survives keyboard layouts the way the Mac's key codes
 * do; Ctrl is Control, Alt is Option, Shift is Shift and the Windows key is
 * Command. Also the plain-words labels the recorder shows, and the few
 * combinations Windows keeps for itself, which no app can register.
 */

import { HOTKEY_MODIFIERS, recordHotkey, type Hotkey, type HotkeyRecording } from "../../core/settings/hotkey";
import { tr } from "../../core/localization/tr";

/** `KeyboardEvent.code` to the Mac's `kVK_*` key code, for every key the core can name. */
export const CODE_TO_KEY_CODE: Readonly<Record<string, number>> = {
  KeyA: 0, KeyB: 11, KeyC: 8, KeyD: 2, KeyE: 14, KeyF: 3, KeyG: 5, KeyH: 4, KeyI: 34,
  KeyJ: 38, KeyK: 40, KeyL: 37, KeyM: 46, KeyN: 45, KeyO: 31, KeyP: 35, KeyQ: 12,
  KeyR: 15, KeyS: 1, KeyT: 17, KeyU: 32, KeyV: 9, KeyW: 13, KeyX: 7, KeyY: 16, KeyZ: 6,
  Digit0: 29, Digit1: 18, Digit2: 19, Digit3: 20, Digit4: 21, Digit5: 23, Digit6: 22, Digit7: 26, Digit8: 28, Digit9: 25,
  Space: 49, Enter: 36, Tab: 48, Escape: 53, Backspace: 51,
  ArrowLeft: 123, ArrowRight: 124, ArrowDown: 125, ArrowUp: 126,
  Minus: 27, Equal: 24, BracketLeft: 33, BracketRight: 30, Semicolon: 41, Quote: 39, Comma: 43, Period: 47, Slash: 44,
  Backslash: 42, Backquote: 50,
  F1: 122, F2: 120, F3: 99, F4: 118, F5: 96, F6: 97, F7: 98, F8: 100, F9: 101, F10: 109, F11: 103, F12: 111,
};

/** The slice of a KeyboardEvent the recorder reads, so tests can pass plain objects. */
export interface KeyLike {
  readonly code: string;
  readonly key?: string;
  readonly ctrlKey: boolean;
  readonly altKey: boolean;
  readonly shiftKey: boolean;
  readonly metaKey: boolean;
  readonly repeat?: boolean;
}

const MODIFIER_CODES = new Set([
  "ControlLeft", "ControlRight", "AltLeft", "AltRight", "ShiftLeft", "ShiftRight", "MetaLeft", "MetaRight",
]);

/** True for a press of a modifier key on its own. */
export function isModifierCode(code: string): boolean {
  return MODIFIER_CODES.has(code);
}

/** The core's modifier bits for the modifiers held in `event`. */
export function modifiersOf(event: KeyLike): number {
  let modifiers = 0;
  if (event.ctrlKey) modifiers |= HOTKEY_MODIFIERS.control;
  if (event.altKey) modifiers |= HOTKEY_MODIFIERS.option;
  if (event.shiftKey) modifiers |= HOTKEY_MODIFIERS.shift;
  if (event.metaKey) modifiers |= HOTKEY_MODIFIERS.command;
  return modifiers;
}

/** The Mac key code for a browser `code`, or undefined for a key Tabbi cannot use as a shortcut. */
export function keyCodeOf(code: string): number | undefined {
  return Object.hasOwn(CODE_TO_KEY_CODE, code) ? CODE_TO_KEY_CODE[code] : undefined;
}

/** What one key press means while recording; a lone modifier press means nothing yet. */
export type KeyMeaning = HotkeyRecording | { readonly kind: "modifierOnly" };

export function interpretKey(event: KeyLike): KeyMeaning {
  if (isModifierCode(event.code)) return { kind: "modifierOnly" };
  const keyCode = keyCodeOf(event.code);
  if (keyCode === undefined) return { kind: "unsupportedKey" };
  return recordHotkey(keyCode, modifiersOf(event));
}

/** The held modifiers as Windows labels them, in Windows' order: "Ctrl+Alt". */
export function modifiersLabel(modifiers: number): string {
  const parts: string[] = [];
  if (modifiers & HOTKEY_MODIFIERS.control) parts.push("Ctrl");
  if (modifiers & HOTKEY_MODIFIERS.option) parts.push("Alt");
  if (modifiers & HOTKEY_MODIFIERS.shift) parts.push("Shift");
  if (modifiers & HOTKEY_MODIFIERS.command) parts.push("Win");
  return parts.join("+");
}

const { control, option, shift, command } = HOTKEY_MODIFIERS;

/*
 * Shortcuts Windows handles before any app sees them, so RegisterHotKey
 * either fails or never fires. Checked by key code and exact modifiers.
 */
const RESERVED: readonly { keyCode: number; modifiers: number }[] = [
  { keyCode: 51, modifiers: control | option }, // Ctrl+Alt+Delete (Backspace stands in for Delete on the Mac's codes)
  { keyCode: 37, modifiers: command }, // Win+L locks the PC
  { keyCode: 48, modifiers: command }, // Win+Tab
  { keyCode: 48, modifiers: option }, // Alt+Tab
  { keyCode: 53, modifiers: control | shift }, // Ctrl+Shift+Esc, Task Manager
  { keyCode: 118, modifiers: option }, // Alt+F4
  { keyCode: 37, modifiers: control | option | command }, // Ctrl+Alt+Win+L
];

/** Why Windows keeps `hotkey` for itself, in plain words, or undefined when an app may claim it. */
export function windowsReservedReason(hotkey: Hotkey): string | undefined {
  const reserved = RESERVED.some((r) => r.keyCode === hotkey.keyCode && r.modifiers === hotkey.modifiers);
  return reserved ? tr("Windows uses %@ itself, so Tabbi can't take it. Record a different shortcut.", windowsLabel(hotkey)) : undefined;
}

/**
 * The shortcut as the host registers it (the global shortcut plugin's
 * form, "ctrl+alt+Space"): modifiers by name, then the physical key's
 * `KeyboardEvent.code`, so a saved Mac key code maps back to the same key.
 * Undefined for a key the host cannot register.
 */
export function hostShortcut(hotkey: Hotkey): string | undefined {
  const code = Object.entries(CODE_TO_KEY_CODE).find(([, value]) => value === hotkey.keyCode)?.[0];
  if (code === undefined) return undefined;
  const parts: string[] = [];
  if (hotkey.modifiers & control) parts.push("ctrl");
  if (hotkey.modifiers & option) parts.push("alt");
  if (hotkey.modifiers & shift) parts.push("shift");
  if (hotkey.modifiers & command) parts.push("super");
  parts.push(code);
  return parts.join("+");
}

/** The Windows label for a hotkey, from the core. */
export function windowsLabel(hotkey: Hotkey): string {
  const parts: string[] = [];
  const label = modifiersLabel(hotkey.modifiers);
  if (label) parts.push(label);
  parts.push(keyName(hotkey.keyCode));
  return parts.join("+");
}

function keyName(keyCode: number): string {
  for (const [code, value] of Object.entries(CODE_TO_KEY_CODE)) {
    if (value !== keyCode) continue;
    if (code.startsWith("Key")) return code.slice(3);
    if (code.startsWith("Digit")) return code.slice(5);
    switch (code) {
      case "ArrowLeft": return "←";
      case "ArrowRight": return "→";
      case "ArrowDown": return "↓";
      case "ArrowUp": return "↑";
      case "Escape": return "Esc";
      case "Minus": return "-";
      case "Equal": return "=";
      case "BracketLeft": return "[";
      case "BracketRight": return "]";
      case "Semicolon": return ";";
      case "Quote": return "'";
      case "Comma": return ",";
      case "Period": return ".";
      case "Slash": return "/";
      case "Backslash": return "\\";
      case "Backquote": return "`";
      default: return code;
    }
  }
  return `Key ${keyCode}`;
}

/** The one line the recorder shows for a refusal. */
export function rejectionText(rejection: HotkeyRecording | { kind: "modifierOnly" }): string | undefined {
  switch (rejection.kind) {
    case "needsModifier":
      return tr("Add Control or Option so the shortcut doesn't get in the way of typing.");
    case "unsupportedKey":
      return tr("That key can't be part of a shortcut. Try a letter, number, or Space.");
    default:
      return undefined;
  }
}
