import { describe, expect, it } from "vitest";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { stringifyJSON, type JSONObject } from "../../../src/core/persistence/json";

interface Note {
  title: string;
  minutes: number;
}

function readNote(document: JSONObject): Note {
  const { title, minutes } = document;
  if (typeof title !== "string" || typeof minutes !== "number") throw new TypeError("not a note");
  return { title, minutes };
}

describe("VersionedJSON", () => {
  it("stamps the current version next to the value's keys", () => {
    const text = new VersionedJSON(3).encode({ title: "Read", minutes: 25 });
    const json = JSON.parse(text) as JSONObject;
    expect(json.schemaVersion).toBe(3);
    expect(json.title).toBe("Read");
    expect(json.minutes).toBe(25);
    expect(VersionedJSON.version(text)).toBe(3);
  });

  it("reads a document without a version as version 0 and still decodes it", () => {
    const legacy = `{"title":"Read","minutes":25}`;
    expect(VersionedJSON.version(legacy)).toBe(0);
    expect(new VersionedJSON(1).decode(legacy, readNote)).toEqual({ title: "Read", minutes: 25 });
  });

  it("runs the steps newer than the document in order before decoding", () => {
    const schema = new VersionedJSON(3, [
      /* 1: "name" became "title". */
      {
        version: 1,
        migrate: (json) => {
          json.title = json.name ?? null;
          delete json.name;
        },
      },
      /* 3: "seconds" became "minutes". */
      {
        version: 3,
        migrate: (json) => {
          const seconds = typeof json.seconds === "number" ? json.seconds : 0;
          json.minutes = Math.trunc(seconds / 60);
          delete json.seconds;
        },
      },
    ]);
    expect(schema.decode(`{"name":"Read","seconds":1500}`, readNote)).toEqual({ title: "Read", minutes: 25 });
    /* A version 2 document only needs the last step; "name" must not be touched. */
    expect(schema.decode(`{"schemaVersion":2,"title":"Read","seconds":600}`, readNote)).toEqual({
      title: "Read",
      minutes: 10,
    });
    expect(schema.upgrade(`{"schemaVersion":2,"title":"Read","seconds":600}`).schemaVersion).toBe(3);
  });

  it("decodes a document from a newer build as it is and ignores unknown keys", () => {
    const schema = new VersionedJSON(1, [
      {
        version: 1,
        migrate: () => {
          throw new Error("A newer document must not be migrated");
        },
      },
    ]);
    const newer = `{"schemaVersion":7,"title":"Read","minutes":25,"color":"blue"}`;
    expect(schema.decode(newer, readNote)).toEqual({ title: "Read", minutes: 25 });
  });

  it("counts anything but an integer version, or a non-object, as version 0", () => {
    expect(VersionedJSON.version(`{"schemaVersion":"2"}`)).toBe(0);
    expect(VersionedJSON.version(`{"schemaVersion":2.5}`)).toBe(0);
    expect(VersionedJSON.version(`[1]`)).toBe(0);
    expect(VersionedJSON.version(`not json`)).toBe(0);
  });

  it("refuses a document that isn't an object", () => {
    expect(() => new VersionedJSON(1).upgrade("[]")).toThrow();
    expect(() => new VersionedJSON(1).upgrade("not json")).toThrow();
  });

  it("refuses steps out of order or past the current version", () => {
    const step = (version: number) => ({ version, migrate: () => undefined });
    expect(() => new VersionedJSON(3, [step(2), step(1)])).toThrow();
    expect(() => new VersionedJSON(1, [step(2)])).toThrow();
  });
});

describe("stringifyJSON", () => {
  it("writes like Foundation's pretty, sorted encoder", () => {
    expect(stringifyJSON({ b: [1, "a/b"], a: {}, c: undefined, d: [] }, { pretty: true, sortedKeys: true })).toBe(
      '{\n  "a" : {\n\n  },\n  "b" : [\n    1,\n    "a\\/b"\n  ],\n  "d" : [\n\n  ]\n}',
    );
    expect(stringifyJSON({ b: 1, a: true })).toBe('{"b":1,"a":true}');
    expect(JSON.parse(stringifyJSON({ path: "a/b" }))).toEqual({ path: "a/b" });
  });
});
