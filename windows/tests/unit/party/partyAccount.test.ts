import { describe, expect, it } from "vitest";
import { PartyAccount } from "../../../src/core/party/partyAccount";
import { InMemoryPartyCredentialStore } from "../../../src/core/party/partyCredentialStore";
import { PartyError } from "../../../src/core/party/partyError";
import { partyPetUpdate } from "../../../src/core/party/partyPetAppearance";
import { PARTY_PRODUCTION_URL } from "../../../src/core/party/partyServer";
import type { PartyHttpRequest, PartyHttpResponse, PartyTransport } from "../../../src/core/party/partyTransport";
import { PetProfile } from "../../../src/core/pets/petProfile";

/* A tiny stand-in friends server: it knows which tokens are valid, hands out new ones on register, and records every request. */
class FakeFriendsServer {
  private readonly validTokens: Set<string>;
  private registrations = 0;
  readonly sent: PartyHttpRequest[] = [];
  registerDelay = 0;
  unreachable = false;
  banned = false;
  heldNames = new Set<string>();
  heldPetNames = new Set<string>();
  catalogVersion1 = false;
  readonly takenBodies: Record<string, unknown>[] = [];

  constructor(validTokens: string[] = []) {
    this.validTokens = new Set(validTokens);
  }

  static token(n: number): string {
    return String(n).padStart(64, "0");
  }

  static code(n: number): string {
    return `CODE000${n}`;
  }

  static profile(code: string, name = "Ana"): string {
    return `{"code":"${code}","name":"${name}","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}`;
  }

  get requests(): string[] {
    return this.sent.map((request) => `${request.method} ${request.path}`);
  }

  get registerCount(): number {
    return this.registrations;
  }

  revoke(token: string): void {
    this.validTokens.delete(token);
  }

  readonly send: PartyTransport = async (request) => {
    this.sent.push(request);
    if (this.unreachable) throw PartyError.of("unreachable");
    const route = `${request.method} ${request.path}`;
    const fields = request.body === undefined ? undefined : (JSON.parse(request.body) as Record<string, unknown>);
    if (typeof fields?.name === "string" && this.heldNames.has(fields.name)) return reply('{"ok":false,"error":"name_not_allowed","message":"no"}', 400);
    if (typeof fields?.petName === "string" && this.heldPetNames.has(fields.petName)) {
      return reply('{"ok":false,"error":"pet_name_not_allowed","message":"no"}', 400);
    }
    if (this.catalogVersion1 && fields !== undefined) {
      const known = new Set(["glasses", "sunglasses", "headphones", "bow", "scarf", "crown", "flower", "party-hat", "beanie", "halo"]);
      const accessories = Array.isArray(fields.accessories) ? (fields.accessories as string[]) : [];
      const colors = Array.isArray(fields.colors) ? fields.colors : [];
      if (!accessories.every((id) => known.has(id)) || colors.length > 6) {
        return reply('{"ok":false,"error":"invalid_field","message":"invalid accessories"}', 400);
      }
    }
    if (fields !== undefined) this.takenBodies.push(fields);
    if (route === "POST /v1/register") {
      if (this.registerDelay > 0) await new Promise((resolve) => setTimeout(resolve, this.registerDelay));
      this.registrations += 1;
      const n = this.registrations;
      this.validTokens.add(FakeFriendsServer.token(n));
      const name = typeof fields?.name === "string" ? fields.name : "Studier";
      return reply(
        `{"ok":true,"token":"${FakeFriendsServer.token(n)}","code":"${FakeFriendsServer.code(n)}","profile":${FakeFriendsServer.profile(FakeFriendsServer.code(n), name)}}`,
        201,
      );
    }
    const token = request.token;
    if (token === undefined || !this.validTokens.has(token)) return reply('{"ok":false,"error":"unauthorized","message":"no"}', 401);
    const code = FakeFriendsServer.code(Number(token));
    switch (route) {
      case "GET /v1/me":
      case "PATCH /v1/me": {
        const name = typeof fields?.name === "string" ? fields.name : "Ana";
        return reply(`{"ok":true,"profile":${FakeFriendsServer.profile(code, name)}${this.banned ? ',"banned":true' : ""}}`);
      }
      case "GET /v1/friends":
        return reply('{"ok":true,"friends":[]}');
      case "DELETE /v1/me":
        this.revoke(token);
        return reply('{"ok":true,"deleted":true}');
      default:
        return reply('{"ok":false,"error":"not_found","message":"no route"}', 404);
    }
  };
}

