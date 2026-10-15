import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import editionSchema from "@shared/schemas/edition.v1.schema.json";
import kitSchema from "@shared/schemas/kit.v1.schema.json";
import { BUNDLED_KIT_FILES } from "../../../src/core/kits/bundledKits";
import { BUNDLED_EDITION_FILES } from "../../../src/core/editions/bundledEditions";

/*
 * Every bundled kit and edition must match the shared JSON Schemas (draft
 * 2020-12), so a malformed file fails here rather than at a user's launch.
 */
const ajv = new Ajv2020({ allErrors: true, strict: false });
const validateKit = ajv.compile(kitSchema);
const validateEdition = ajv.compile(editionSchema);

function errors(validate: typeof validateKit): string[] {
  return (validate.errors ?? []).map((error) => `${error.instancePath || "/"} ${error.message ?? ""}`.trim());
}

describe("shared schemas", () => {
  it("accept every bundled kit", () => {
    expect(BUNDLED_KIT_FILES.length).toBeGreaterThan(0);
    for (const file of BUNDLED_KIT_FILES) {
      const valid = validateKit(JSON.parse(file.text));
      expect(errors(validateKit), file.name).toEqual([]);
      expect(valid, file.name).toBe(true);
    }
  });

  it("reject a kit that breaks the format", () => {
    expect(validateKit({ formatVersion: 2, id: "k", name: "K", modules: ["planner"] })).toBe(false);
    expect(validateKit({ formatVersion: 1, id: "My Kit", name: "K", modules: ["planner"] })).toBe(false);
  });

  /*
   * edition.v1 predates the `distribution` and `excludedModules` fields that
   * Edition.swift reads and appstore.json uses, and it rejects unknown
   * fields. Until the schema gains them (a Mac-side change to shared/),
   * those two fields are the only differences allowed; anything else fails.
   */
  const fieldsMissingFromSchema = ["distribution", "excludedModules"];

  it("accept every bundled edition, apart from the fields the schema lacks", () => {
    expect(BUNDLED_EDITION_FILES.length).toBeGreaterThan(0);
    for (const file of BUNDLED_EDITION_FILES) {
      validateEdition(JSON.parse(file.text));
      const unexpected = (validateEdition.errors ?? []).filter(
        (error) =>
          !(
            error.keyword === "additionalProperties" &&
            fieldsMissingFromSchema.includes(String(error.params.additionalProperty))
          ),
      );
      expect(unexpected, file.name).toEqual([]);
    }
  });

  it("accept the default edition as it is", () => {
    const tabbi = BUNDLED_EDITION_FILES.find((file) => file.name === "tabbi");
    expect(tabbi).toBeDefined();
    expect(validateEdition(JSON.parse(tabbi?.text ?? "null")), errors(validateEdition).join("; ")).toBe(true);
  });
});
