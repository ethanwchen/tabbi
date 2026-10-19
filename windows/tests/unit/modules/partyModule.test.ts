import { afterEach, describe, expect, it } from "vitest";
import { ModuleContext } from "../../../src/app/context";
import { partyDevServer } from "../../../src/core/party/partyServer";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { PartyModule } from "../../../src/modules/party/partyModule";
import { PARTY_PRESENCE_FILE, PARTY_SETTINGS_FILE, PartyStore } from "../../../src/modules/party/partyStore";
import { partyCredentialStore, SyncService } from "../../../src/modules/party/syncService";
import { FakePartyTransport, Fixture, json } from "../party/partyFakes";
import { testApp, type TestApp } from "../../support/runtime";

/*
 * The Party module over the mock host: demo data for the tab, the ticker
 * and the pet, invite links as a takeover, the sign-in callback, and a live
 * store against recorded replies: register, heartbeat, friends only while
 * the panel shows, and the settings saved in the Party folder.
 */

const NOW = 1_790_000_000;
let apps: TestApp[] = [];

afterEach(() => {
  for (const { app } of apps) app.dispose();
  apps = [];
});

const settle = async () => {
  for (let i = 0; i < 16; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

const registration = `{"ok":true,"token":"${"ab".repeat(32)}","code":"K7QW2MZD","profile":${Fixture.ana}}`;

function fakeServer(): FakePartyTransport {
  return new FakePartyTransport({
    "POST /v1/register": json(registration),
    "PATCH /v1/me": json(`{"ok":true,"profile":${Fixture.ana},"banned":false}`),
    "POST /v1/presence": json(`{"ok":true,"presence":${Fixture.studying},"nextHeartbeat":120,"incomingRequests":1}`),
    "GET /v1/friends": json(`{"ok":true,"friends":[],"incoming":[],"outgoing":[]}`),
    "GET /v1/party": json(`{"ok":true,"party":null}`),
    "GET /v1/grants": json(`{"ok":true,"items":[]}`),
    "GET /v1/blocks": json(`{"ok":true,"blocks":[]}`),
  });
}

describe("PartyModule in demo mode", () => {
  it("shares the demo party's pets and shared session, the waiting request as the badge, and never calls the host", async () => {
    const made = await testApp({ moduleTypes: MODULE_LIST, runMode: { isDemo: true, isSnapshot: false } }, NOW);
    apps.push(made);
    const module = made.app.modules.instance(PartyModule);
    if (module === undefined) throw new Error("no Party module");
    const provision = module.provision?.get();
    expect(provision?.party?.pets.map((pet) => pet.name)).toEqual(["Sam", "Maya", "Priya"]);
    expect(provision?.party?.session?.hostName).toBeUndefined();
    expect(provision?.focus?.source).toBe("party");
    expect(provision?.badge).toBe(1);
    expect(made.host.calls.filter((call) => call.name === "httpRequest" || call.name === "credentialGet")).toEqual([]);
  });

  it("takes an invite link as a takeover and answers it with sample people", async () => {
    const made = await testApp({ moduleTypes: MODULE_LIST, runMode: { isDemo: true, isSnapshot: false } }, NOW);
    apps.push(made);
    const module = made.app.modules.instance(PartyModule);
    if (module === undefined) throw new Error("no Party module");
    expect(made.app.modules.openLink("https://example.com/add/K7QW2MZD")).toBeUndefined();
    expect(made.app.modules.openLink("tabbi://add/n4zr-7hvb")).toBe("party");
    expect(made.app.modules.takeover.get()).toBeDefined();
    /* The default kit leaves Party off: the invite first offers to turn it on, which the module does by adding the tab. */
    expect(module.store.state.invite?.flow.stage.kind).toBe("needsParty");
    made.app.settings.update((settings) => {
      const modules = settings.modules.clone();
      modules.add("party");
      return { ...settings, modules };
    });
    module.store.inviteTurnedPartyOn();
    expect(module.store.state.invite?.flow.stage.kind).toBe("confirming");
    module.store.confirmInvite();
    expect(module.store.state.invite?.flow.stage.kind).toBe("finished");
    module.store.dismissInvite();
    expect(made.app.modules.takeover.get()).toBeUndefined();
  });

  it("hands the sign-in callback to the account", async () => {
    const made = await testApp({ moduleTypes: MODULE_LIST, runMode: { isDemo: true, isSnapshot: false } }, NOW);
    apps.push(made);
    expect(made.app.modules.openLink(`tabbi://auth/apple?code=${"0".repeat(64)}`)).toBe("party");
    expect(made.app.modules.openLink("tabbi://auth/other")).toBeUndefined();
  });
});

describe("PartyStore against recorded replies", () => {
  async function liveStore(transport: FakePartyTransport): Promise<TestApp & { store: PartyStore }> {
    const made = await testApp({ moduleTypes: MODULE_LIST }, NOW);
    apps.push(made);
    const context = new ModuleContext("party", made.app.environment);
    const store = new PartyStore(context, { transport: transport.send, credentials: partyCredentialStore(context) });
    store.follow();
    return { ...made, store };
  }

  it("asks the age check first, then registers, sends the launch heartbeat and counts waiting requests", async () => {
    const transport = fakeServer();
    const { store, host } = await liveStore(transport);
    store.start();
    await settle();
    expect(store.state.party.connection).toEqual({ kind: "ageCheck", tooYoungUntil: undefined });
    expect(transport.requests).toEqual([]);
    store.answerAge(1, 1990);
    await settle();
    expect(store.state.party.connection).toEqual({ kind: "connected" });
    expect(store.state.party.friendCode).toBe("K7QW2MZD");
    expect(transport.requests.map((request) => `${request.method} ${request.path}`)).toEqual(["POST /v1/register", "POST /v1/presence", "GET /v1/grants"]);
    expect(transport.requests[1]?.body).toContain('"status":"idle"');
    expect(store.state.party.waitingRequestCount).toBe(1);
    expect(host.credentials.get("party")).toContain("K7QW2MZD");
    expect(host.documents.get(`durable:Party/${PARTY_SETTINGS_FILE.replace(/\.json$/, "")}`)).toContain('"ageEligibleFrom"');
    expect(host.documents.get(`durable:Party/${PARTY_PRESENCE_FILE.replace(/\.json$/, "")}`)).toContain('"status":"idle"');
    /* Nothing is fetched while the panel is hidden. */
    expect(transport.requests.some((request) => request.path === "/v1/friends")).toBe(false);
    store.setVisible(true);
    await settle();
    expect(transport.requests.filter((request) => request.path === "/v1/friends")).toHaveLength(1);
    expect(transport.requests.filter((request) => request.path === "/v1/party")).toHaveLength(1);
    expect(store.state.party.friendsLoaded).toBe(true);
    store.setVisible(false);
    store.stop();
    await settle();
    expect(transport.last?.body).toBe('{"status":"offline"}');
  });

  it("never sends a birth date: only the eligible-from day is kept, on this PC", async () => {
    const transport = fakeServer();
    const { store, host } = await liveStore(transport);
    store.start();
    store.answerAge(6, 2005);
    await settle();
    for (const request of transport.requests) {
      expect(request.body ?? "").not.toMatch(/2005|birth|age/i);
    }
    const settings = host.documents.get(`durable:Party/${PARTY_SETTINGS_FILE.replace(/\.json$/, "")}`) ?? "";
    expect(settings).not.toContain("2005");
    expect(settings).toContain('"ageEligibleFrom"');
    store.stop();
  });

  it("hands a custom server to the host and a blank one clears it", async () => {
    const transport = fakeServer();
    const { store, host } = await liveStore(transport);
    store.start();
    store.answerAge(1, 1990);
    await settle();
    store.update({ ...store.state.settings, serverText: "https://friends.example.com" });
    await settle();
    expect(host.calls.filter((call) => call.name === "setPartyServer").at(-1)?.args).toEqual(["https://friends.example.com"]);
    store.update({ ...store.state.settings, serverText: "" });
    await settle();
    expect(host.calls.filter((call) => call.name === "setPartyServer").at(-1)?.args).toEqual([null]);
    expect(partyDevServer("https://friends.example.com")).toBeUndefined();
    store.stop();
  });
});

describe("SyncService", () => {
  /* Signing in never asks for a birthday (App Review guideline 5.1.1(v)); only an under-13 answer given in Party keeps it off. */
  async function webService(ageEligibleFrom: number | undefined) {
    const made = await testApp({ moduleTypes: MODULE_LIST }, NOW);
    apps.push(made);
    const context = new ModuleContext("party", made.app.environment);
    const service = new SyncService(context, {
      server: () => "https://tabbi-friends.example",
      credentials: partyCredentialStore(context),
      ageAnswer: { load: () => ageEligibleFrom },
      transport: () => new FakePartyTransport({}).send,
    });
    service.start();
    await settle();
    return { made, service };
  }

  it("opens Apple's page with no age answer at all", async () => {
    const { made, service } = await webService(undefined);
    expect(service.state.ageStatus).toEqual({ kind: "unanswered" });
    await service.signInOnWeb();
    expect(service.state.phase).toBe("signingIn");
    expect(made.host.calls.some((call) => call.name === "openUrl")).toBe(true);
    service.cancelSignIn();
    service.stop();
  });

  it("keeps signing in off after an under-13 answer in Party", async () => {
    const { made, service } = await webService(NOW + 365 * 24 * 60 * 60);
    expect(service.state.ageStatus.kind).toBe("tooYoung");
    await service.signInOnWeb();
    expect(service.state.phase).toBe("signedOut");
    expect(made.host.calls.some((call) => call.name === "openUrl")).toBe(false);
    service.stop();
  });

  it("opens Apple's page in the browser and trades the callback's code for the account", async () => {
    const made = await testApp({ moduleTypes: MODULE_LIST }, NOW);
    apps.push(made);
    const context = new ModuleContext("party", made.app.environment);
    const transport = new FakePartyTransport({
      "POST /v1/auth/apple/web/token": json(`{"ok":true,"token":"${"cd".repeat(32)}","code":"K7QW2MZD","profile":${Fixture.ana},"newAccount":false}`),
      "GET /v1/sync": json(`{"ok":true,"revision":0,"document":null}`),
      "PUT /v1/sync": json(`{"ok":true,"revision":1}`),
    });
    const credentials = partyCredentialStore(context);
    const identities: number[] = [];
    const service = new SyncService(context, {
      server: () => "https://tabbi-friends.example",
      credentials,
      ageAnswer: { load: () => Number.NEGATIVE_INFINITY },
      transport: () => transport.send,
    });
    service.identityChanged.on(() => identities.push(1));
    service.start();
    await settle();
    expect(service.state.phase).toBe("signedOut");
    await service.signInOnWeb();
    expect(service.state.phase).toBe("signingIn");
    const opened = made.host.calls.find((call) => call.name === "openUrl")?.args[0];
    expect(String(opened)).toMatch(/^https:\/\/appleid\.apple\.com\/auth\/authorize\?response_type=code%20id_token/);
    expect(String(opened)).toContain("redirect_uri=https://tabbi-friends.example/v1/auth/apple/web/callback");
    expect(service.receiveCallback("tabbi://auth/apple?error=cancelled")).toBe(true);
    expect(service.state.phase).toBe("signedOut");
    expect(service.state.notice).toBeUndefined();
    await service.signInOnWeb();
    expect(service.receiveCallback(`tabbi://auth/apple?code=${"0".repeat(64)}`)).toBe(true);
    await settle();
    expect(service.state.phase).toBe("signedIn");
    expect(identities).toHaveLength(1);
    expect((await credentials.load("https://tabbi-friends.example"))?.code).toBe("K7QW2MZD");
    const exchange = transport.requests.find((request) => request.path === "/v1/auth/apple/web/token");
    expect(JSON.parse(exchange?.body ?? "{}")).toMatchObject({ code: "0".repeat(64) });
    expect(made.host.documents.get("durable:Sync/state")).toContain('"account":"K7QW2MZD"');
    /* The launch round ran: a pull, then a push of this device's look. */
    expect(transport.requests.map((request) => `${request.method} ${request.path}`).slice(-2)).toEqual(["GET /v1/sync", "PUT /v1/sync"]);
    service.signOut();
    await settle();
    expect(service.state.phase).toBe("signedOut");
    expect(identities).toHaveLength(2);
    service.stop();
  });
});
