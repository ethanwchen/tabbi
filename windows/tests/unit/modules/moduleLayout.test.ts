import { describe, expect, it } from "vitest";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { MODULE_CATEGORIES, moduleDescriptor } from "../../../src/core/modules/moduleDescriptor";
import { ModuleLayout } from "../../../src/core/modules/moduleLayout";
import { BUILT_IN_CATALOG, builtInLayout, defaultTestLayout } from "../../support/builtInCatalog";

const classic = ["spotify", "system", "claudeUsage", "planner", "claudeAsk"];
/* Built-in modules that start switched off: Focus and the study tabs. */
const optIn = ["focus", "study", "anki", "party", "closet"];

function plainCatalog(ids: readonly string[], headerModule?: string): ModuleCatalog {
  return new ModuleCatalog(
    ids.map((id) =>
      moduleDescriptor({
        id,
        title: id,
        symbol: "circle",
        category: MODULE_CATEGORIES.productivity,
        accent: { red: 1, green: 1, blue: 1 },
        headerShortcut: id === headerModule ? { label: "Your pet", key: "P" } : undefined,
      }),
    ),
  );
}

/* A layout whose "pet" module opens from the header (key P), not a tab. */
function layoutWithPet(order: string[], disabled: string[] = []): ModuleLayout {
  return new ModuleLayout(order, disabled, plainCatalog(["a", "b", "pet", "c"], "pet"));
}

