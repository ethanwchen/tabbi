import { defineConfig } from "@playwright/test";

/*
 * Snapshot runs: every island state rendered to PNG in Microsoft Edge, the
 * same engine as WebView2, against the Vite dev server and the mock host.
 * The PNGs land in tests/snapshots/output/ for a person (or an agent) to look at.
 */
export default defineConfig({
  testDir: "tests/snapshots",
  outputDir: "test-results",
  reporter: "list",
  use: {
    baseURL: "http://localhost:1420",
    channel: "msedge",
    viewport: { width: 560, height: 236 },
  },
  projects: [
    { name: "100", use: { deviceScaleFactor: 1 } },
    { name: "150", use: { deviceScaleFactor: 1.5 } },
  ],
  webServer: {
    command: "npm run dev",
    url: "http://localhost:1420",
    reuseExistingServer: true,
  },
});
