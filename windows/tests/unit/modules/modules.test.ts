import { afterEach, describe, expect, it } from "vitest";
import { setLookup } from "../../../src/core/localization/tr";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import {
  MODULE_CATEGORIES,
  decodeModuleCategory,
  isLocalNetworkAccess,
  moduleCategory,
  moduleDescriptor,
  modulePermissionTitle,
} from "../../../src/core/modules/moduleDescriptor";
import { isEmptyChanges, ModuleLifecycle } from "../../../src/core/modules/moduleLifecycle";
import { ModuleLayout } from "../../../src/core/modules/moduleLayout";
import { RowReorderDrag } from "../../../src/core/modules/rowReorderDrag";
import { rowViewportHeight } from "../../../src/core/modules/rowViewport";
import {
  DEMO_RUN_MODE,
  LIVE_RUN_MODE,
  isEphemeral,
  runModeFrom,
} from "../../../src/core/modules/runMode";
import { kitLayout } from "../../../src/core/kits/kitApplication";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { BUILT_IN_CATALOG, defaultTestLayout } from "../../support/builtInCatalog";

const accent = { red: 0, green: 0, blue: 0 };

function descriptor(id: string, title = id, extra: { ownsFocusClock?: boolean } = {}) {
  return moduleDescriptor({ id, title, symbol: "circle", category: MODULE_CATEGORIES.study, accent, ...extra });
}

afterEach(() => setLookup(() => undefined));

describe("ModuleCategory", () => {
  it("decodes stored ids and keeps built-in titles", () => {
    const decoded = ["ai", "law"].map(decodeModuleCategory);
    expect(decoded.map((category) => category.id)).toEqual(["ai", "law"]);
    expect(decoded.map((category) => category.title)).toEqual(["AI", "Law"]);
  });

  it("lets a module bring its own category", () => {
    const law = moduleCategory("law", "Law and LSAT");
    expect(law.id).toBe(moduleCategory("law").id);
    expect(law.title).toBe("Law and LSAT");
    expect(moduleCategory("coding").title).toBe("Coding");
  });

  it("reads built-in titles from the catalog each time", () => {
    setLookup((key) => (key === "Media" ? "Medien" : undefined));
    expect(MODULE_CATEGORIES.media.title).toBe("Medien");
    expect(modulePermissionTitle("calendars")).toBe("Calendars");
    expect(modulePermissionTitle("claudeCLI")).toBe("Claude Code CLI");
  });
});

