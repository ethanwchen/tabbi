// The weekly recap on the runtime: the store builds last week's recap from
// the activity log and saves it under Recaps/recaps.json, the moment shows
// the card once in the takeover slot when the island opens and never while
// something else owns the slot, and the share image draws every format.
import { beforeAll, describe, expect, it } from "vitest";
import { takeoverSlot } from "../../../src/app/takeover";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { latestReadyWeek } from "../../../src/core/recap/recapWeek";
import { recapShareFileName } from "../../../src/core/recap/recapShareFormat";
import { dayKeyStart } from "../../../src/core/planner/plannerDayKey";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { ClosetModule } from "../../../src/modules/closet/closetModule";
import { blobToBase64 } from "../../../src/modules/closet/recap/recapSharing";
import { switchLanguage } from "../../support/catalogs";
import { testApp } from "../../support/runtime";

/* A Wednesday noon UTC, so the latest ready week is the one before. */
const NOW = Date.UTC(2026, 9, 14, 12) / 1000;
const WITH_CLOSET = { "settings.modules.order": ["closet"], "settings.modules.disabled": [] };

beforeAll(() => switchLanguage("en"));

const settle = async () => {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

describe("the weekly recap on the runtime", () => {
  it("builds last week from the log on open, shows it once, and saves the archive", async () => {
    const { app, host } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    const week = latestReadyWeek(NOW, "UTC");
    const monday = dayKeyStart(week, "UTC");
    await app.activityLog.record(
      makeActivityRecord({ source: MODULE_IDS.focus, kind: ACTIVITY_KINDS.focusCompleted, start: monday + 9 * 3600, end: monday + 9 * 3600 + 90 * 60, quantity: 90, unit: ACTIVITY_UNITS.minutes, metadata: { outcome: "completed" } }),
    );
    const slot = takeoverSlot(app.shared);
    await closet.moment.islandOpened();
    await settle();
    expect(closet.recaps.archive.recaps.map((recap) => [recap.week, recap.focusMinutes])).toEqual([[week, 90]]);
    expect(closet.moment.state.shown?.recap.week).toBe(week);
    expect(closet.moment.state.shown?.cheer).toBe("firstWeek");
    expect(slot.get()).toBeDefined();
    expect(host.documents.get("durable:Recaps/recaps")).toContain(`"seenWeek" : "${week}"`);
    closet.moment.islandClosed();
    expect(slot.get()).toBeUndefined();
    /* Seen: the next open shows the tabs. */
    await closet.moment.islandOpened();
    expect(closet.moment.state.shown).toBeUndefined();
    /* The list reopens it. */
    const recap = closet.recaps.archive.recaps[0];
    if (recap) closet.recaps.reopen(recap);
    expect(slot.get()).toBeDefined();
    closet.moment.dismiss();
  });

  it("waits while onboarding owns the slot, and names the file it saves", async () => {
    const { app } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET, runMode: { isDemo: true, isSnapshot: false } }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    const slot = takeoverSlot(app.shared);
    const onboarding = { Leading: () => null, Trailing: () => null, Body: () => null };
    slot.set(onboarding);
    await closet.moment.islandOpened();
    expect(closet.moment.state.shown).toBeUndefined();
    expect(slot.get()).toBe(onboarding);
    slot.set(undefined);
    expect(recapShareFileName("square", "2026-10-05", "en", "UTC")).toBe("Tabbi week Oct 5 - 11 (square).png");
    expect(await blobToBase64(new Blob([new Uint8Array([0x89, 0x50, 0x4e, 0x47])]))).toBe("iVBORw==");
  });
});
