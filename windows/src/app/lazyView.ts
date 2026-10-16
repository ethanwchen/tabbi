/*
 * Module views loaded on first use. A module's store and descriptor stay in
 * the main chunk (providers, the ticker and the pet read them at launch),
 * while its panel, settings pane and setup views load when first drawn, so
 * the island starts on a smaller script. Every loader is remembered, so the
 * snapshot harness can wait for all of them before it marks a frame ready.
 */

import { createElement, lazy, useState, type ComponentType } from "react";

const loaders: (() => Promise<unknown>)[] = [];

/**
 * A named export of a lazily imported file as a component; `name` must be
 * one of the file's exports. It suspends only while the file is still
 * loading: once loaded it draws at once, and each instance keeps the
 * component it mounted with, so its state survives the load finishing.
 */
export function lazyView<M extends Record<K, ComponentType<never>>, K extends string>(load: () => Promise<M>, name: K): M[K] {
  let loaded: ComponentType<object> | undefined;
  let pending: Promise<{ default: ComponentType<object> }> | undefined;
  const loader = () => {
    pending ??= load().then((file) => {
      /* The constraint on M guarantees a component; its props are checked where the view is drawn. */
      const view = file[name] as unknown as ComponentType<object>;
      loaded = view;
      return { default: view };
    });
    return pending;
  };
  loaders.push(loader);
  const Suspending = lazy(loader);
  function LazyView(props: object) {
    const [Component] = useState<ComponentType<object>>(() => loaded ?? Suspending);
    return createElement(Component, props);
  }
  LazyView.displayName = `Lazy(${name})`;
  return LazyView as unknown as M[K];
}

/** Loads every lazy view declared so far; a lazy view drawn after this renders at once. */
export async function preloadLazyViews(): Promise<void> {
  await Promise.all(loaders.map((loader) => loader()));
}
