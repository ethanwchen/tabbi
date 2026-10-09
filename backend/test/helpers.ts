import { SELF, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { expect } from "vitest";

export const BASE = "https://tabbi.test";

let ipCounter = 0;
/** A fresh fake client IP, so per-IP registration limits never leak between tests. */
export const freshIp = () => `10.0.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`;

export interface Reply {
  status: number;
  headers: Headers;
  body: any; // eslint-disable-line @typescript-eslint/no-explicit-any
}

export async function call(method: string, path: string, body?: unknown, token?: string, ip = "10.255.0.1"): Promise<Reply> {
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": ip };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await SELF.fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, headers: res.headers, body: text ? JSON.parse(text) : null };
}

export async function register(profile: Record<string, unknown> = {}) {
  const r = await call("POST", "/v1/register", profile, undefined, freshIp());
  expect(r.status).toBe(201);
  expect(r.body.token).toMatch(/^[0-9a-f]{64}$/);
  expect(r.body.code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  return r.body as { token: string; code: string; profile: Record<string, unknown> };
}

export function expectError(r: Reply, status: number, error: string) {
  expect(r.status).toBe(status);
  expect(r.body.ok).toBe(false);
  expect(r.body.error).toBe(error);
  expect(typeof r.body.message).toBe("string");
}

/** The one Hub every request goes to. */
export const hub = () => env.HUB.get(env.HUB.idFromName("hub"));

/** Links a friends user to a made-up Apple account directly in storage, as POST /v1/auth/apple would. */
export async function linkAppleAccount(code: string, sub = `apple.${code}`): Promise<void> {
  await runInDurableObject(hub(), (_, state) => {
    state.storage.sql.exec("INSERT INTO apple_accounts (apple_sub, code, refresh_token, created_at) VALUES (?, ?, NULL, 0)", sub, code);
  });
}

/** The ADMIN_TOKEN binding in vitest.config.ts. */
export const ADMIN_TOKEN = "test-admin-secret";

/** A maintainer call to /v1/admin/..., from a fresh IP so the per-IP admin limit never leaks between tests. */
export const admin = (method: string, path: string, token = ADMIN_TOKEN) => call(method, "/v1/admin" + path, undefined, token, freshIp());
