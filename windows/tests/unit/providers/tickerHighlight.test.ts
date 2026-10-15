// Port of TickerHighlightTests.swift.
import { beforeAll, describe, expect, it } from "vitest";
import { usageHighlights } from "../../../src/core/claudeUsage/claudeUsageHighlights";
import { decodeKit, kitIssues } from "../../../src/core/kits/kitValidation";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { MODULE_CATEGORIES, moduleDescriptor } from "../../../src/core/modules/moduleDescriptor";
import type { ModuleID } from "../../../src/core/modules/moduleId";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { moduleProvision } from "../../../src/core/providers/moduleProvision";
import { ProvidedParty } from "../../../src/core/providers/providedParty";
import { ProviderSnapshot } from "../../../src/core/providers/providerSnapshot";
import { TickerHighlight } from "../../../src/core/providers/tickerHighlight";
import { tickerItemIsPinned, tickerItemKind, tickerItemModule, type TickerItem } from "../../../src/core/ticker/tickerItem";
import { allTickerKinds, highlightsKind, TICKER_KINDS, tickerKindTitle } from "../../../src/core/ticker/tickerKind";
import { TickerRotation } from "../../../src/core/ticker/tickerRotation";
import { TickerSources } from "../../../src/core/ticker/tickerSources";
import { BUILT_IN_CATALOG } from "../../support/builtInCatalog";
import { switchLanguage } from "../../support/catalogs";

// Date(timeIntervalSinceReferenceDate: 800_000_000) in seconds since 1970.
const now = 800_000_000 + 978_307_200;

function highlight(
  id: string,
  source: ModuleID,
  options: { priority?: number; pinned?: boolean; expiresIn?: number } = {},
): TickerHighlight {
  return new TickerHighlight({
    id,
    source,
    text: id,
    priority: options.priority ?? 0,
    isPinned: options.pinned ?? false,
    expiresAt: options.expiresIn === undefined ? undefined : now + options.expiresIn,
  });
}

const item = (value: TickerHighlight): TickerItem => ({ type: "highlight", highlight: value });

beforeAll(() => {
  switchLanguage("en");
});

