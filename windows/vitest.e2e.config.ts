import { defineConfig } from "vitest/config";
import base from "./vitest.config";

/*
 * The end-to-end suites, kept out of `npm test` because they need a running
 * server: `TABBI_PARTY_SERVER=http://localhost:8787 npm run test:e2e` with
 * `npx wrangler dev` running in backend/ (local mode). Without the variable
 * every suite skips. Only `include` and the timeouts differ from the unit
 * config, so aliases and the fixed time zone stay the same.
 */
export default defineConfig({
  ...base,
  test: {
    ...base.test,
    include: ["tests/e2e/**/*.test.ts"],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    fileParallelism: false,
  },
});