describe("ModuleCatalog", () => {
  it("gives unknown ids a neutral placeholder", () => {
    const catalog = new ModuleCatalog([descriptor("study", "Study")]);
    const unknown = catalog.descriptor("leetcode");
    expect(catalog.contains("leetcode")).toBe(false);
    expect(unknown.title).toBe("leetcode");
    expect(unknown.symbol).toBe("square.dashed");
  });

  it("keeps the first descriptor on duplicate ids", () => {
    const catalog = new ModuleCatalog([descriptor("a", "First"), descriptor("b", "B"), descriptor("a", "Second")]);
    expect(catalog.ids).toEqual(["a", "b"]);
    expect(catalog.duplicateIDs).toEqual(["a"]);
    expect(catalog.get("a")?.title).toBe("First");
    expect(catalog.get("c")).toBeUndefined();
    expect(catalog.descriptor("c").title).toBe("c");
  });

  it("normalizes a layout against a custom catalog", () => {
    const catalog = new ModuleCatalog([descriptor("study"), descriptor("anki")]);
    const layout = new ModuleLayout(["anki", "spotify"], [], catalog);
    expect(layout.order).toEqual(["anki", "study"]);
    expect(layout.enabled).toEqual(["anki"]);
  });

  it("names the first enabled module with its own clock as the focus clock owner", () => {
    const catalog = new ModuleCatalog([
      descriptor("today"),
      descriptor("study", "Study", { ownsFocusClock: true }),
      descriptor("drill", "Drill", { ownsFocusClock: true }),
    ]);
    const layout = new ModuleLayout(["today", "drill", "study"], [], catalog);
    expect(catalog.focusClockOwner(layout)).toBe("drill");
    expect(layout.setEnabled("drill", false)).toBe(true);
    expect(catalog.focusClockOwner(layout)).toBe("study");
    expect(layout.setEnabled("study", false)).toBe(true);
    expect(catalog.focusClockOwner(layout)).toBeUndefined();
  });

  it("leaves excluded modules out and remembers them as unavailable", () => {
    const catalog = BUILT_IN_CATALOG.excluding(["claudeAsk", "chess"]);
    expect(catalog.ids).toEqual(BUILT_IN_CATALOG.ids.filter((id) => id !== "claudeAsk"));
    expect(catalog.isUnavailable("claudeAsk")).toBe(true);
    expect(catalog.isUnavailable("chess")).toBe(true);
    expect(catalog.isUnavailable("planner")).toBe(false);
  });

  it("tells a local service from a remote host", () => {
    expect(isLocalNetworkAccess({ host: "127.0.0.1", purpose: "decks" })).toBe(true);
    expect(isLocalNetworkAccess({ host: "LOCALHOST", purpose: "decks" })).toBe(true);
    expect(isLocalNetworkAccess({ host: "i.scdn.co", purpose: "art" })).toBe(false);
  });

  it("lower-cases a header shortcut's key", () => {
    const pet = moduleDescriptor({
      id: "pet",
      title: "Pet",
      symbol: "pawprint",
      category: MODULE_CATEGORIES.fun,
      accent,
      headerShortcut: { label: "Your pet", key: "P" },
    });
    expect(pet.headerShortcut?.key).toBe("p");
  });
});

describe("ModuleLifecycle", () => {
  it("starts every enabled module in tab order on the first update", () => {
    const lifecycle = new ModuleLifecycle();
    expect(lifecycle.update(["planner", "spotify", "system"])).toEqual({
      start: ["planner", "spotify", "system"],
      stop: [],
    });
    expect(lifecycle.running).toEqual(["planner", "spotify", "system"]);
  });

  it("does nothing for the same set or a new order", () => {
    const lifecycle = new ModuleLifecycle();
    lifecycle.update(["planner", "spotify", "system"]);
    expect(isEmptyChanges(lifecycle.update(["planner", "spotify", "system"]))).toBe(true);
    expect(isEmptyChanges(lifecycle.update(["system", "planner", "spotify"]))).toBe(true);
  });

  it("stops disabled modules and starts enabled ones", () => {
    const lifecycle = new ModuleLifecycle();
    lifecycle.update(["planner", "spotify", "system"]);
    const changes = lifecycle.update(["planner", "anki"]);
    expect(changes.stop).toEqual(["spotify", "system"]);
    expect(changes.start).toEqual(["anki"]);
    expect(lifecycle.running).toEqual(["planner", "anki"]);
  });

  it("starts duplicate ids once", () => {
    const lifecycle = new ModuleLifecycle();
    expect(lifecycle.update(["study", "study", "anki"]).start).toEqual(["study", "anki"]);
    expect(lifecycle.running).toEqual(["study", "anki"]);
  });

  it("swaps the running set when kits switch", () => {
    const lifecycle = new ModuleLifecycle();
    const medicineKit = BUNDLED_KITS.get("medicine");
    expect(medicineKit).toBeDefined();
    if (!medicineKit) return;
    const medicine = kitLayout(medicineKit, BUILT_IN_CATALOG);
    lifecycle.update(defaultTestLayout().enabled);
    const changes = lifecycle.update(medicine.enabled);
    expect(changes.start).toContain("study");
    expect(changes.stop).toContain("system");
    expect(changes.start).not.toContain("planner");
    expect(new Set(lifecycle.running)).toEqual(new Set(medicine.enabled));
  });

  it("stops everything in start order and clears", () => {
    const lifecycle = new ModuleLifecycle();
    lifecycle.update(["planner", "spotify"]);
    expect(lifecycle.stopAll()).toEqual({ start: [], stop: ["planner", "spotify"] });
    expect(lifecycle.running).toEqual([]);
    expect(isEmptyChanges(lifecycle.stopAll())).toBe(true);
  });
});

