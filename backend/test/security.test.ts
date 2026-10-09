import { SELF } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AUTH_FAILURES_PER_MIN, MAX_BODY_BYTES, REGISTER_PER_MIN, clientKey } from "../src/lib";
import { BASE, call, expectError, freshIp, pinClockToMinuteStart, register } from "./helpers";

const randomToken = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, "0")).join("");
const withIp = (ip: string) => new Request(BASE, { headers: { "CF-Connecting-IP": ip } });

describe("clientKey", () => {
  it("keeps IPv4 addresses as they are", () => {
    expect(clientKey(withIp("203.0.113.7"))).toBe("203.0.113.7");
  });

  it("counts an IPv6 address by its /64 prefix, however it is written", () => {
    const key = "2001:db8:1:2::/64";
    expect(clientKey(withIp("2001:db8:1:2::a"))).toBe(key);
    expect(clientKey(withIp("2001:0DB8:0001:0002:ffff:ffff:ffff:ffff"))).toBe(key);
    expect(clientKey(withIp("2001:db8:1:2:0:0:0:1"))).toBe(key);
    expect(clientKey(withIp("2001:db8:1:3::a"))).not.toBe(key);
    expect(clientKey(withIp("::1"))).toBe("0:0:0:0::/64");
  });

  it("reads IPv4-mapped IPv6 as the IPv4 address", () => {
    expect(clientKey(withIp("::ffff:203.0.113.7"))).toBe("203.0.113.7");
  });

  it("is unknown without an address", () => {
    expect(clientKey(new Request(BASE))).toBe("unknown");
  });
});

describe("authentication limits", () => {
  beforeEach(pinClockToMinuteStart);
  afterEach(() => vi.useRealTimers());

  it("limits guessing well-formed tokens per IP, not per token", async () => {
    const ip = freshIp();
    for (let i = 0; i < AUTH_FAILURES_PER_MIN; i++) {
      expectError(await call("GET", "/v1/me", undefined, randomToken(), ip), 401, "unauthorized");
    }
    const r = await call("GET", "/v1/me", undefined, randomToken(), ip);
    expectError(r, 429, "rate_limited");
    expect(r.headers.get("Retry-After")).toBe("60");
    // The limit is per IP: another client is unaffected.
    expectError(await call("GET", "/v1/me", undefined, randomToken(), freshIp()), 401, "unauthorized");
  });

  it("counts IPv6 guesses per /64, so rotating addresses does not help", async () => {
    for (let i = 0; i < AUTH_FAILURES_PER_MIN; i++) {
      expectError(await call("GET", "/v1/me", undefined, randomToken(), `2001:db8:aa:1::${i.toString(16)}`), 401, "unauthorized");
    }
    expectError(await call("GET", "/v1/me", undefined, randomToken(), "2001:db8:aa:1::ffff"), 429, "rate_limited");
    expectError(await call("GET", "/v1/me", undefined, randomToken(), "2001:db8:aa:2::1"), 401, "unauthorized");
  });

  it("keeps failed sign-ins and registrations in separate windows", async () => {
    const ip = freshIp();
    for (let i = 0; i < REGISTER_PER_MIN; i++) {
      expectError(await call("GET", "/v1/me", undefined, "bad", ip), 401, "unauthorized");
    }
    expect((await call("POST", "/v1/register", {}, undefined, ip)).status).toBe(201);
  });

  it("does not count requests with a valid token as failures", async () => {
    const ip = freshIp();
    const a = await register();
    for (let i = 0; i < AUTH_FAILURES_PER_MIN; i++) {
      expect((await call("GET", "/v1/me", undefined, a.token, ip)).status).toBe(200);
    }
    expectError(await call("GET", "/v1/me", undefined, randomToken(), ip), 401, "unauthorized");
  });
});

describe("request bodies", () => {
  it("rejects an oversized body sent without Content-Length", async () => {
    const a = await register();
    const chunk = new TextEncoder().encode(" ".repeat(1024));
    let sent = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        // Far more than the limit; the server must stop reading long before the end.
        if (sent++ < 1024) controller.enqueue(chunk);
        else controller.close();
      },
    });
    const res = await SELF.fetch(BASE + "/v1/me", {
      method: "PATCH",
      headers: { Authorization: `Bearer ${a.token}`, "Content-Type": "application/json", "CF-Connecting-IP": freshIp() },
      body,
      duplex: "half",
    } as RequestInit);
    expect(res.status).toBe(413);
    expect(await res.json()).toMatchObject({ ok: false, error: "body_too_large" });
    expect(sent).toBeLessThan(1024);
    expect(sent * chunk.byteLength).toBeGreaterThan(MAX_BODY_BYTES);
  });
});
