import { afterEach, describe, expect, it, vi } from "vitest";
import { ModuleContext } from "../../../src/app/context";
import { AnkiConnectClient } from "../../../src/core/anki/ankiConnectClient";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { AnkiModule } from "../../../src/modules/anki/ankiModule";
import { ANKI_FAVORITE_DOCUMENT, AnkiStore } from "../../../src/modules/anki/ankiStore";
import { hostAnkiTransport } from "../../../src/modules/anki/ankiTransport";
import { recorded, ScriptedAnkiTransport, statsJSON } from "../anki/fakeAnki";
import { testApp, type TestApp } from "../../support/runtime";

/* The Anki tab's store over the mock host: refreshes, the setup states, polling only while someone looks, the favorite deck and the shared goal. */

const NOW = 1_790_000_000;
let apps: TestApp[] = [];

afterEach(() => {
  vi.useRealTimers();
  for (const { app } of apps) app.dispose();
  apps = [];
});

/** An AnkiConnect that answers every action with two decks due. */
function answering(): ScriptedAnkiTransport {
  return new ScriptedAnkiTransport((request) => {
    switch (request.action) {
      case "requestPermission":
        return `{"result":{"permission":"granted","requireApiKey":false,"version":6},"error":null}`;
      case "deckNamesAndIds":
        return `{"result":{"Biology":2,"Spanish":3},"error":null}`;
      case "getDeckStats":
        return `{"result":{${statsJSON(2, "Biology", 12)},${statsJSON(3, "Spanish", 5)}},"error":null}`;
      case "getNumCardsReviewedToday":
        return `{"result":20,"error":null}`;
      case "getNumCardsReviewedByDay":
        return `{"result":[["2026-09-21",20],["2026-09-20",30]],"error":null}`;
      case "guiDeckReview":
        return `{"result":false,"error":null}`;
      case "multi":
        return `{"result":[{"result":[],"error":null},{"result":[],"error":null}],"error":null}`;
      default:
        return recorded.unsupportedAction;
    }
  });
}

/**
 * The app with only the Anki module. The polling test drives the closed
 * preview watch by hand, so no other module (whose items make the ticker
 * rewrite the watch) may run beside it.
 */
async function ankiApp(options: { transport?: ScriptedAnkiTransport; demo?: boolean } = {}): Promise<TestApp & { store: AnkiStore; context: ModuleContext }> {
  const made = await testApp({ moduleTypes: [AnkiModule], ...(options.demo ? { runMode: { isDemo: true, isSnapshot: false } } : {}) }, NOW);
  apps.push(made);
  const context = new ModuleContext("anki", made.app.environment);
  const client = options.transport === undefined ? undefined : new AnkiConnectClient({ transport: options.transport.transport });
  const store = new AnkiStore(context, client === undefined ? {} : { client });
  return { ...made, store, context };
}

