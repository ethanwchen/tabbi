import { runInDurableObject } from "cloudflare:test";
import { expect, vi } from "vitest";
import crewsCatalog from "../shared/crews.json";
import { weekStart } from "../src/crews";
import type { Hub } from "../src/hub";
import { BASE, call, hub, register } from "./helpers";
import { checkCrews } from "./schema";

export type User = { code: string; token: string; profile: Record<string, unknown> };

/** The first frame, emblem and color in the catalog (the defaults), whichever the owner keeps. */
export const FRAME = crewsCatalog.frames[0];
export const EMBLEM = crewsCatalog.emblems[0];
export const COLOR = Object.keys(crewsCatalog.colors)[0];

let names = 0;
/** A crew name no other test in the run uses. */
export const uniqueName = (prefix = "Crew") => `${prefix} ${++names}`;

/**
 * Moves the clock to a Monday 00:00 UTC far from the real now plus `offsetS`, a different week for each
 * `slot`, so a test's board never sees another test's crews. Returns that Monday.
 */
export function atWeek(slot: number, offsetS = 10 * 3600): number {
  vi.useFakeTimers({ toFake: ["Date"] });
  const monday = weekStart(Math.floor(Date.UTC(2031, 0, 1) / 1000)) + slot * 7 * 86_400;
  vi.setSystemTime((monday + offsetS) * 1000);
  return monday;
}

/** Moves the pinned clock forward. */
export function advance(seconds: number): void {
  vi.setSystemTime(Date.now() + seconds * 1000);
}

export const nowS = () => Math.floor(Date.now() / 1000);

/** A crew body with sensible defaults. */
export function crewBody(over: Record<string, unknown> = {}) {
  return { name: uniqueName(), description: "We study after dinner.", frame: FRAME, emblem: EMBLEM, color: COLOR, visibility: "public", ...over };
}

/** Creates a crew owned by a new (or the given) user and checks the reply against the schema. */
export async function makeCrew(over: Record<string, unknown> = {}, owner?: User) {
  const user = owner ?? await register({ name: "Owner" }) as User;
  const r = await call("POST", "/v1/crews", crewBody(over), user.token);
  expect(r.status, JSON.stringify(r.body)).toBe(201);
  expect(checkCrews("crewReply", r.body)).toEqual([]);
  return { owner: user, crew: r.body.crew };
}

/** Joins a crew by its invite code. */
export async function joinByCode(user: User, inviteCode: string) {
  const r = await call("POST", "/v1/crews/join", { code: inviteCode }, user.token);
  expect(r.status, JSON.stringify(r.body)).toBe(200);
  return r.body.crew;
}

/** Reports sessions and checks the reply against the schema. */
export async function report(user: User, sessions: { start: number; end: number; minutes: number }[]) {
  const r = await call("POST", "/v1/crews/sessions", { sessions }, user.token);
  expect(r.status, JSON.stringify(r.body)).toBe(200);
  expect(checkCrews("sessionsReply", r.body)).toEqual([]);
  return r.body as { results: { status: string; credited: number }[]; crewMinutes: number | null; myMinutes: number };
}

/** A session of `minutes` ending `endAgoS` seconds before now, its length the minutes exactly. */
export function session(minutes: number, endAgoS = 0) {
  const end = nowS() - endAgoS;
  return { start: end - minutes * 60, end, minutes };
}

export const rows = (sql: string, ...params: unknown[]) =>
  runInDurableObject(hub(), (_hub: Hub, state) => state.storage.sql.exec(sql, ...params).toArray());

/** A request with a raw Tabbi-Protocol header, as an app on that protocol sends it. */
export async function callWithHeader(protocol: string, method: string, path: string, body?: unknown, token?: string) {
  const { SELF } = await import("cloudflare:test");
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": "10.254.0.1", "Tabbi-Protocol": protocol };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await SELF.fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}
