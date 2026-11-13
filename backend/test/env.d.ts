import type { Env as WorkerEnv } from "../src/index";

declare global {
  namespace Cloudflare {
    // eslint-disable-next-line @typescript-eslint/no-empty-object-type
    interface Env extends WorkerEnv {}
  }
  /** Vite's eager glob import, which the tests use to read a shared fixture only when it exists. */
  interface ImportMeta {
    glob<T = unknown>(pattern: string, options: { eager: true; import: "default" }): Record<string, T>;
  }
}
