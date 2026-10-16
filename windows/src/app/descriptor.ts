/*
 * Descriptors whose words follow the language. A module's descriptor is a
 * constant made when its file loads, before the user's language is
 * installed, so the Mac's `String(localized:)` fields become getters that
 * ask the catalog each time they are read (the way core's built-in
 * categories do).
 */

import { moduleDescriptor, type ModuleDescriptor, type ModuleDescriptorInput } from "../core/modules/moduleDescriptor";

/** The descriptor's user-facing words, each read from the catalog when shown. */
export interface DescriptorTexts {
  readonly title?: () => string;
  readonly summary?: () => string;
  readonly highlightTitle?: () => string;
  /** The header shortcut's tooltip and accessibility label, e.g. "Your pet". */
  readonly shortcutLabel?: () => string;
}

/** `moduleDescriptor(input)` with the given fields read through `texts` on every access. */
export function localizedDescriptor(input: ModuleDescriptorInput, texts: DescriptorTexts): ModuleDescriptor {
  const descriptor = moduleDescriptor(input);
  const getters: PropertyDescriptorMap = {};
  if (texts.title) getters.title = { get: texts.title, enumerable: true };
  if (texts.summary) getters.summary = { get: texts.summary, enumerable: true };
  if (texts.highlightTitle) getters.highlightTitle = { get: texts.highlightTitle, enumerable: true };
  const shortcut = descriptor.headerShortcut;
  const label = texts.shortcutLabel;
  if (shortcut !== undefined && label !== undefined) {
    getters.headerShortcut = {
      value: Object.defineProperty({ key: shortcut.key }, "label", { get: label, enumerable: true }),
      enumerable: true,
    };
  }
  return Object.defineProperties({ ...descriptor }, getters) as ModuleDescriptor;
}
