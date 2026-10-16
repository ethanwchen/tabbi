/*
 * AnkiConnect over the host's HTTP: one POST per request to the add-on on
 * this PC, with no Origin header (the Rust host sends none, so AnkiConnect's
 * CORS list never matters). Host failures become the transport errors the
 * core client explains: a refused connection is Anki closed or the add-on
 * missing, a timeout is Anki busy. The host keeps its own long timeouts, so
 * the client's shorter ones are enforced here: a reply that comes after the
 * deadline is dropped.
 */

import { ANKI_CONNECT_ENDPOINT, type AnkiConnectTransport, type AnkiRequest, type AnkiTransportError } from "../../core/anki/ankiConnectClient";
import { isHostError, type Host } from "../../host/host";

function transportError(error: unknown): AnkiTransportError {
  if (isHostError(error)) {
    switch (error.code) {
      case "network":
        return { kind: "connectionRefused" };
      case "timeout":
        return { kind: "timedOut" };
      default:
        return { kind: "failed", message: error.message };
    }
  }
  return { kind: "failed", message: error instanceof Error ? error.message : String(error) };
}

/** The transport for `httpRequest`, the host's allow-listed HTTP. */
export function hostAnkiTransport(httpRequest: Host["httpRequest"]): AnkiConnectTransport {
  return (request: AnkiRequest) =>
    new Promise<unknown>((resolve, reject) => {
      let settled = false;
      const settle = (run: () => void) => {
        if (settled) return;
        settled = true;
        globalThis.clearTimeout(deadline);
        run();
      };
      const deadline = globalThis.setTimeout(() => settle(() => reject({ kind: "timedOut" } satisfies AnkiTransportError)), request.timeoutSeconds * 1000);
      request.signal?.addEventListener("abort", () => settle(() => reject(request.signal?.reason ?? new DOMException("The operation was aborted.", "AbortError"))), {
        once: true,
      });
      httpRequest({ method: "POST", url: ANKI_CONNECT_ENDPOINT, headers: [["Content-Type", "application/json"]], body: request.body }).then(
        (response) =>
          settle(() => {
            if (response.status < 200 || response.status >= 300) reject({ kind: "status", status: response.status } satisfies AnkiTransportError);
            else resolve(response.body);
          }),
        (error: unknown) => settle(() => reject(transportError(error))),
      );
    });
}
