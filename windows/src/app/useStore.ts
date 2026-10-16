/*
 * React's view of the runtime's stores: `useStore(store)` redraws a
 * component whenever the store changes, through `useSyncExternalStore`, so
 * module stores stay plain classes (store.ts) with no React in them.
 */

import { useCallback, useRef, useSyncExternalStore } from "react";
import type { Readable } from "./store";

/** The readable's current value; the component redraws when it changes. */
export function useStore<T>(store: Readable<T>): T;
/**
 * A part of the readable's value; the component redraws only when that part
 * changes (compared with `equals`, reference identity by default).
 */
export function useStore<T, U>(store: Readable<T>, select: (value: T) => U, equals?: (a: U, b: U) => boolean): U;
export function useStore<T, U>(
  store: Readable<T>,
  select?: (value: T) => U,
  equals: (a: U, b: U) => boolean = Object.is,
): T | U {
  const last = useRef<{ source: T; picked: U } | undefined>(undefined);
  const getSnapshot = useCallback((): T | U => {
    const value = store.get();
    if (select === undefined) return value;
    const previous = last.current;
    if (previous !== undefined && Object.is(previous.source, value)) return previous.picked;
    const picked = select(value);
    if (previous !== undefined && equals(previous.picked, picked)) {
      last.current = { source: value, picked: previous.picked };
      return previous.picked;
    }
    last.current = { source: value, picked };
    return picked;
  }, [store, select, equals]);
  return useSyncExternalStore(store.subscribe, getSnapshot, getSnapshot);
}
