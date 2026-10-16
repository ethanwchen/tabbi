/*
 * Messages between Tabbi's windows. The island and the Settings window are
 * separate webviews with separate stores, so a change one makes (a setting,
 * a kit switch, a module's own option) is posted on a named topic and the
 * other windows apply it. A window never hears its own posts.
 */

import type { Host, JsonValue } from "../host/host";

export interface WindowChannel {
  post(message: JsonValue): void;
  /** Calls `listener` with every message another window posts; returns the function that stops it. */
  on(listener: (message: unknown) => void): () => void;
}

/** The channel `topic` over the host's broadcast. */
export function hostChannel(host: Pick<Host, "broadcast" | "onBroadcast">, topic: string): WindowChannel {
  return {
    post: (message) => {
      void host.broadcast(topic, message).catch((error: unknown) => console.error("tabbi broadcast", topic, error));
    },
    on: (listener) => host.onBroadcast(topic, listener),
  };
}

/** A channel nobody else hears, for snapshot runs and tests. */
export const quietChannel: WindowChannel = { post: () => {}, on: () => () => {} };