describe("TickerHighlight", () => {
  it("shows each module's highest priority highlight", () => {
    const sources = new TickerSources({
      highlights: [
        highlight("easy", "leetcode", { priority: 1 }),
        highlight("daily", "leetcode", { priority: 5 }),
        highlight("streak", "leetcode", { priority: 5 }),
      ],
    });
    expect(sources.items(now)).toEqual([item(highlight("daily", "leetcode", { priority: 5 }))]);
  });

  it("rotates modules by priority then tab order between progress and the party", () => {
    const party = new ProvidedParty([
      { id: "me", name: "Me", pet: PetProfile.starter("cat"), isAway: false },
      { id: "sam", name: "Sam", pet: PetProfile.starter("cat"), isAway: false },
    ]);
    const sources = new TickerSources({
      tasksRemaining: 1,
      highlights: [highlight("a", "first"), highlight("b", "second", { priority: 3 }), highlight("c", "third")],
      party,
    });
    expect(sources.items(now).map(tickerItemKind)).toEqual(["tasks", "second", "first", "third", "party"]);
  });

  it("gives way once a highlight expires and wakes the ticker for it", () => {
    const sources = new TickerSources({
      highlights: [highlight("urgent", "leetcode", { priority: 9, expiresIn: 600 }), highlight("calm", "leetcode")],
    });
    expect(sources.items(now)[0]).toEqual(item(highlight("urgent", "leetcode", { priority: 9, expiresIn: 600 })));
    expect(sources.nextChange(now)).toBe(now + 600);
    expect(sources.items(now + 600)).toEqual([item(highlight("calm", "leetcode"))]);
  });

  it("toggles highlights per module", () => {
    const sources = new TickerSources({ highlights: [highlight("a", "leetcode", { expiresIn: 60 }), highlight("b", "chess")] });
    const kinds = new Set([highlightsKind("chess")]);
    expect(sources.items(now, kinds)).toEqual([item(highlight("b", "chess"))]);
    expect(sources.nextChange(now, kinds), "A hidden highlight's expiry doesn't wake").toBeUndefined();
  });

  it("holds the island with a pinned highlight and opens its module", () => {
    const pinned = item(highlight("contest", "leetcode", { pinned: true }));
    expect(tickerItemIsPinned(pinned)).toBe(true);
    expect(tickerItemModule(pinned)).toBe("leetcode");
    expect(tickerItemKind(pinned)).toBe(highlightsKind("leetcode"));

    const rotation = new TickerRotation(8);
    const music: TickerItem = { type: "nowPlaying" };
    rotation.update([music], now);
    expect(rotation.update([music, pinned], now + 30)).toEqual(pinned);
  });

  it("merges highlights and music from every module in the snapshot", () => {
    const snapshot = new ProviderSnapshot([
      { module: "leetcode", provision: moduleProvision({ highlights: [highlight("daily", "unset"), highlight("daily", "unset")] }) },
      { module: "spotify", provision: moduleProvision({ isPlaying: true }) },
      { module: "chess", provision: moduleProvision({ highlights: [highlight("daily", "unset")] }) },
    ]);
    expect(snapshot.highlights.map((h) => h.source)).toEqual(["leetcode", "chess"]);
    expect(snapshot.isPlaying).toBe(true);
    expect(TickerSources.of(snapshot).items(now).map(tickerItemKind)).toEqual([
      TICKER_KINDS.nowPlaying,
      highlightsKind("leetcode"),
      highlightsKind("chess"),
    ]);
  });

  it("lists modules that declare highlights among every kind, in catalog order", () => {
    const catalog = new ModuleCatalog([
      moduleDescriptor({
        id: "quiet",
        title: "Quiet",
        symbol: "circle",
        category: MODULE_CATEGORIES.productivity,
        accent: { red: 0, green: 0, blue: 0 },
      }),
      moduleDescriptor({
        id: "leetcode",
        title: "LeetCode",
        symbol: "chevron.left.forwardslash.chevron.right",
        category: MODULE_CATEGORIES.productivity,
        accent: { red: 1, green: 0.6, blue: 0 },
        highlightTitle: "LeetCode daily problem",
      }),
    ]);
    expect(allTickerKinds(catalog)).toEqual(["meeting", "nowPlaying", "focus", "tasks", "progress", "leetcode", "party", "pet"]);
    expect(tickerKindTitle(highlightsKind("leetcode"), catalog)).toBe("LeetCode daily problem");
    expect(tickerKindTitle(TICKER_KINDS.meeting, catalog)).toBe("Next meeting");
  });

  it("lets a kit's ticker name modules by id", () => {
    // The Mac also checks KitDefaults.resolvedTicker(catalog:), which has no Windows port yet; only the issues are checked here.
    const kit = decodeKit(`{"formatVersion": 1, "id": "tech", "name": "Tech", "modules": [{"id": "claudeUsage"}],
      "defaults": {"ticker": ["focus", "claudeUsage", "weather"]}}`);
    expect(kit.ok).toBe(true);
    if (!kit.ok) return;
    expect(kitIssues(kit.kit, BUILT_IN_CATALOG)).toEqual([{ kind: "unknownTickerKind", value: "weather" }]);
  });

  it("publishes one Claude usage highlight per full window", () => {
    const reset = now + 3600;
    const highlights = usageHighlights(
      { fiveHour: { utilization: 1.02, resetsAt: reset }, sevenDay: { utilization: 0.5 } },
      now,
    ).map((h) => new TickerHighlight(h));
    expect(highlights.map((h) => h.text)).toEqual(["5h 102%"]);
    expect(highlights[0]?.tone).toBe("danger");
    expect(highlights[0]?.summary).toBe("Claude usage 5h 102%");
    expect(highlights[0]?.expiresAt).toBe(reset);
    expect(highlights[0]?.symbol, "Uses the module's own symbol").toBeUndefined();
  });
});