describe("RowViewport", () => {
  it("ends a list on the last whole row", () => {
    expect(rowViewportHeight(119, 22)).toBe(110);
    expect(rowViewportHeight(131.9, 22)).toBe(110);
    expect(rowViewportHeight(132, 22)).toBe(132);
  });

  it("keeps a space shorter than one row, and never goes negative", () => {
    expect(rowViewportHeight(15, 22)).toBe(15);
    expect(rowViewportHeight(-4, 22)).toBe(0);
    expect(rowViewportHeight(100, 0)).toBe(100);
  });
});

describe("RowReorderDrag", () => {
  it("keeps the lifted row in the list while it follows the pointer", () => {
    const drag = new RowReorderDrag(1, 4, 40);
    drag.translation = 30;
    expect(drag.liftedOffset).toBe(30);
    drag.translation = -500;
    expect(drag.liftedOffset).toBe(-40);
    drag.translation = 500;
    expect(drag.liftedOffset).toBe(80);
    expect(drag.target).toBe(3);
  });

  it("targets the slot under the row's center", () => {
    const drag = new RowReorderDrag(0, 3, 40);
    drag.translation = 19;
    expect(drag.target).toBe(0);
    expect(drag.movesRow).toBe(false);
    drag.translation = 21;
    expect(drag.target).toBe(1);
    expect(drag.movesRow).toBe(true);
  });

  it("slides passed rows toward the gap", () => {
    const down = new RowReorderDrag(0, 4, 40, 80);
    expect(down.target).toBe(2);
    expect([0, 1, 2, 3].map((i) => down.offset(i))).toEqual([80, -40, -40, 0]);
    down.translation = 0;
    expect([0, 1, 2, 3].map((i) => down.offset(i))).toEqual([0, 0, 0, 0]);
    const up = new RowReorderDrag(3, 4, 40, -85);
    expect(up.target).toBe(1);
    expect([0, 1, 2, 3].map((i) => up.offset(i))).toEqual([0, 40, 40, -85]);
  });

  it("matches the layout move on release", () => {
    const catalog = new ModuleCatalog(["a", "b", "c", "d"].map((id) => descriptor(id)));
    const tabs = new ModuleLayout(["a", "b", "c", "d"], [], catalog);
    const drag = new RowReorderDrag(3, tabs.tabs.length, 36, -70);
    tabs.moveTab(tabs.tabs[drag.from] ?? "", drag.target);
    expect(tabs.tabs).toEqual(["a", "d", "b", "c"]);
  });
});

describe("RunMode", () => {
  it("is live for a plain launch", () => {
    const mode = runModeFrom({}, ["Tabbi"]);
    expect(mode).toEqual(LIVE_RUN_MODE);
    expect(isEphemeral(mode)).toBe(false);
  });

  it("needs the demo variable set to 1", () => {
    expect(runModeFrom({ TABBI_DEMO: "1" }, [])).toEqual(DEMO_RUN_MODE);
    expect(runModeFrom({ TABBI_DEMO: "0" }, [])).toEqual(LIVE_RUN_MODE);
    expect(runModeFrom({ TABBI_DEMO: "true" }, [])).toEqual(LIVE_RUN_MODE);
  });

  it("makes a snapshot run that saves nothing", () => {
    const mode = runModeFrom({}, ["Tabbi", "--snapshot", "snapshots"]);
    expect(mode.isSnapshot).toBe(true);
    expect(mode.isDemo).toBe(false);
    expect(isEphemeral(mode)).toBe(true);
  });

  it("makes demo snapshots both", () => {
    const mode = runModeFrom({ TABBI_DEMO: "1" }, ["--snapshot", "snapshots-demo"]);
    expect(mode).toEqual({ isDemo: true, isSnapshot: true });
    expect(isEphemeral(mode)).toBe(true);
  });

  it("only counts the exact flag", () => {
    expect(runModeFrom({}, ["--snapshots"])).toEqual(LIVE_RUN_MODE);
  });
});
