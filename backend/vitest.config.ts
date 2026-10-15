import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

/**
 * A throwaway Sign in with Apple key made for each test run (PKCS#8 PEM, like Apple's .p8 file), so the
 * code exchange and revoke paths run against mocked Apple endpoints without any real secret in the repo.
 */
async function throwawayAppleKey(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const b64 = btoa(String.fromCharCode(...der)).replace(/(.{64})/g, "$1\n");
  return `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;
}

export default defineConfig(async () => ({
  // A few tests drive dozens of requests through the Worker (friend caps and rate limits); the 5 s default
  // is too tight on a shared CI runner, so every test gets 30 s.
  test: { testTimeout: 30_000 },
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.toml" },
    miniflare: {
      bindings: {
        APPLE_TEAM_ID: "TESTTEAM01",
        APPLE_KEY_ID: "TESTKEY001",
        APPLE_PRIVATE_KEY: await throwawayAppleKey(),
        // A launch on March 1, 2026 closes the founding window at the end of June 8, 2026 (entitlements.test.ts).
        FOUNDING_LAUNCH: "2026-03-01",
        ADMIN_TOKEN: Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, "0")).join(""),
      },
    },
  })],
}));
