/*
 * The runtime's tiny reactive layer, the stand-in for the Mac's Combine
 * publishers and `ObservableObject`: a store is a plain class that holds a
 * value and tells subscribers when it changed. Nothing here imports React;
 * `useStore` (useStore.ts) is the one bridge, through `useSyncExternalStore`,
 * so stores stay testable in Vitest without a DOM.
 */

/** Something whose current value can be read and followed. React reads it through `useStore`. */
export interface Readable<T> {
  /** The current value. Returns the same object until it changes, so React can compare by reference. */
  get(): T;
  /** Calls `listener` after every change; returns the function that stops it. */
  subscribe(listener: () => void): () => void;
}

/** A set of listeners, notified in the order they subscribed. A listener may unsubscribe while being called. */
class Listeners {
  private readonly set = new Set<() => void>();

  add(listener: () => void): () => void {
    this.set.add(listener);
    return () => {
      this.set.delete(listener);
    };
  }

  notify(): void {
    for (const listener of [...this.set]) listener();
  }

  get size(): number {
    return this.set.size;
  }
}

/**
 * One reactive value: the Mac's `@Published var`. `set` replaces the value
 * and notifies only when it is a different one (by `equals`, reference
 * identity by default).
 */
export class Observable<T> implements Readable<T> {
  private value: T;
  private readonly listeners = new Listeners();

  constructor(
    initial: T,
    private readonly equals: (a: T, b: T) => boolean = Object.is,
  ) {
    this.value = initial;
  }

  readonly get = (): T => this.value;

  readonly subscribe = (listener: () => void): (() => void) => this.listeners.add(listener);

  set(next: T): void {
    if (this.equals(this.value, next)) return;
    this.value = next;
    this.listeners.notify();
  }

  update(change: (value: T) => T): void {
    this.set(change(this.value));
  }

  /** How many subscribers follow it, so a store can stop work nobody watches. */
  get subscriberCount(): number {
    return this.listeners.size;
  }
}

/**
 * Base class for a module's store, the Mac's `ObservableObject`: its state
 * is one immutable object that `setState` replaces (merging a patch), and
 * React redraws whatever reads it. A store whose state lives in mutable core
 * objects (a `FocusTimer`) changes them, then calls `changed()` with the new
 * snapshot.
 *
 * ```ts
 * class CounterStore extends Store<{ count: number }> {
 *   constructor() { super({ count: 0 }); }
 *   increment() { this.setState((s) => ({ count: s.count + 1 })); }
 * }
 * ```
 */
export class Store<S extends object> implements Readable<S> {
  private current: S;
  private readonly listeners = new Listeners();

  constructor(initial: S) {
    this.current = initial;
  }

  /** The state now. Read it in event handlers; components read it with `useStore`. */
  get state(): S {
    return this.current;
  }

  readonly get = (): S => this.current;

  readonly subscribe = (listener: () => void): (() => void) => this.listeners.add(listener);

  /** Merges `patch` into the state (or the patch `change` returns) and notifies, unless nothing differs. */
  protected setState(patch: Partial<S> | ((state: S) => Partial<S>)): void {
    const values = typeof patch === "function" ? patch(this.current) : patch;
    const keys = Object.keys(values) as (keyof S)[];
    if (keys.every((key) => Object.is(this.current[key], values[key]))) return;
    this.changed({ ...this.current, ...values });
  }

  /** Replaces the state with `next` and notifies, for stores that rebuild their snapshot themselves. */
  protected changed(next: S): void {
    this.current = next;
    this.listeners.notify();
  }
}

/** A stream of events nobody keeps a value of: the Mac's `PassthroughSubject` (kit applied, a record logged). */
export class Emitter<E> {
  private readonly listeners = new Set<(event: E) => void>();

  /** Calls `listener` with every later event; returns the function that stops it. */
  readonly on = (listener: (event: E) => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  emit(event: E): void {
    for (const listener of [...this.listeners]) listener(event);
  }
}

/**
 * A value worked out from other readables, recomputed when any of them
 * changes and kept while equal, so subscribers hear real changes only.
 * It follows its sources only while someone follows it.
 */
export function derived<T>(
  sources: readonly Readable<unknown>[],
  compute: () => T,
  equals: (a: T, b: T) => boolean = Object.is,
): Readable<T> {
  const listeners = new Listeners();
  let cached: { value: T } | undefined;
  let stops: (() => void)[] = [];
  const recompute = (): boolean => {
    const next = compute();
    if (cached !== undefined && equals(cached.value, next)) return false;
    cached = { value: next };
    return true;
  };
  return {
    get() {
      if (stops.length === 0 || cached === undefined) recompute();
      return (cached as { value: T }).value;
    },
    subscribe(listener) {
      if (listeners.size === 0) {
        recompute();
        stops = sources.map((source) =>
          source.subscribe(() => {
            if (recompute()) listeners.notify();
          }),
        );
      }
      const remove = listeners.add(listener);
      return () => {
        remove();
        if (listeners.size === 0) {
          for (const stop of stops) stop();
          stops = [];
        }
      };
    },
  };
}

/** A readable that never changes. */
export function constant<T>(value: T): Readable<T> {
  return { get: () => value, subscribe: () => () => {} };
}

/**
 * `source`'s value passed through `transform`, worked out again only when
 * the source changes: how a module turns its store into its provision,
 * `mapped(store, (state) => provisionOf(state))`.
 */
export function mapped<S, T>(source: Readable<S>, transform: (value: S) => T): Readable<T> {
  let last: { readonly source: S; readonly value: T } | undefined;
  return {
    get() {
      const value = source.get();
      if (last === undefined || !Object.is(last.source, value)) last = { source: value, value: transform(value) };
      return last.value;
    },
    subscribe: source.subscribe,
  };
}
