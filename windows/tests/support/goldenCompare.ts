/*
 * Compares a port's output with a recorded golden value: the same keys (an
 * `undefined` field counts as absent, the way Swift's encoder leaves out a
 * nil), the same array lengths, equal strings and booleans, and numbers
 * within `tolerance` (1e-9 by default, as shared/README.md asks).
 * Returns the first difference as a readable path, or undefined when equal.
 */
export function goldenDiff(actual: unknown, expected: unknown, path = "$", tolerance = 1e-9): string | undefined {
  if (typeof expected === "number") {
    if (typeof actual !== "number") return `${path}: expected ${expected}, got ${JSON.stringify(actual)}`;
    if (Math.abs(actual - expected) > tolerance) return `${path}: expected ${expected}, got ${actual}`;
    return undefined;
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual)) return `${path}: expected an array, got ${JSON.stringify(actual)}`;
    if (actual.length !== expected.length) {
      return `${path}: expected ${expected.length} items, got ${actual.length} (${JSON.stringify(actual)})`;
    }
    for (let index = 0; index < expected.length; index++) {
      const difference = goldenDiff(actual[index], expected[index], `${path}[${index}]`, tolerance);
      if (difference !== undefined) return difference;
    }
    return undefined;
  }
  if (typeof expected === "object" && expected !== null) {
    if (typeof actual !== "object" || actual === null || Array.isArray(actual)) {
      return `${path}: expected an object, got ${JSON.stringify(actual)}`;
    }
    const expectedRecord = expected as Record<string, unknown>;
    const actualRecord = actual as Record<string, unknown>;
    const actualKeys = Object.keys(actualRecord).filter((key) => actualRecord[key] !== undefined);
    for (const key of actualKeys) {
      if (!(key in expectedRecord)) return `${path}.${key}: not recorded, got ${JSON.stringify(actualRecord[key])}`;
    }
    for (const key of Object.keys(expectedRecord)) {
      if (actualRecord[key] === undefined) return `${path}.${key}: missing, expected ${JSON.stringify(expectedRecord[key])}`;
      const difference = goldenDiff(actualRecord[key], expectedRecord[key], `${path}.${key}`, tolerance);
      if (difference !== undefined) return difference;
    }
    return undefined;
  }
  if (actual !== expected) return `${path}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`;
  return undefined;
}
