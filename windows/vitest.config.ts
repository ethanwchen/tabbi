import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

const repo = (path: string) => fileURLToPath(new URL(`../${path}`, import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      "@mac": repo("Sources/TabbiKitCore"),
      "@shared": repo("shared"),
      "@backend": repo("backend"),
    },
  },
  test: {
    include: ["tests/unit/**/*.test.ts", "tests/fixtures/**/*.test.ts"],
    environment: "node",
    /*
     * The core never reads the machine's time zone: wall-clock math takes an
     * IANA zone explicitly. A fixed, non-UTC zone here makes any accidental
     * use of the local zone fail loudly instead of passing on a UTC runner.
     */
    env: { TZ: "Pacific/Chatham" },
  },
});