const settle = async () => {
  for (let i = 0; i < 12; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

/** Lets a refresh's chain of awaited replies land under fake timers. */
const flush = async () => {
  for (let i = 0; i < 24; i++) await vi.advanceTimersByTimeAsync(0);
};

describe("AnkiStore", () => {
  it("reads the summary on start and shares today's reviews as a goal with a Study action", async () => {
    const transport = answering();
    const { store } = await ankiApp({ transport });
    store.start();
    await settle();
    expect(store.state.connection).toEqual({ kind: "ready" });
    expect(store.state.summary?.newDue).toBe(17);
    const goal = store.provision().progress[0];
    expect(goal?.completed).toBe(20);
    expect(goal?.target).toBe(37);
    expect(goal?.action?.title).toBe("Study Biology");
    store.stop();
  });

  it("reads a refused connection as Anki closed and keeps no stale numbers", async () => {
    const transport = new ScriptedAnkiTransport(() => {
      throw { kind: "connectionRefused" };
    });
    const { store } = await ankiApp({ transport });
    store.start();
    await settle();
    expect(store.state.connection).toEqual({ kind: "notRunning" });
    expect(store.state.summary).toBeUndefined();
    expect(store.provision().progress).toEqual([]);
    store.stop();
  });

  it("polls only while the panel shows or the closed island's progress preview can show", async () => {
    vi.useFakeTimers();
    const transport = answering();
    const { store, context } = await ankiApp({ transport });
    /* The island's ticker watches the progress preview by default; this test drives the watch by hand. */
    context.closedPreview.setWatched(new Set());
    store.start();
    await flush();
    const after = (count: number) => transport.requests.filter((request) => request.action === "deckNamesAndIds").length === count;
    expect(after(1)).toBe(true);
    /* Hidden and connected: nothing polls. */
    await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
    expect(after(1)).toBe(true);
    store.panelDidAppear();
    await flush();
    expect(after(2)).toBe(true);
    await vi.advanceTimersByTimeAsync(181 * 1000);
    await flush();
    expect(after(3)).toBe(true);
    store.panelDidDisappear();
    await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
    expect(after(3)).toBe(true);
    /* The ticker's progress preview counts as someone looking. */
    context.closedPreview.setWatched(new Set(["progress"]));
    await vi.advanceTimersByTimeAsync(181 * 1000);
    await flush();
    expect(after(4)).toBe(true);
    context.closedPreview.setWatched(new Set());
    store.stop();
  });

  it("saves the favorite deck in the Anki folder, follows it on refresh and opens it from the shared action", async () => {
    const transport = answering();
    const { store, host } = await ankiApp({ transport });
    store.start();
    await settle();
    const spanish = store.state.summary?.decks.find((deck) => deck.name === "Spanish");
    if (spanish === undefined) throw new Error("no Spanish deck");
    store.toggleFavorite(spanish);
    await settle();
    expect(host.documents.get(`durable:Anki/${ANKI_FAVORITE_DOCUMENT.replace(/\.json$/, "")}`)).toContain('"name":"Spanish"');
    expect(store.provision().progress[0]?.action?.title).toBe("Study Spanish");
    store.studyFromShared();
    await settle();
    const review = transport.requests.find((request) => request.action === "guiDeckReview");
    expect(review?.params).toEqual({ name: "Spanish" });
    /* Anki said the deck is gone: the panel says so for a moment. */
    expect(store.state.openNotice).toEqual({ kind: "deckNotFound", deck: "Spanish" });
    store.stop();
  });

  it("shows the sample summary in demo mode and never calls the host", async () => {
    const { store, host } = await ankiApp({ demo: true });
    store.start();
    store.panelDidAppear();
    await settle();
    expect(store.state.connection).toEqual({ kind: "ready" });
    expect(store.state.favorite?.name).toBe("Spanish verbs");
    expect(host.calls.filter((call) => call.name === "httpRequest")).toEqual([]);
    store.stop();
  });

  it("is listed with its setup step and shares its goal through the registry", async () => {
    const made = await testApp({ moduleTypes: MODULE_LIST, runMode: { isDemo: true, isSnapshot: false } }, NOW);
    apps.push(made);
    const module = made.app.modules.instance(AnkiModule);
    expect(module?.descriptor.setup.map((step) => step.id)).toEqual(["anki"]);
    expect(module?.provision?.get().progress[0]?.source).toBe("anki");
    expect(module?.setupView?.({ id: "anki", title: "", symbol: "", rank: 0 })).toBeDefined();
  });
});

describe("hostAnkiTransport", () => {
  it("posts the envelope to AnkiConnect and maps the host's failures", async () => {
    const sent: unknown[] = [];
    const transport = hostAnkiTransport((request) => {
      sent.push(request);
      return Promise.resolve({ status: 200, headers: {}, body: `{"result":6,"error":null}` });
    });
    const body = `{"action":"version","version":6}`;
    expect(await transport({ envelope: { action: "version", version: 6 }, body, timeoutSeconds: 3 })).toBe(body.replace(/.*/, `{"result":6,"error":null}`));
    expect(sent[0]).toMatchObject({ method: "POST", url: "http://127.0.0.1:8765", body });
    const refused = hostAnkiTransport(() => Promise.reject({ code: "network", message: "refused" }));
    await expect(refused({ envelope: { action: "version", version: 6 }, body, timeoutSeconds: 3 })).rejects.toEqual({ kind: "connectionRefused" });
    const slow = hostAnkiTransport(() => new Promise(() => {}));
    vi.useFakeTimers();
    const pending = expect(slow({ envelope: { action: "version", version: 6 }, body, timeoutSeconds: 1 })).rejects.toEqual({ kind: "timedOut" });
    await vi.advanceTimersByTimeAsync(1100);
    await pending;
  });
});
