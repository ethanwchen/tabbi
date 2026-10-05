/**
 * Tabbi friends backend: a Cloudflare Worker in front of one SQLite-backed Durable Object (`Hub`).
 *
 * The Worker answers CORS preflights, the health check and the public catalog itself (no Durable
 * Object request is spent on those) and forwards every `/v1/*` call to the Hub, which owns all state.
 * Nothing about cards, decks or notes is ever accepted; bodies with unknown fields are rejected.
 */
import { CATALOG, SERVICE } from "./lib";
import { CORS, json } from "./http";
import type { Env } from "./hub";

// The entry module may only export handlers and Durable Object classes (workerd rejects other values).

export { Hub } from "./hub";
export type { Env } from "./hub";

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (path === "/" || path === "/v1") return json({ ok: true, service: SERVICE, version: 1 });
    if (path === "/v1/catalog" && req.method === "GET") return json({ ok: true, catalog: CATALOG });
    if (!path.startsWith("/v1/")) return json({ ok: false, error: "not_found", message: "not found" }, 404);
    try {
      return await env.HUB.get(env.HUB.idFromName("hub")).fetch(req);
    } catch (e) {
      console.error(e);
      return json({ ok: false, error: "unavailable", message: "service temporarily unavailable" }, 503);
    }
  },
} satisfies ExportedHandler<Env>;
