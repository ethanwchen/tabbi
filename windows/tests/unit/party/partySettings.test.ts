import { describe, expect, it } from "vitest";
import { encodeSorted, profileBody } from "../../../src/core/party/partyClient";
import {
  InMemoryPartyCredentialStore,
  hostPartyCredentialStore,
  parseStoredIdentities,
  type HostCredentials,
} from "../../../src/core/party/partyCredentialStore";
import { PartyError } from "../../../src/core/party/partyError";
import { NO_REFUSAL, refusalMessage, refusalOf } from "../../../src/core/party/partyModeration";
import { PARTY_LOCAL_DEV_URL, PARTY_PRODUCTION_URL, partyDevServer, partyIdentityKey } from "../../../src/core/party/partyServer";
import {
  DEFAULT_PARTY_SETTINGS,
  PARTY_MAX_NAME_LENGTH,
  cleanedPartyName,
  decodePartySettings,
  encodePartySettings,
  partyProfileUpdate,
  partyServerIssue,
  partyServerURL,
  partySettings,
  refusedNames,
  usesDefaultServer,
} from "../../../src/core/party/partySettings";
import { PetProfile } from "../../../src/core/pets/petProfile";

describe("PartySettings", () => {
  it("uses the production server when the field is blank", () => {
    const settings = partySettings({ serverText: "  \n" });
    expect(usesDefaultServer(settings)).toBe(true);
    expect(partyServerURL(settings)).toBe(PARTY_PRODUCTION_URL);
    expect(partyServerIssue(settings)).toBeUndefined();
    expect(partyServerURL(DEFAULT_PARTY_SETTINGS)).toBe(PARTY_PRODUCTION_URL);
  });

  it("parses the user's own server and explains a bad one", () => {
    expect(partyServerURL(partySettings({ serverText: "friends.example.org/" }))).toBe("https://friends.example.org");
    expect(partyServerURL(partySettings({ serverText: "http://localhost:8787" }))).toBe(PARTY_LOCAL_DEV_URL);
    const plainHTTP = partySettings({ serverText: "http://friends.example.org" });
    expect(partyServerURL(plainHTTP)).toBeUndefined();
    expect(partyServerIssue(plainHTTP)).toBe("Use https:// (plain http:// only works for localhost).");
    const junk = partySettings({ serverText: "ftp://nope" });
    expect(partyServerURL(junk)).toBeUndefined();
    expect(partyServerIssue(junk)).toBeDefined();
  });

  it("takes TABBI_PARTY_SERVER only as a plain-http loopback address", () => {
    expect(partyDevServer("http://localhost:8787")).toBe("http://localhost:8787");
    expect(partyDevServer("http://127.0.0.1:8787/")).toBe("http://127.0.0.1:8787");
    expect(partyDevServer("http://[::1]:8787")).toBe("http://[::1]:8787");
    expect(partyDevServer("https://localhost:8787"), "https is a deployed server").toBeUndefined();
    expect(partyDevServer(PARTY_PRODUCTION_URL)).toBeUndefined();
    expect(partyDevServer("http://friends.example.org")).toBeUndefined();
    expect(partyDevServer("localhost:8787"), "no scheme means https").toBeUndefined();
    expect(partyDevServer(undefined)).toBeUndefined();
    expect(partyServerURL(DEFAULT_PARTY_SETTINGS, "http://localhost:8787"), "the override wins").toBe("http://localhost:8787");
    expect(partyServerURL(DEFAULT_PARTY_SETTINGS, PARTY_PRODUCTION_URL), "a refused override is ignored").toBe(PARTY_PRODUCTION_URL);
  });

  it("cleans the name as the server does", () => {
    expect(cleanedPartyName(partySettings({ name: "   " }))).toBeUndefined();
    expect(cleanedPartyName(partySettings({ name: "​‍" }))).toBeUndefined();
    expect(cleanedPartyName(partySettings({ name: "  An​a\n " }))).toBe("Ana");
    expect(cleanedPartyName(partySettings({ name: "x".repeat(40) }))?.length).toBe(PARTY_MAX_NAME_LENGTH);
  });

  it("carries only the name and the pet in the profile update", () => {
    const pet = new PetProfile("Mochi", "calico");
    const update = partyProfileUpdate(partySettings({ name: " Ana " }), pet);
    expect(update.name).toBe("Ana");
    expect(update.petName).toBe("Mochi");
    expect(update.points).toBeUndefined();
    const keys = Object.keys(JSON.parse(encodeSorted(profileBody(update))) as object);
    const allowed = new Set(["name", "petName", "species", "breed", "colors", "costume", "accessories"]);
    for (const key of keys) expect(allowed).toContain(key);
    expect(partyProfileUpdate(partySettings(), pet).name, "a blank name keeps the server's").toBeUndefined();
  });

  it("leaves out and reports names the filter rejects", () => {
    const fine = new PetProfile("Mochi", "calico");
    const rude = new PetProfile("Sh1t", "calico");
    const settings = partySettings({ name: "F u c k" });
    expect(refusedNames(settings, fine)).toEqual({ name: true, petName: false });
    expect(partyProfileUpdate(settings, fine).name).toBeUndefined();
    expect(partyProfileUpdate(settings, fine).petName).toBe("Mochi");
    const cassandra = partySettings({ name: "Cassandra" });
    expect(refusedNames(cassandra, rude)).toEqual({ name: false, petName: true });
    expect(partyProfileUpdate(cassandra, rude).name).toBe("Cassandra");
    expect(partyProfileUpdate(cassandra, rude).petName).toBeUndefined();
    expect(refusedNames(partySettings(), fine), "a blank name is never refused").toEqual(NO_REFUSAL);
  });

  it("says which name to change", () => {
    expect(refusalMessage(NO_REFUSAL)).toBeUndefined();
    expect(refusalMessage({ name: true, petName: false })).toBe("That name isn't allowed. Please pick another.");
    expect(refusalMessage({ name: false, petName: true })).toBe("Your pet's name isn't allowed. Rename your pet in the Closet.");
    expect(refusalMessage({ name: true, petName: true })).toBe("That name and your pet's name aren't allowed. Please pick others.");
    expect(refusalOf(PartyError.of("nameNotAllowed"))).toEqual({ name: true, petName: false });
    expect(refusalOf(PartyError.of("petNameNotAllowed"))).toEqual({ name: false, petName: true });
    expect(refusalOf(PartyError.of("banned"))).toBeUndefined();
  });

  it("round-trips its stored form and tolerates missing keys", () => {
    expect(decodePartySettings(undefined)).toEqual(DEFAULT_PARTY_SETTINGS);
    const saved = partySettings({ serverText: "http://localhost:8787", name: "Ana", invisible: true });
    expect(decodePartySettings(encodePartySettings(saved))).toEqual(saved);
    expect(JSON.parse(encodePartySettings(saved)).schemaVersion).toBe(1);
    expect(decodePartySettings('{"name":"Ben"}')).toEqual(partySettings({ name: "Ben" }));
    expect(decodePartySettings("not json")).toEqual(DEFAULT_PARTY_SETTINGS);
  });

  it("keys identities ignoring case and trailing slashes", () => {
    expect(partyIdentityKey("HTTPS://Friends.Example.org/")).toBe(partyIdentityKey("https://friends.example.org"));
    expect(partyIdentityKey(PARTY_LOCAL_DEV_URL)).not.toBe(partyIdentityKey("http://localhost:8788"));
  });

  it("keeps one identity per server in memory", async () => {
    const store = new InMemoryPartyCredentialStore();
    const local = { token: "a".repeat(64), code: "K7QW2MZD" };
    await store.save(local, PARTY_LOCAL_DEV_URL);
    expect(await store.load(PARTY_PRODUCTION_URL)).toBeUndefined();
    expect(await store.load("http://LOCALHOST:8787/")).toEqual(local);
    await store.delete(PARTY_LOCAL_DEV_URL);
    expect(await store.load(PARTY_LOCAL_DEV_URL)).toBeUndefined();
  });
});

