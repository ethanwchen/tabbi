/*
 * The UI's only door to the Rust host. Components talk to a Host, never to
 * Tauri, so the same UI runs inside the app, in Vitest and in the Playwright
 * snapshot runs (against the mock in mock.ts).
 */

import type { HitRect } from "../ui/shell/geometry";

export type HostSource = "hotkey" | "tray" | "launch";

export interface HotkeyStatus {
  readonly shortcut: string;
  readonly registered: boolean;
}

export interface Startup {
  readonly hotkey: HotkeyStatus | null;
  /* A development override of the closed-island mode; null in release builds. */
  readonly notchMode: string | null;
}

export type HostEvent =
  | { type: "hotZone" }
  | { type: "toggle"; source: HostSource }
  | { type: "open"; source: HostSource }
  | { type: "outsideClick" }
  | { type: "fullscreen"; active: boolean }
  | { type: "focus"; focused: boolean }
  | { type: "link"; url: string }
  | { type: "placed"; scale: number };

export interface Host {
  /* Limits drawing and clicks to this rectangle of the window, or to nothing. */
  setShape(rect: HitRect | null): Promise<void>;
  /* Open lets the panel take focus and watches for clicks outside it. */
  setOpen(open: boolean): Promise<void>;
  activate(): Promise<void>;
  restoreFocus(): Promise<void>;
  armHotZone(armed: boolean): Promise<void>;
  /* Shows the window once the first frame is drawn. */
  ready(): Promise<Startup>;
  subscribe(listener: (event: HostEvent) => void): () => void;
}
