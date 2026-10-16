/*
 * The generator the coach, Cat wisdom and surprise gifts draw from, in
 * place of Swift's `RandomNumberGenerator`: a function returning a number
 * in [0, 1). The app passes `Math.random`; tests pass a seeded or fixed one,
 * so every pick is reproducible.
 */

export type RandomSource = () => number;

/** A draw in [0, 1), clamped so a source returning 1 can't step past the end. */
export function randomUnit(random: RandomSource): number {
  const value = random();
  return value >= 1 ? 1 - Number.EPSILON : Math.max(0, value);
}

/** An element of a non-empty list (Swift's `randomElement`); throws on an empty one, where Swift would trap. */
export function randomElement<Element>(items: readonly Element[], random: RandomSource): Element {
  const item = items[Math.floor(randomUnit(random) * items.length)];
  if (item === undefined) throw new RangeError("randomElement needs a non-empty list");
  return item;
}