/* A fake of the host's Credential Manager calls: one secret per name. */
class FakeCredentials implements HostCredentials {
  readonly secrets = new Map<string, string>();
  async credentialGet(name: "party"): Promise<string | null> {
    return this.secrets.get(name) ?? null;
  }
  async credentialSet(name: "party", secret: string): Promise<void> {
    this.secrets.set(name, secret);
  }
  async credentialDelete(name: "party"): Promise<boolean> {
    return this.secrets.delete(name);
  }
}

describe("hostPartyCredentialStore", () => {
  const first = { token: "1".repeat(64), code: "AAAAAAAA" };
  const second = { token: "2".repeat(64), code: "BBBBBBBB" };

  it("keeps one identity per server under the single party credential", async () => {
    const host = new FakeCredentials();
    const store = hostPartyCredentialStore(host);
    expect(await store.load(PARTY_PRODUCTION_URL)).toBeUndefined();
    await store.save(first, PARTY_PRODUCTION_URL);
    await store.save(second, "http://LOCALHOST:8787/");
    expect([...host.secrets.keys()]).toEqual(["party"]);
    expect(await store.load(PARTY_PRODUCTION_URL)).toEqual(first);
    expect(await store.load(PARTY_LOCAL_DEV_URL)).toEqual(second);

    await store.save(second, PARTY_PRODUCTION_URL);
    expect(await store.load(PARTY_PRODUCTION_URL), "a save replaces that server's identity").toEqual(second);

    await store.delete(PARTY_PRODUCTION_URL);
    expect(await store.load(PARTY_PRODUCTION_URL)).toBeUndefined();
    expect(await store.load(PARTY_LOCAL_DEV_URL)).toEqual(second);
    await store.delete(PARTY_LOCAL_DEV_URL);
    expect(host.secrets.size, "nothing left behind once every identity is gone").toBe(0);
    await store.delete(PARTY_LOCAL_DEV_URL);
  });

  it("reads an unreadable secret as no identities", async () => {
    const host = new FakeCredentials();
    host.secrets.set("party", "garbage");
    expect(await hostPartyCredentialStore(host).load(PARTY_PRODUCTION_URL)).toBeUndefined();
    expect(parseStoredIdentities('{"x":{"token":"short","code":"A"}}').size, "a malformed token is dropped").toBe(0);
  });

  it("keeps the secret small enough for Credential Manager", async () => {
    const host = new FakeCredentials();
    const store = hostPartyCredentialStore(host);
    for (let index = 0; index < 20; index += 1) await store.save(first, `https://server${index}.example.org`);
    expect(new TextEncoder().encode(host.secrets.get("party") ?? "").length).toBeLessThanOrEqual(2560);
    expect(await store.load("https://server19.example.org"), "the newest identity stays").toEqual(first);
  });
});
