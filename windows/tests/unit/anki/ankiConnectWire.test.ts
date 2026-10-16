import { describe, expect, it } from "vitest";
import { type AnkiRequest, AnkiConnectClient, ANKI_TIMEOUTS } from "../../../src/core/anki/ankiConnectClient";

/*
 * Port of AnkiConnectWireTests. On Windows the Rust host owns the socket
 * (headers, Content-Length, no chunking, no Origin), so its own tests pin
 * those bytes; here we pin what the core hands the host: one JSON body that
 * AnkiConnect's parser reads, and the reply decoded from the body text the
 * host passes back.
 */

async function roundTrip(apiKey?: string): Promise<{ request: AnkiRequest; names: string[] }> {
  let captured: AnkiRequest | undefined;
  const client = new AnkiConnectClient({
    apiKey,
    transport: async (request) => {
      captured = request;
      return `{"result":{"Default":1,"Biology::Cells":5},"error":null}`;
    },
  });
  const decks = await client.decks();
  if (!captured) throw new Error("nothing was sent");
  return { request: captured, names: decks.map((deck) => deck.name) };
}

describe("AnkiConnect wire format", () => {
  it("hands the host one compact JSON body AnkiConnect reads", async () => {
    const { request, names } = await roundTrip();
    expect(request.body).toBe(`{"action":"deckNamesAndIds","version":6}`);
    expect(request.body).not.toContain("\n");
    expect(JSON.parse(request.body)).toEqual(request.envelope);
    expect(request.timeoutSeconds).toBe(ANKI_TIMEOUTS.request);
    expect(names).toEqual(["Biology::Cells", "Default"]);
  });

  it("writes params and the key after the action and version", async () => {
    const { request } = await roundTrip("k3y");
    expect(request.body).toBe(`{"action":"deckNamesAndIds","version":6,"key":"k3y"}`);
    let body = "";
    const client = new AnkiConnectClient({
      apiKey: "k3y",
      transport: async (sent) => {
        body = sent.body;
        return `{"result":{},"error":null}`;
      },
    });
    await client.deckStats([{ id: 5, name: "Biology::Cells" }]);
    expect(body).toBe(`{"action":"getDeckStats","version":6,"params":{"decks":["Biology::Cells"]},"key":"k3y"}`);
  });

  it("keeps non-ASCII deck names intact in the body", async () => {
    let body = "";
    const client = new AnkiConnectClient({
      transport: async (sent) => {
        body = sent.body;
        return `{"result":[],"error":null}`;
      },
    });
    await client.cardReviews("Japanisch::日本語 \"N5\"", 0);
    expect(JSON.parse(body)).toEqual({
      action: "cardReviews",
      version: 6,
      params: { deck: "Japanisch::日本語 \"N5\"", startID: 0 },
    });
  });
});