function reply(body: string, status = 200): PartyHttpResponse {
  return { status, body };
}

const server = "http://localhost:8787";

function account(fake: FakeFriendsServer, store = new InMemoryPartyCredentialStore(), at = server): PartyAccount {
  return new PartyAccount({ server: at, transport: fake.send, credentials: store });
}

async function rejection(body: () => Promise<unknown>): Promise<unknown> {
  try {
    await body();
  } catch (error) {
    return error;
  }
  throw new Error("expected a rejection");
}

describe("PartyAccount", () => {
  it("registers with the profile on first connect and stores the token", async () => {
    const fake = new FakeFriendsServer();
    const store = new InMemoryPartyCredentialStore();
    const party = account(fake, store);
    const profile = await party.connect({ name: "Ana" });
    expect(profile.name).toBe("Ana");
    expect(fake.requests).toEqual(["POST /v1/register"]);
    expect(await store.load(server)).toEqual({ token: FakeFriendsServer.token(1), code: FakeFriendsServer.code(1) });
    expect(await party.friendCode()).toBe(FakeFriendsServer.code(1));
  });

  it("reuses a stored identity and patches the profile", async () => {
    const token = FakeFriendsServer.token(7);
    const fake = new FakeFriendsServer([token]);
    const store = new InMemoryPartyCredentialStore({ [server]: { token, code: FakeFriendsServer.code(7) } });
    const profile = await account(fake, store).connect({ name: "Ben" });
    expect(profile.name).toBe("Ben");
    expect(profile.code).toBe(FakeFriendsServer.code(7));
    expect(fake.requests).toEqual(["PATCH /v1/me"]);
    expect(fake.registerCount).toBe(0);
  });

  it("throws banned when the server says so and keeps the identity", async () => {
    const token = FakeFriendsServer.token(7);
    const fake = new FakeFriendsServer([token]);
    fake.banned = true;
    const store = new InMemoryPartyCredentialStore({ [server]: { token, code: FakeFriendsServer.code(7) } });
    const error = await rejection(() => account(fake, store).connect({ name: "Ben" }));
    expect((error as PartyError).kind).toBe("banned");
    expect((await store.load(server))?.code).toBe(FakeFriendsServer.code(7));
    expect(fake.requests).toEqual(["PATCH /v1/me"]);
  });

  it("leaves a refused name out so the rest still syncs", async () => {
    const token = FakeFriendsServer.token(7);
    const fake = new FakeFriendsServer([token]);
    fake.heldNames = new Set(["Rude"]);
    fake.heldPetNames = new Set(["Worse"]);
    const store = new InMemoryPartyCredentialStore({ [server]: { token, code: FakeFriendsServer.code(7) } });
    const party = account(fake, store);
    const profile = await party.connect({ name: "Rude", petName: "Worse", breed: "tabby" });
    expect(profile.name, "the server keeps the name it has").toBe("Ana");
    expect(fake.requests).toEqual(["PATCH /v1/me", "PATCH /v1/me", "PATCH /v1/me"]);
    expect(party.refusedNames).toEqual({ name: true, petName: true });
    fake.heldNames = new Set();
    await party.connect({ name: "Ana" });
    expect(party.refusedNames, "a name the server takes clears the refusal").toEqual({ name: false, petName: false });
  });

  it("sends a catalog version 1 server the look it can carry", async () => {
    const token = FakeFriendsServer.token(7);
    const fake = new FakeFriendsServer([token]);
    fake.catalogVersion1 = true;
    const store = new InMemoryPartyCredentialStore({ [server]: { token, code: FakeFriendsServer.code(7) } });
    const pet = new PetProfile("Nova", "corgi", { outfit: "dinosaurHoodie", accessories: ["roundGlasses", "wizardHat"] });
    await account(fake, store).connect(partyPetUpdate(pet));
    expect(fake.requests, "refused once, then sent as catalog version 1 takes it").toEqual(["PATCH /v1/me", "PATCH /v1/me"]);
    const taken = fake.takenBodies[fake.takenBodies.length - 1];
    expect(taken?.accessories).toEqual(["glasses"]);
    expect(taken?.costume).toBe("hoodie");
    expect((taken?.colors as unknown[] | undefined)?.length).toBe(6);
  });

  it("still registers when the name is refused on register", async () => {
    const fake = new FakeFriendsServer();
    fake.heldNames = new Set(["Rude"]);
    const party = account(fake);
    const profile = await party.connect({ name: "Rude" });
    expect(profile.name).toBe("Studier");
    expect(fake.requests).toEqual(["POST /v1/register", "POST /v1/register"]);
    expect(fake.registerCount).toBe(1);
    expect(party.refusedNames).toEqual({ name: true, petName: false });
  });

  it("registers again with the last profile after a revoked token and retries once", async () => {
    const fake = new FakeFriendsServer();
    const store = new InMemoryPartyCredentialStore();
    const party = account(fake, store);
    await party.connect({ name: "Ana" });
    fake.revoke(FakeFriendsServer.token(1));
    const friends = await party.perform((client) => client.friends());
    expect(friends).toEqual([]);
    expect(fake.requests).toEqual(["POST /v1/register", "GET /v1/friends", "POST /v1/register", "GET /v1/friends"]);
    expect((await store.load(server))?.code).toBe(FakeFriendsServer.code(2));
    expect(party.profile?.name, "the new identity keeps the synced name").toBe("Ana");
  });

  it("shares one registration between concurrent calls", async () => {
    const fake = new FakeFriendsServer();
    fake.registerDelay = 20;
    const party = account(fake);
    await Promise.all([party.perform((client) => client.friends()), party.perform((client) => client.me())]);
    expect(fake.registerCount).toBe(1);
  });

  it("leaves no identity when the server is unreachable, and throws a transient error", async () => {
    const fake = new FakeFriendsServer();
    fake.unreachable = true;
    const store = new InMemoryPartyCredentialStore();
    const party = account(fake, store);
    const error = (await rejection(() => party.connect({ name: "Ana" }))) as PartyError;
    expect(error.kind).toBe("unreachable");
    expect(error.isTransient).toBe(true);
    expect(await store.load(server)).toBeUndefined();
    fake.unreachable = false;
    expect((await party.connect({ name: "Ana" })).code, "a later attempt registers normally").toBe(FakeFriendsServer.code(1));
  });

  it("forgets the token on delete so the next connect starts over", async () => {
    const fake = new FakeFriendsServer();
    const store = new InMemoryPartyCredentialStore();
    const party = account(fake, store);
    await party.connect({});
    await party.deleteAccount();
    expect(await store.load(server)).toBeUndefined();
    expect(await party.friendCode()).toBeUndefined();
    expect((await party.connect({})).code).toBe(FakeFriendsServer.code(2));
    expect(fake.requests).toEqual(["POST /v1/register", "DELETE /v1/me", "POST /v1/register"]);
  });

  it("keeps identities per server", async () => {
    const store = new InMemoryPartyCredentialStore();
    await account(new FakeFriendsServer(), store).connect({});
    expect(await account(new FakeFriendsServer(), store, PARTY_PRODUCTION_URL).friendCode()).toBeUndefined();
    expect(await store.load(server)).toBeDefined();
    expect(await store.load("HTTP://LOCALHOST:8787/"), "one identity per server, whatever the spelling").toBeDefined();
  });
});