describe("ModuleLayout", () => {
  it("shows the original tabs and parks the rest", () => {
    const layout = defaultTestLayout();
    expect(layout.enabled).toEqual(classic);
    expect(layout.order).toEqual(BUILT_IN_CATALOG.ids);
    expect(optIn.some((id) => layout.isEnabled(id))).toBe(false);
  });

  it("appends missing modules switched off and drops unknown ones", () => {
    const layout = builtInLayout(["planner", "futureThing", "spotify", "system", "planner"], ["spotify", "alsoUnknown"]);
    expect(layout.order).toEqual(["planner", "spotify", "system", "claudeUsage", "claudeAsk", ...optIn]);
    expect(layout.enabled).toEqual(["planner", "system"]);
  });

  it("re-enables the first module when everything is off", () => {
    expect(builtInLayout(["system", "spotify"], BUILT_IN_CATALOG.ids).enabled).toEqual(["system"]);
  });

  it("never disables the last enabled module", () => {
    const layout = defaultTestLayout();
    for (const module of classic.slice(0, -1)) expect(layout.setEnabled(module, false)).toBe(true);
    expect(layout.canDisable("claudeAsk")).toBe(false);
    expect(layout.setEnabled("claudeAsk", false)).toBe(false);
    expect(layout.enabled).toEqual(["claudeAsk"]);
    expect(layout.setEnabled("system", true)).toBe(true);
    expect(layout.enabled).toEqual(["system", "claudeAsk"]);
  });

  it("moves with onMove semantics", () => {
    const layout = defaultTestLayout();
    layout.move([0], 3);
    expect(layout.order).toEqual(["system", "claudeUsage", "spotify", "planner", "claudeAsk", ...optIn]);
    layout.move([4], 0);
    expect(layout.order).toEqual(["claudeAsk", "system", "claudeUsage", "spotify", "planner", ...optIn]);
    layout.move([1, 3], 5);
    expect(layout.order).toEqual(["claudeAsk", "claudeUsage", "planner", "system", "spotify", ...optIn]);
  });

  it("offers every module that is not a tab in the library", () => {
    expect(defaultTestLayout().available).toEqual(optIn);
  });

  it("adds from the library as the last tab", () => {
    const layout = builtInLayout(["spotify", "party", "planner", "system"], ["party", "system"]);
    layout.add("system");
    expect(layout.enabled).toEqual(["spotify", "planner", "system"]);
    layout.add("party");
    expect(layout.enabled).toEqual(["spotify", "planner", "system", "party"]);
    expect(layout.available).not.toContain("party");
    /* Adding a tab again leaves the order alone. */
    layout.add("spotify");
    expect(layout.enabled).toEqual(["spotify", "planner", "system", "party"]);
  });

  it("puts a removed module back in the library but keeps one tab", () => {
    const layout = builtInLayout(["spotify", "planner"], [...optIn, "system", "claudeUsage", "claudeAsk"]);
    expect(layout.remove("spotify")).toBe(true);
    expect(layout.enabled).toEqual(["planner"]);
    expect(layout.available).toContain("spotify");
    expect(layout.remove("planner")).toBe(false);
    expect(layout.enabled).toEqual(["planner"]);
    /* Removed and added again, a module comes back at the end. */
    layout.add("spotify");
    expect(layout.enabled).toEqual(["planner", "spotify"]);
  });

  it("moves tabs by tab offsets and leaves library slots", () => {
    const layout = builtInLayout(["spotify", "party", "planner", "system", "claudeAsk"], ["party", "system"]);
    layout.moveTabs([2], 0);
    expect(layout.enabled).toEqual(["claudeAsk", "spotify", "planner"]);
    expect(layout.order.slice(0, 5)).toEqual(["claudeAsk", "party", "spotify", "system", "planner"]);
    layout.moveTabs([0], 3);
    expect(layout.enabled).toEqual(["spotify", "planner", "claudeAsk"]);
    layout.moveTabs([7], 0);
    expect(layout.enabled).toEqual(["spotify", "planner", "claudeAsk"]);
  });

  it("cycles past disabled modules and wraps", () => {
    const layout = defaultTestLayout();
    layout.setEnabled("system", false);
    expect(layout.moduleAfter("spotify")).toBe("claudeUsage");
    expect(layout.moduleAfter("claudeAsk")).toBe("spotify");
    expect(layout.moduleBefore("claudeUsage")).toBe("spotify");
    expect(layout.moduleBefore("spotify")).toBe("claudeAsk");
  });

  it("gives number shortcuts to enabled tabs", () => {
    const layout = defaultTestLayout();
    layout.setEnabled("system", false);
    expect(layout.moduleForShortcut(1)).toBe("spotify");
    expect(layout.moduleForShortcut(2)).toBe("claudeUsage");
    expect(layout.moduleForShortcut(4)).toBe("claudeAsk");
    expect(layout.moduleForShortcut(5)).toBeUndefined();
    expect(layout.moduleForShortcut(0)).toBeUndefined();
    expect(layout.shortcut("claudeUsage")).toBe(2);
    expect(layout.shortcut("system")).toBeUndefined();
    expect(layout.shortcut("study")).toBeUndefined();
  });

  it("stops number shortcuts at nine", () => {
    const ten = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"];
    const layout = new ModuleLayout(ten, [], plainCatalog(ten));
    expect(layout.enabled.length).toBe(10);
    expect(layout.moduleForShortcut(9)).toBe("i");
    expect(layout.moduleForShortcut(10)).toBeUndefined();
    expect(layout.shortcut("i")).toBe(9);
    expect(layout.shortcut("j")).toBeUndefined();
  });

  it("keeps header modules out of the tab bar and the numbers", () => {
    const layout = layoutWithPet(["a", "pet", "b", "c"]);
    expect(layout.enabled).toEqual(["a", "pet", "b", "c"]);
    expect(layout.tabs).toEqual(["a", "b", "c"]);
    expect(layout.headerShortcuts).toEqual(["pet"]);
    expect(layout.moduleForShortcut(2)).toBe("b");
    expect(layout.shortcut("pet")).toBeUndefined();
    expect(layout.headerKey("pet")).toBe("p");
    expect(layout.headerKey("a")).toBeUndefined();
  });

  it("moves tabs around the header module", () => {
    const layout = layoutWithPet(["a", "pet", "b", "c"]);
    layout.moveTabs([2], 0);
    expect(layout.tabs).toEqual(["c", "a", "b"]);
    expect(layout.order).toEqual(["c", "pet", "a", "b"]);
    expect(layout.headerShortcuts).toEqual(["pet"]);
  });

  it("opens only an enabled header module from its key", () => {
    expect(layoutWithPet(["a", "b", "pet"]).moduleForHeaderKey("P")).toBe("pet");
    expect(layoutWithPet(["a", "b", "pet"]).moduleForHeaderKey("p")).toBe("pet");
    expect(layoutWithPet(["a", "b", "pet"]).moduleForHeaderKey("a")).toBeUndefined();
    const petOff = layoutWithPet(["a", "b", "pet"], ["pet"]);
    expect(petOff.headerShortcuts).toEqual([]);
    expect(petOff.moduleForHeaderKey("p")).toBeUndefined();
    expect(petOff.headerKey("pet")).toBeUndefined();
  });

  it("cycles tabs with arrows and leaves the header module toward the tabs", () => {
    const layout = layoutWithPet(["a", "pet", "b"], ["c"]);
    expect(layout.moduleAfter("a")).toBe("b");
    expect(layout.moduleAfter("b")).toBe("a");
    expect(layout.moduleAfter("pet")).toBe("a");
    expect(layout.moduleBefore("pet")).toBe("b");
  });

  it("keeps the header module selected when it is the only one on", () => {
    const layout = layoutWithPet(["pet", "a", "b", "c"], ["a", "b", "c"]);
    expect(layout.tabs).toEqual([]);
    expect(layout.resolvedSelection("a")).toBe("pet");
    expect(layout.moduleAfter("pet")).toBe("pet");
  });

  it("falls back to the first enabled module for a selection", () => {
    const layout = builtInLayout(["planner", "spotify", "system", "claudeUsage", "claudeAsk"]);
    layout.setEnabled("system", false);
    expect(layout.resolvedSelection("system")).toBe("planner");
    expect(layout.resolvedSelection("spotify")).toBe("spotify");
    expect(layout.moduleAfter("system")).toBe("planner");
  });

  it("builds a layout that turns on exactly the listed modules", () => {
    const layout = ModuleLayout.enablingList("study, planner,anki,unknown,spotify,closet", BUILT_IN_CATALOG);
    expect(layout?.enabled).toEqual(["study", "planner", "anki", "spotify", "closet"]);
    expect(layout?.isEnabled("claudeAsk")).toBe(false);
    expect(new Set(layout?.order)).toEqual(new Set(BUILT_IN_CATALOG.ids));
    expect(ModuleLayout.enablingList("nothing,known", BUILT_IN_CATALOG)).toBeUndefined();
    expect(ModuleLayout.enablingList("", BUILT_IN_CATALOG)).toBeUndefined();
  });

  it("turns every module on in catalog order without saved data", () => {
    const catalog = plainCatalog(["study", "anki"]);
    const layout = ModuleLayout.all(catalog);
    expect(layout.order).toEqual(["study", "anki"]);
    expect(layout.enabled).toEqual(["study", "anki"]);
  });

  it("clones independently and compares by value", () => {
    const layout = defaultTestLayout();
    const copy = layout.clone();
    expect(copy.equals(layout)).toBe(true);
    copy.setEnabled("system", false);
    expect(layout.isEnabled("system")).toBe(true);
    expect(copy.equals(layout)).toBe(false);
  });
});

