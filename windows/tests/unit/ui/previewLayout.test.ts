// The closed pill's wing math (NotchPreviewLayout) and the snapshot harness's
// state list, with text measured as six pixels a character so widths are exact.
import { beforeAll, describe, expect, it } from "vitest";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { tickerFocus, tickerMeeting, tickerPet, type TickerItem } from "../../../src/core/ticker/tickerItem";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { partyPetsWidth, PREVIEW, previewSymbol, wingWidth, type TextMeasure } from "../../../src/ui/shell/previewLayout";
import { DEMO_PREVIEWS } from "../../../src/ui/shell/snapshot/demoPreviews";
import { parseSnapshot, setupSteps, snapshotStates } from "../../../src/ui/shell/snapshot/snapshotPlan";
import { switchLanguage } from "../../support/catalogs";

const measure: TextMeasure = (text) => text.length * 6;
const catalog = new ModuleCatalog(MODULE_LIST.map((type) => type.descriptor));

beforeAll(() => switchLanguage("en"));

describe("wing width", () => {
  it("keeps music compact and measures a fixed-width clock", () => {
    expect(wingWidth({ type: "nowPlaying" }, measure)).toBe(PREVIEW.compactWingWidth);
    const focus = (time: number): TickerItem => ({ type: "focus", focus: tickerFocus({ phase: "focus", time, isRunning: true }) });
    /* "18:42" is five characters: 30 + 8 + 8. */
    expect(wingWidth(focus(18 * 60 + 42), measure)).toBe(46);
    expect(wingWidth(focus(11 * 60 + 11), measure)).toBe(wingWidth(focus(18 * 60 + 42), measure));
  });

  it("never goes below the icon's room and caps a long title, with room kept for Join", () => {
    expect(wingWidth({ type: "tasks", remaining: 1 }, () => 0)).toBe(PREVIEW.iconSize + PREVIEW.outerInset + PREVIEW.innerGap);
    const long = tickerMeeting({ title: "A very long meeting title that goes on", timing: { kind: "startsIn", minutes: 30 }, canJoin: false });
    expect(wingWidth({ type: "meeting", meeting: long }, measure)).toBe(PREVIEW.maxWingWidth);
    const join = tickerMeeting({ ...long, timing: { kind: "startsIn", minutes: 3 }, canJoin: true, link: { provider: "zoom", url: "https://zoom.us/j/1" } });
    /* "Join" is 24 px, padded 6 on each side, after a 4 px gap. */
    expect(wingWidth({ type: "meeting", meeting: join }, measure)).toBe(PREVIEW.maxWingWidth + 4 + 36);
  });

  it("measures a pet as if asleep, so dozing off never moves the pill", () => {
    const awake = tickerPet({ profile: new PetProfile("Pumpkin", "orangeTabby"), mood: "awake" });
    const asleep = tickerPet({ profile: new PetProfile("Pumpkin", "orangeTabby"), mood: "asleep" });
    expect(wingWidth({ type: "pet", pet: awake }, measure)).toBe(wingWidth({ type: "pet", pet: asleep }, measure));
    expect(partyPetsWidth(3)).toBe(24 + 2 * PREVIEW.partyPetStep);
  });

  it("names each preview's icon", () => {
    const icons = Object.values(DEMO_PREVIEWS).map((make) => previewSymbol(make(), catalog));
    expect(icons).toContain("rectangle.stack.fill");
    expect(icons).toContain("gauge.with.dots.needle.67percent");
  });
});

describe("snapshot plan", () => {
  it("lists every module's panel, every setup step and every Settings section", () => {
    const states = snapshotStates(MODULE_LIST);
    for (const type of MODULE_LIST) expect(states).toContain(`open:${type.descriptor.id}`);
    expect(setupSteps(MODULE_LIST).map((step) => step.id)).toEqual(["pet", "anki", "calendar", "studyMethod", "party"]);
    const sections = states.filter((state) => /^settings:[a-z]+$/.test(state));
    expect(sections).toEqual(["settings:general", "settings:tabs", "settings:look", "settings:connections", "settings:about"]);
    expect(states).toContain("settings:tabs:import");
    for (const step of ["name", "kit", "question", "modules", "extras", "startWithWindows", "trayIcon"]) expect(states).toContain(`onboarding:${step}`);
  });

  it("reads states from the query", () => {
    expect(parseSnapshot("open:study:running")).toEqual({ kind: "open", module: "study", state: "running" });
    expect(parseSnapshot("pill:focus")).toEqual({ kind: "pill", preview: "focus" });
    expect(parseSnapshot("pill:nope")).toBeUndefined();
    expect(parseSnapshot("settings")).toEqual({ kind: "settings", section: "general" });
  });
});
