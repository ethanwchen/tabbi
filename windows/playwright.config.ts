import { defineConfig } from "@playwright/test";

/*
 * Snapshot runs: every island state rendered to PNG in Microsoft Edge, the
 * same engine as WebView2, against the Vite dev server and the mock host.
 * The PNGs land in tests/snapshots/output/ for a person (or an agent) to look at.
 */

/*
 * Its own server on its own port, never one already running: a dev server
 * left on 1420 by `npm run app` or another worktree would serve other code,
 * and the PNGs would silently show that instead of this checkout. Runs side
 * by side (several worktrees at once) pick different ports with
 * TABBI_SNAPSHOT_PORT.
 */
const port = Number(process.env.TABBI_SNAPSHOT_PORT ?? 1421);
const origin = `http://localhost:${port}`;

export default defineConfig({
  testDir: "tests/snapshots",
  outputDir: "test-results",
  /* One test shoots every state of every module, well over the default 30 s. */
  timeout: 600_000,
  reporter: "list",
  use: {
    baseURL: origin,
    channel: "msedge",
    viewport: { width: 560, height: 236 },
  },
  projects: [
    { name: "100", use: { deviceScaleFactor: 1 } },
    { name: "150", use: { deviceScaleFactor: 1.5 } },
  ],
  webServer: {
    command: `npm run strings && npx vite --port ${port} --strictPort`,
    url: origin,
    reuseExistingServer: false,
  },
});