describe("tab reordering", () => {
  function layout(order: string[], disabled: string[] = []): ModuleLayout {
    return new ModuleLayout(order, disabled, plainCatalog(["a", "b", "c", "d", "pet"], "pet"));
  }

  it("lands a moved tab on its slot in both directions", () => {
    const tabs = layout(["a", "b", "c", "d", "pet"]);
    expect(tabs.moveTab("a", 2)).toBe(true);
    expect(tabs.tabs).toEqual(["b", "c", "a", "d"]);
    expect(tabs.moveTab("d", 0)).toBe(true);
    expect(tabs.tabs).toEqual(["d", "b", "c", "a"]);
    expect(tabs.moveTab("c", 2)).toBe(false);
    expect(tabs.moveTab("b", 99)).toBe(true);
    expect(tabs.tabs).toEqual(["d", "c", "a", "b"]);
  });

  it("keeps the paw and library modules in their slots", () => {
    const tabs = layout(["a", "pet", "b", "c", "d"], ["c"]);
    expect(tabs.moveTab("d", 0)).toBe(true);
    expect(tabs.tabs).toEqual(["d", "a", "b"]);
    expect(tabs.order).toEqual(["d", "pet", "a", "c", "b"]);
    expect(tabs.headerShortcuts).toEqual(["pet"]);
    expect(tabs.moveTab("pet", 0)).toBe(false);
    expect(tabs.moveTab("c", 0)).toBe(false);
    expect(tabs.order).toEqual(["d", "pet", "a", "c", "b"]);
  });

  it("stops step moves at either end", () => {
    const tabs = layout(["a", "b", "c", "pet"]);
    expect(tabs.canMoveTab("a", -1)).toBe(false);
    expect(tabs.moveTabBy("a", -1)).toBe(false);
    expect(tabs.canMoveTab("a", 1)).toBe(true);
    expect(tabs.moveTabBy("a", 1)).toBe(true);
    expect(tabs.tabs).toEqual(["b", "a", "c"]);
    expect(tabs.moveTabBy("a", 1)).toBe(true);
    expect(tabs.tabs).toEqual(["b", "c", "a"]);
    expect(tabs.canMoveTab("a", 1)).toBe(false);
    expect(tabs.moveTabBy("a", 1)).toBe(false);
    expect(tabs.canMoveTab("pet", -1)).toBe(false);
    expect(tabs.canMoveTab("b", 0)).toBe(false);
  });
});
