import { describe, expect, it } from "vitest";
import cases from "../shared/name-filter-cases.json";
import { isNameAllowed } from "../src/names";
import { call, expectError, register } from "./helpers";

describe("name filter", () => {
  it.each(cases.allowed)("allows %s", (name) => {
    expect(isNameAllowed(name)).toBe(true);
  });

  it.each(cases.blocked)("blocks %s", (name) => {
    expect(isNameAllowed(name)).toBe(false);
  });
});

describe("profile names", () => {
  it("refuses a blocked name or pet name on register and leaves no user behind", async () => {
    expectError(await call("POST", "/v1/register", { name: "f.u.c.k" }, undefined, "10.254.0.1"), 400, "name_not_allowed");
    expectError(await call("POST", "/v1/register", { petName: "Sh1thead" }, undefined, "10.254.0.2"), 400, "pet_name_not_allowed");
  });

  it("refuses a blocked rename and keeps the old name", async () => {
    const a = await register({ name: "Maya", petName: "Mochi" });
    expectError(await call("PATCH", "/v1/me", { name: "BigCunt" }, a.token), 400, "name_not_allowed");
    expectError(await call("PATCH", "/v1/me", { petName: "wh0re" }, a.token), 400, "pet_name_not_allowed");
    const me = await call("GET", "/v1/me", undefined, a.token);
    expect(me.body.profile).toMatchObject({ name: "Maya", petName: "Mochi" });
  });

  it("accepts ordinary names that contain a short blocked word", async () => {
    const a = await register({ name: "Cassandra" });
    const r = await call("PATCH", "/v1/me", { name: "Dick Van Dyke", petName: "Scunthorpe" }, a.token);
    expect(r.status).toBe(200);
    expect(r.body.profile).toMatchObject({ name: "Dick Van Dyke", petName: "Scunthorpe" });
  });
});
