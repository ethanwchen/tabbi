import { describe, expect, it } from "vitest";
import { PartyClient } from "../../../src/core/party/partyClient";
import { PartyError } from "../../../src/core/party/partyError";
import { PARTY_PRODUCTION_URL } from "../../../src/core/party/partyServer";
import {
  hostPartyTransport,
  parseRetryAfter,
  type HostHttpRequestFunction,
  type HostHttpRequestLike,
  type HostHttpResponseLike,
} from "../../../src/core/party/partyTransport";
import type { Host } from "../../../src/host/host";
import { TOKEN, expectPartyError } from "./partyFakes";

/* The real transport over the host's allow-listed HTTP (Port of URLSessionPartyTransportTests), with a fake host. */

function fakeHost(answer: (request: HostHttpRequestLike) => HostHttpResponseLike | Promise<HostHttpResponseLike>) {
  const sent: HostHttpRequestLike[] = [];
  const httpRequest: HostHttpRequestFunction = async (request) => {
    sent.push(request);
    return answer(request);
  };
  return { sent, httpRequest };
}

const hostError = (code: string) => ({ code, message: "for logs" });

describe("hostPartyTransport", () => {
  it("takes the host's httpRequest as it is", () => {
    const fromHost: Host["httpRequest"] = async () => ({ status: 200, headers: {}, body: "" });
    expect(typeof hostPartyTransport(PARTY_PRODUCTION_URL, fromHost)).toBe("function");
  });

  it("sends the method, route, headers, token and body", async () => {
    const host = fakeHost(() => ({ status: 201, headers: { "content-type": "application/json" }, body: '{"ok":true}' }));
    const transport = hostPartyTransport("http://localhost:8787/", host.httpRequest);
    const response = await transport(
      { method: "POST", path: "/v1/friends", body: '{"code":"B3NX9QRT"}', token: TOKEN, headers: { "Tabbi-Protocol": "2" } },
      10,
    );
    expect(response).toEqual({ status: 201, body: '{"ok":true}' });
    expect(host.sent).toEqual([
      {
        method: "POST",
        url: "http://localhost:8787/v1/friends",
        headers: [
          ["Accept", "application/json"],
          ["Content-Type", "application/json"],
          ["Tabbi-Protocol", "2"],
          ["Authorization", `Bearer ${TOKEN}`],
        ],
        body: '{"code":"B3NX9QRT"}',
      },
    ]);
  });

  it("sends neither Content-Type nor Authorization without a body or token", async () => {
    const host = fakeHost(() => ({ status: 200, headers: {}, body: '{"ok":true}' }));
    await hostPartyTransport(PARTY_PRODUCTION_URL, host.httpRequest)({ method: "GET", path: "/" }, 10);
    const request = host.sent[0];
    expect(request?.url).toBe(`${PARTY_PRODUCTION_URL}/`);
    expect(request?.headers).toEqual([["Accept", "application/json"]]);
    expect(request?.body).toBeUndefined();
  });

  it("returns an error status with its body, Retry-After and ETag", async () => {
    const host = fakeHost(() => ({ status: 429, headers: { "retry-after": "17", etag: '"4"' }, body: '{"ok":false,"error":"rate_limited"}' }));
    const response = await hostPartyTransport(PARTY_PRODUCTION_URL, host.httpRequest)({ method: "GET", path: "/v1/me" }, 10);
    expect(response).toEqual({ status: 429, body: '{"ok":false,"error":"rate_limited"}', retryAfter: 17, etag: '"4"' });
  });

  it("drops an unparsable Retry-After", async () => {
    const host = fakeHost(() => ({ status: 429, headers: { "retry-after": "soon" }, body: "{}" }));
    const response = await hostPartyTransport(PARTY_PRODUCTION_URL, host.httpRequest)({ method: "GET", path: "/v1/me" }, 10);
    expect(response.retryAfter).toBeUndefined();
    expect(parseRetryAfter(" 30 ")).toBe(30);
    expect(parseRetryAfter("")).toBeUndefined();
  });

  it("maps the host's network failures to Party errors", async () => {
    for (const [code, expected] of [
      ["network", PartyError.of("unreachable")],
      ["timeout", PartyError.of("timedOut")],
      ["blocked", PartyError.transport("blocked")],
    ] as const) {
      const host = fakeHost(() => {
        throw hostError(code);
      });
      await expectPartyError(() => hostPartyTransport(PARTY_PRODUCTION_URL, host.httpRequest)({ method: "GET", path: "/v1/me" }, 10), expected);
    }
  });

  it("rethrows a cancelled request as it is", async () => {
    const cancelled = hostError("cancelled");
    const host = fakeHost(() => {
      throw cancelled;
    });
    const transport = hostPartyTransport(PARTY_PRODUCTION_URL, host.httpRequest);
    await expect(transport({ method: "GET", path: "/v1/me" }, 10)).rejects.toBe(cancelled);
    await expect(new PartyClient(transport, TOKEN).me(), "the client does not wrap a cancellation").rejects.toBe(cancelled);
  });

  it("lets the client see unreachable when the server cannot be found", async () => {
    const host = fakeHost(() => {
      throw hostError("network");
    });
    await expectPartyError(() => new PartyClient(hostPartyTransport(PARTY_PRODUCTION_URL, host.httpRequest), TOKEN).friends(), PartyError.of("unreachable"));
  });
});
