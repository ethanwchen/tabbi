import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import { ActivityLogRepository } from "../../src/core/activity/activityLogRepository";
import {
  ACTIVITY_KINDS,
  ACTIVITY_METADATA,
  ACTIVITY_UNITS,
  activityDay,
  makeActivityRecord,
  type ActivityRecord,
  type ActivityRecordInput,
} from "../../src/core/activity/activityRecord";
import { InMemoryDocumentStore } from "../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../src/core/persistence/versionedJson";
import { goldenDiff } from "../support/goldenCompare";
import { loadFixture, loadRepoJson } from "../support/fixtures";

/*
 * Replays shared/fixtures/activity-log (written by ActivityLogGoldenTests on
 * the Mac): records as ActivityRecord's initializer makes them, the local day
 * an instant lands in across eight zones and clock changes, appends into day
 * files (exact text, parsed document, saved days and what reads back), and
 * how odd day files read. Every day file this port writes is validated
 * against shared/schemas/activity-record.v1.schema.json.
 */

type RecordJSON = Omit<ActivityRecordInput, "end"> & { id: string; end?: number };

interface FileJSON {
  name: string;
  contents: string;
  document?: unknown;
}

interface ActivityLogFixture {
  schema: string;
  version: number;
  constants: {
    folderName: string;
    versionKey: string;
    schemaVersion: number;
    migrations: number[];
    kinds: Record<string, string>;
    units: Record<string, string>;
    metadataKeys: Record<string, string>;
  };
  records: { name: string; input: RecordJSON; record: RecordJSON }[];
  days: { records: RecordJSON[]; zones: { timeZone: string; days: string[] }[] };
  appends: {
    name: string;
    input: { timeZone: string; seed: FileJSON[]; batches: RecordJSON[][] };
    output: { threw: boolean[]; files: FileJSON[]; savedDays: string[]; readBack: RecordJSON[] };
  }[];
  reads: { name: string; contents: string; records?: RecordJSON[] }[];
}

const fixture = loadFixture<ActivityLogFixture>("activity-log/activity-log.json");
const validateDayFile = new Ajv2020({ allErrors: true, strict: false }).compile(
  loadRepoJson("shared/schemas/activity-record.v1.schema.json"),
);

const folder = ActivityLogRepository.folderName;

function make(input: RecordJSON): ActivityRecord {
  return makeActivityRecord(input);
}

function expectGolden(actual: unknown, expected: unknown, label: string): void {
  const difference = goldenDiff(actual, expected);
  expect(difference, `${label}: ${difference ?? ""}`).toBeUndefined();
}

describe("activity-log fixture", () => {
  it("is the version this suite reads", () => {
    expect(fixture.schema).toBe("tabbi.activity-log.golden");
    expect(fixture.version).toBe(1);
  });

  it("has the Mac's constants", () => {
    const { constants } = fixture;
    expect(ActivityLogRepository.folderName).toBe(constants.folderName);
    expect(VersionedJSON.versionKey).toBe(constants.versionKey);
    expect(ActivityLogRepository.schema.current).toBe(constants.schemaVersion);
    expect(ActivityLogRepository.schema.migrations.map((step) => step.version)).toEqual(constants.migrations);
    expect({ ...ACTIVITY_KINDS }).toEqual(constants.kinds);
    expect({ ...ACTIVITY_UNITS }).toEqual(constants.units);
    expect({ ...ACTIVITY_METADATA }).toEqual(constants.metadataKeys);
  });

  it.each(fixture.records.map((entry) => [entry.name, entry] as const))("makes the record %s", (_name, entry) => {
    expectGolden(make(entry.input), entry.record, entry.name);
  });

  it.each(fixture.days.zones.map((zone) => [zone.timeZone, zone] as const))(
    "puts each instant on its local day in %s",
    (_zone, zone) => {
      const days = fixture.days.records.map((input) => activityDay(make(input), zone.timeZone));
      expect(days).toEqual(zone.days);
    },
  );

  it.each(fixture.appends.map((entry) => [entry.name, entry] as const))("appends %s", async (_name, entry) => {
    const { input, output } = entry;
    const store = new InMemoryDocumentStore(
      Object.fromEntries(input.seed.map((file) => [`${folder}/${file.name}`, file.contents])),
    );
    const seeded = new Set(input.seed.map((file) => file.name));
    const repository = new ActivityLogRepository(store, input.timeZone);

    const threw: boolean[] = [];
    for (const batch of input.batches) {
      try {
        await repository.append(batch.map(make));
        threw.push(false);
      } catch {
        threw.push(true);
      }
    }
    expect(threw).toEqual(output.threw);

    const files = Object.entries(store.snapshot())
      .filter(([name]) => name.startsWith(`${folder}/`))
      .map(([name, contents]) => ({ name: name.slice(folder.length + 1), contents }))
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    expect(files.map((file) => file.name)).toEqual(output.files.map((file) => file.name));
    for (const [index, expected] of output.files.entries()) {
      const actual = files[index];
      if (actual === undefined) throw new Error(`missing file ${expected.name}`);
      /* The Mac's exact bytes: sorted keys, ` : `, escaped slashes, `{\n\n}` for empty metadata. */
      expect(actual.contents, `${expected.name} text`).toBe(expected.contents);
      if (expected.document !== undefined) {
        const document: unknown = JSON.parse(actual.contents);
        expectGolden(document, expected.document, expected.name);
        if (!validateDayFile(document)) {
          throw new Error(`${expected.name} breaks the schema: ${JSON.stringify(validateDayFile.errors)}`);
        }
      } else {
        /* A file the repository did not write (a broken day, readme.txt) stays as seeded. */
        expect(seeded.has(expected.name), `${expected.name} was seeded`).toBe(true);
      }
    }

    const savedDays = await repository.savedDays();
    expect(savedDays).toEqual(output.savedDays);
    const first = savedDays[0];
    const last = savedDays[savedDays.length - 1];
    const readBack = first === undefined || last === undefined ? [] : await repository.recordsBetween(first, last);
    expectGolden(readBack, output.readBack, `${entry.name} readBack`);
  });

  it.each(fixture.reads.map((entry) => [entry.name, entry] as const))("reads the day file %s", async (_name, entry) => {
    const store = new InMemoryDocumentStore({ [`${folder}/2026-10-02.json`]: entry.contents });
    const repository = new ActivityLogRepository(store, "UTC");
    let records: ActivityRecord[] | undefined;
    try {
      records = await repository.records("2026-10-02");
    } catch {
      records = undefined;
    }
    if (entry.records === undefined) {
      expect(records, `${entry.name} is refused`).toBeUndefined();
    } else {
      expectGolden(records, entry.records, entry.name);
    }
  });
});
