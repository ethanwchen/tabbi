import { describe, expect, it } from "vitest";
import { PartyError, partyErrorMessage } from "../../../src/core/party/partyError";
import { NAME_FILTER_RULES, isNameAllowed } from "../../../src/core/party/partyNameFilter";
import { loadRepoJson } from "../../support/fixtures";

interface RulesFile {
  substitutions: Record<string, string>;
  ambiguous: Record<string, string>;
  anywhere: string[];
  allow: string[];
  words: string[];
}

const rules = loadRepoJson<RulesFile>("backend/shared/name-filter.json");
const cases = loadRepoJson<{ allowed: string[]; blocked: string[] }>("backend/shared/name-filter-cases.json");

describe("PartyNameFilter", () => {
  /* The app must refuse exactly what the server refuses, or a name would pass here and fail on save. */
  it("uses the server's rules", () => {
    expect(NAME_FILTER_RULES).toEqual({
      substitutions: rules.substitutions,
      ambiguous: rules.ambiguous,
      anywhere: rules.anywhere,
      allow: rules.allow,
      words: rules.words,
    });
  });

  it.each(cases.allowed)("allows %s", (name) => {
    expect(isNameAllowed(name)).toBe(true);
  });

  it.each(cases.blocked)("blocks %s", (name) => {
    expect(isNameAllowed(name)).toBe(false);
  });

  it("lets empty and punctuation-only names pass", () => {
    expect(isNameAllowed("")).toBe(true);
    expect(isNameAllowed("... !!")).toBe(true);
  });

  it("maps the server's name rejections to typed errors", () => {
    expect(PartyError.fromServer("name_not_allowed", 400, undefined).kind).toBe("nameNotAllowed");
    expect(PartyError.fromServer("pet_name_not_allowed", 400, undefined).kind).toBe("petNameNotAllowed");
    expect(PartyError.of("nameNotAllowed").isTransient).toBe(false);
    expect(partyErrorMessage(PartyError.of("petNameNotAllowed"))).toBe("That pet name isn't allowed. Please pick another.");
  });
});
