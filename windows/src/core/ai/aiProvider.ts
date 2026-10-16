import { type AIProviderID, isCommandLineTool } from "./aiProviderID";
import { AIProviderFailure, type AIRequest, type AIStreamEvent } from "./aiRequest";
import { AIStreamParser } from "./aiStream";
import { type AIHTTPRequest, errorFromResponse, httpRequest } from "./aiWireFormat";

/**
 * Port of AIProvider: something that answers an `AIRequest` with a stream of
 * events. The app picks one from the user's choice; tests pass a mock.
 * Aborting `signal` stops the request.
 */
export interface AIProvider {
  readonly id: AIProviderID;
  stream(request: AIRequest, signal?: AbortSignal): AsyncIterable<AIStreamEvent>;
}

function isTimeout(reason: unknown): boolean {
  return typeof reason === "object" && reason !== null && (reason as { name?: unknown }).name === "TimeoutError";
}

/**
 * The whole answer to `request`, for features that use the result rather
 * than show it as it arrives (Plan my day, Day review, Refine). Throws the
 * provider's error; a `signal` that times out (`AbortSignal.timeout`) throws
 * `unreachable` with "timed out", as the Mac's 60 second limit does.
 */
export async function answer(provider: AIProvider, request: AIRequest, signal?: AbortSignal): Promise<string> {
  const aborted = () =>
    signal && isTimeout(signal.reason) ? new AIProviderFailure({ kind: "unreachable", detail: "timed out" }) : signal?.reason;
  if (signal?.aborted) throw aborted();
  /* Races every step with the signal, so a provider that never answers still ends on time. */
  let onAbort: (() => void) | undefined;
  const abort = new Promise<never>((_, reject) => {
    onAbort = () => reject(aborted());
    signal?.addEventListener("abort", onAbort, { once: true });
  });
  abort.catch(() => undefined);
  const iterator = provider.stream(request, signal)[Symbol.asyncIterator]();
  let deltas = "";
  let final: string | undefined;
  try {
    for (;;) {
      const step = await Promise.race([iterator.next(), abort]);
      if (step.done) break;
      const event = step.value;
      if (event.kind === "textDelta") deltas += event.text;
      else if (event.kind === "finished") final = event.text ?? final;
    }
  } catch (error) {
    if (signal?.aborted) {
      iterator.return?.().catch(() => undefined);
      throw aborted();
    }
    throw error;
  } finally {
    if (onAbort) signal?.removeEventListener("abort", onAbort);
  }
  return final ?? deltas;
}

/** A streamed HTTP response: its status and its body as text chunks. */
export interface AIHTTPResponse {
  status: number;
  chunks: AsyncIterable<string>;
}

/**
 * Sends one request and resolves once the response headers are in. Rejects
 * when nothing answered (refused, DNS, TLS), which becomes `unreachable`.
 * Injected: the host makes the call, tests replay recorded responses.
 */
export type AIHTTPTransport = (request: AIHTTPRequest, signal?: AbortSignal) => Promise<AIHTTPResponse>;

/**
 * Port of AIHTTPProvider: the hosted APIs and Ollama, one wire-format
 * request with its streamed body decoded into events. Exactly one
 * `finished` ends every successful stream, whatever end marker the
 * provider sends.
 */
export class AIHTTPProvider implements AIProvider {
  constructor(
    readonly id: AIProviderID,
    private readonly apiKey: string | undefined,
    private readonly transport: AIHTTPTransport,
    private readonly baseURL?: string,
  ) {
    if (isCommandLineTool(id)) throw new Error(`${id} is a command line tool`);
  }

  async *stream(request: AIRequest, signal?: AbortSignal): AsyncGenerator<AIStreamEvent> {
    const wire = httpRequest(this.id, request, this.apiKey, this.baseURL);
    let response: AIHTTPResponse;
    try {
      response = await this.transport(wire, signal);
    } catch (error) {
      throw providerError(error, signal);
    }
    if (response.status < 200 || response.status >= 300) {
      let body = "";
      try {
        for await (const chunk of response.chunks) body += chunk;
      } catch (error) {
        throw providerError(error, signal);
      }
      throw new AIProviderFailure(errorFromResponse(response.status, body));
    }
    const parser = new AIStreamParser(this.id);
    try {
      for await (const chunk of response.chunks) {
        for (const event of parser.push(chunk)) if (event.kind !== "finished") yield event;
      }
    } catch (error) {
      throw providerError(error, signal);
    }
    for (const event of parser.finish()) if (event.kind !== "finished") yield event;
    yield { kind: "finished" };
  }
}

/** Turns a connection failure into the error the panel explains; a cancelled call keeps its abort reason. */
function providerError(error: unknown, signal: AbortSignal | undefined): unknown {
  if (error instanceof AIProviderFailure) return error;
  if (signal?.aborted) return signal.reason;
  const detail = error instanceof Error ? error.message : typeof error === "string" ? error : undefined;
  return new AIProviderFailure(detail === undefined ? { kind: "unreachable" } : { kind: "unreachable", detail });
}
