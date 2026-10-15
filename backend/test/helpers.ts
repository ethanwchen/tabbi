import { SELF, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { expect, vi } from "vitest";
import { PROTOCOL_HEADER, PROTOCOL_VERSION } from "../src/lib";

export const BASE = "https://tabbi.test";

let ipCounter = 0;
/** A fresh fake client IP, so per-IP registration limits never leak between tests. */
export const freshIp = () => `10.0.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`;

/**
 * Freezes the clock at the start of a minute until `vi.useRealTimers()`. Rate limits count in fixed
 * one-minute windows, so a test that fills a window on the real clock fails whenever it runs across a
 * minute boundary (which a slow, loaded machine makes likely). Pinned, the whole test is one window.
 * Tests that move the clock forward pin it first too, so real time passing between a request and the
 * jump (a second ticking over under load) cannot add to the interval they test.
 */
export function pinClockToMinuteStart(): number {
  vi.useFakeTimers({ toFake: ["Date"] });
  const minuteStart = (Math.floor(Date.now() / 60_000) + 1) * 60_000;
  vi.setSystemTime(minuteStart);
  return minuteStart / 1000;
}

export interface Reply {
  status: number;
  headers: Headers;
  body: any; // eslint-disable-line @typescript-eslint/no-explicit-any
}

/**
 * A request as the current app sends it, with its Party protocol (PROTOCOL_VERSION). `oldCall` is one from
 * an app up to 1.0.0, which sends no protocol header.
 */
export async function call(method: string, path: string, body?: unknown, token?: string, ip = "10.255.0.1"): Promise<Reply> {
  return callWithProtocol(PROTOCOL_VERSION, method, path, body, token, ip);
}

/** A request from an app up to 1.0.0: no protocol header, so protocol 1 and no friend requests. */
export async function oldCall(method: string, path: string, body?: unknown, token?: string, ip = "10.255.0.2"): Promise<Reply> {
  return callWithProtocol(null, method, path, body, token, ip);
}

async function callWithProtocol(
  protocol: number | null, method: string, path: string, body?: unknown, token?: string, ip = "10.255.0.1",
): Promise<Reply> {
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": ip };
  if (protocol !== null) headers[PROTOCOL_HEADER] = String(protocol);
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await SELF.fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, headers: res.headers, body: text ? JSON.parse(text) : null };
}

/** Registers a user from the current app, or from an app up to 1.0.0 with `old`. */
export async function register(profile: Record<string, unknown> = {}, old = false) {
  const r = await (old ? oldCall : call)("POST", "/v1/register", profile, undefined, freshIp());
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

/** The ADMIN_TOKEN binding in vitest.config.ts, random for each run. */
export const ADMIN_TOKEN = env.ADMIN_TOKEN as string;

/** A maintainer call to /v1/admin/..., from a fresh IP so the per-IP authentication failure limit never leaks between tests. */
export const admin = (method: string, path: string, token = ADMIN_TOKEN) => call(method, "/v1/admin" + path, undefined, token, freshIp());

/** Makes two users friends the way the app does: `a` sends a friend request and `b` accepts it. */
export async function befriend(a: { code: string; token: string }, b: { code: string; token: string }): Promise<void> {
  const asked = await call("POST", "/v1/friends", { code: b.code }, a.token);
  expect(asked.status).toBe(200);
  if (asked.body.status === "friends") return;
  const accepted = await call("POST", `/v1/friends/${a.code}/accept`, undefined, b.token);
  expect(accepted.status).toBe(200);
}
