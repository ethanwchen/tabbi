import { SELF } from "cloudflare:test";
import { expect } from "vitest";

export const BASE = "https://studynotch.test";

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
