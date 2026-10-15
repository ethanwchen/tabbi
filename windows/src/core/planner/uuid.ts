/*
 * Ids the planner gives checklist items and plan blocks: UUIDs written the
 * way Foundation's `UUID.uuidString` writes them (upper case), so files the
 * Mac and Windows write read the same.
 */

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A new random UUID, upper case. */
export function newUUID(): string {
  return globalThis.crypto.randomUUID().toUpperCase();
}

/** `text` as an upper-case UUID, or undefined when it isn't one (`UUID(uuidString:)`). */
export function parseUUID(text: string): string | undefined {
  return UUID_PATTERN.test(text) ? text.toUpperCase() : undefined;
}

/** The demo data's fixed ids, `00000000-0000-4000-8000-<number as 12 digits>`. */
export function sampleUUID(number: number): string {
  return `00000000-0000-4000-8000-${String(number).padStart(12, "0")}`;
}
