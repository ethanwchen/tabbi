import { defineConfig } from "@playwright/test";

/*
 * Snapshot runs: every island state rendered to PNG in Microsoft Edge, the
 * same engine as WebView2, against a production build of the UI and the
 * mock host. The PNGs land in tests/snapshots/output/ for a person (or an
 * agent) to look at.
 */

/*
 * Its own server on its own port, never one already running: a server left
 * on 1420 by `npm run app` or another worktree would serve other code, and
 * the PNGs would silently show that instead of this checkout. Runs side by
 * side (several worktrees at once) pick different ports with
 * TABBI_SNAPSHOT_PORT.
 *
 * It serves the built bundle (`vite preview`), not the dev server: the dev
 * server compiles every module on demand, and a dozen browsers asking for
 * hundreds of modules at once (the pet art alone is large) made page loads
 * slow enough to time out. A bundle loads the same way every time, which is
 * also what the app ships.
 */
const port = Number(process.env.TABBI_SNAPSHOT_PORT ?? 1421);
const origin = `http://localhost:${port}`;

export default defineConfig({
  testDir: "tests/snapshots",
  outputDir: "test-results",
  reporter: "list",
  /* A few browsers at a time: each test walks many states, and more workers only queue on the CPU. */
  workers: 4,
  /*
   * Every test opens its own page and writes its own PNGs, so tests within a
   * file run in parallel too, and CI's --shard splits the run by test rather
   * than by file: by file, one shard got the 3 minute gallery and the others
   * 20 minutes each of module panels and settings.
   */
  fullyParallel: true,
  /* Each test renders every state of its run in one page, so its budget grows with the list, not per page. */
  timeout: 10 * 60_000,
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
    command: `npm run build && npx vite preview --port ${port} --strictPort`,
    url: origin,
    reuseExistingServer: false,
    timeout: 3 * 60_000,
  },
});
