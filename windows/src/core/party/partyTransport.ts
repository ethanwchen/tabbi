import type { Seconds } from "../time";
import { PartyError } from "./partyError";

/*
 * Port of PartyTransport: one request to the friends server, already
 * encoded, and its raw reply. The transport is injected: the app hands in
 * the host's `httpRequest` (through `hostPartyTransport`), tests a recorded
 * reply, and the end-to-end suite Node's fetch. Core never opens a socket.
 */

export type PartyMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

/** Port of PartyHTTPRequest. */
export interface PartyHttpRequest {
  readonly method: PartyMethod;
  /** The route, e.g. `/v1/friends`. */
  readonly path: string;
  /** The JSON body, when there is one. */
  readonly body?: string;
  /** The bearer token, when the route needs one. */
  readonly token?: string;
  /** Extra headers, such as the protocol and the `If-Match` revision a sync push needs. */
  readonly headers?: Readonly<Record<string, string>>;
}

/** Port of PartyHTTPResponse. */
export interface PartyHttpResponse {
  readonly status: number;
  readonly body: string;
  /** The `Retry-After` header in seconds, sent with `429`. */
  readonly retryAfter?: Seconds;
  /** The `ETag` header, sent with sync replies. */
  readonly etag?: string;
}

/**
 * Sends one request. Network failures reject with a `PartyError`
 * (`unreachable`, `timedOut`, `transport`); anything else that rejects is
 * wrapped as `transport` by the client.
 */
export type PartyTransport = (request: PartyHttpRequest, timeout: Seconds) => Promise<PartyHttpResponse>;

/* MARK: The host's HTTP, structurally (src/host/host.ts), so core needs no host import. */

export interface HostHttpRequestLike {
  readonly method: PartyMethod;
  readonly url: string;
  readonly headers?: readonly (readonly [name: string, value: string])[];
  readonly body?: string;
}

export interface HostHttpResponseLike {
  readonly status: number;
  /** Lowercase names. */
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
}

export type HostHttpRequestFunction = (request: HostHttpRequestLike) => Promise<HostHttpResponseLike>;

/** Joins a route onto the base URL, tolerating a trailing slash or a path prefix in the user's server setting. */
export function joinServerPath(base: string, path: string): string {
  let text = base;
  while (text.endsWith("/")) text = text.slice(0, -1);
  return text + path;
}

/** The headers a request goes out with, in a stable order. Port of URLSessionPartyTransport.send's header rules. */
export function requestHeaders(request: PartyHttpRequest): [string, string][] {
  const headers: [string, string][] = [["Accept", "application/json"]];
  if (request.body !== undefined) headers.push(["Content-Type", "application/json"]);
  for (const [name, value] of Object.entries(request.headers ?? {})) headers.push([name, value]);
  if (request.token !== undefined) headers.push(["Authorization", `Bearer ${request.token}`]);
  return headers;
}

/** `Retry-After` in seconds, or undefined when missing or not a number (an HTTP date is not used by the Worker). */
export function parseRetryAfter(value: string | undefined): Seconds | undefined {
  if (value === undefined || value.trim() === "") return undefined;
  const seconds = Number(value.trim());
  return Number.isFinite(seconds) ? seconds : undefined;
}

/** A thrown host error's stable code, if it is one (src/host/host.ts `HostError`). */
function hostErrorCode(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null || !("code" in error)) return undefined;
  const code = (error as { code: unknown }).code;
  return typeof code === "string" ? code : undefined;
}

/**
 * Maps a host or fetch failure to the states the Party tab explains: no
 * connection is `unreachable`, a timeout `timedOut`, anything else
 * `transport`. A cancelled request rethrows as it is. Port of
 * URLSessionPartyTransport.classify.
 */
export function classifyTransportError(error: unknown): unknown {
  if (error instanceof PartyError) return error;
  const code = hostErrorCode(error);
  if (code === "cancelled") return error;
  if (code === "network") return PartyError.of("unreachable");
  if (code === "timeout") return PartyError.of("timedOut");
  if (error instanceof Error && error.name === "AbortError") return error;
  if (error instanceof Error && error.name === "TimeoutError") return PartyError.of("timedOut");
  if (error instanceof TypeError) return PartyError.of("unreachable");
  if (code !== undefined) return PartyError.transport(code);
  return PartyError.transport(error instanceof Error ? error.name : "failed");
}

/**
 * The real transport: the host's allow-listed HTTP to `baseURL`. The host
 * holds no cookies or caches and applies its own connect and read
 * timeouts, so `timeout` is left to it.
 */
export function hostPartyTransport(baseURL: string, httpRequest: HostHttpRequestFunction): PartyTransport {
  return async (request) => {
    let response: HostHttpResponseLike;
    try {
      response = await httpRequest({
        method: request.method,
        url: joinServerPath(baseURL, request.path),
        headers: requestHeaders(request),
        ...(request.body === undefined ? {} : { body: request.body }),
      });
    } catch (error) {
      throw classifyTransportError(error);
    }
    const retryAfter = parseRetryAfter(response.headers["retry-after"]);
    const etag = response.headers.etag;
    return {
      status: response.status,
      body: response.body,
      ...(retryAfter === undefined ? {} : { retryAfter }),
      ...(etag === undefined ? {} : { etag }),
    };
  };
}
