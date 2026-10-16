import { describe, expect, it } from "vitest";
import { CoachAppList } from "../../../src/core/coach/coachAppList";
import { decisionNudge, PetCoach, STANDARD_COACH_RULES } from "../../../src/core/coach/petCoach";
import { PET_COACH_NUDGE_KINDS } from "../../../src/core/coach/petCoachMessages";
import {
  nudgeReplies,
  PET_COACH_REPLIES,
  replyHelp,
  replyPausesTimer,
  replyResumesTimer,
  replyTitle,
} from "../../../src/core/coach/petCoachReply";
import { coachInput, coachStudyState, PetCoachSave } from "../../../src/core/coach/petCoachSession";
import { FocusTimer, FocusTimerConfig } from "../../../src/core/focus/focusTimer";
import { CatWisdomSchedule } from "../../../src/core/motivation/catWisdom";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { characterCount } from "../../../src/core/kits/kitSettingsSchema";
import { fixed, seeded } from "./support";

const t0 = 1_800_000_000;
const shared = (timer: FocusTimer) => timer.provided(MODULE_IDS.focus);

describe("PetCoachReply", () => {
  it("offers snooze last on every bubble, once", () => {
    for (const kind of PET_COACH_NUDGE_KINDS) {
      const replies = nudgeReplies(kind);
      expect(replies[replies.length - 1]).toBe("snooze");
      expect(replies.filter((reply) => reply === "snooze")).toHaveLength(1);
    }
  });

  it("offers the right way out", () => {
    expect(nudgeReplies("distraction")[0]).toBe("backToIt");
    expect(nudgeReplies("offerPause")[0]).toBe("pause");
    expect(nudgeReplies("idleCheck")[0]).toBe("stillHere");
    expect(nudgeReplies("autoPause")).toEqual(["resume", "snooze"]);
  });

  it("touches the timer only for pause and resume", () => {
    expect(PET_COACH_REPLIES.filter(replyPausesTimer)).toEqual(["pause"]);
    expect(PET_COACH_REPLIES.filter(replyResumesTimer)).toEqual(["resume"]);
  });

  it("snoozes the coach for fifteen minutes and leaves it awake otherwise", () => {
    const coach = new PetCoach();
    coach.handle("snooze", t0);
    expect(coach.isSnoozed(t0 + 14 * 60)).toBe(true);
    expect(coach.isSnoozed(t0 + 15 * 60)).toBe(false);
    for (const reply of PET_COACH_REPLIES.filter((candidate) => candidate !== "snooze")) {
      const awake = new PetCoach();
      awake.handle(reply, t0);
      expect(awake.isSnoozed(t0)).toBe(false);
    }
  });

  it("has titles that fit a small bubble and help that never names the notch", () => {
    for (const reply of PET_COACH_REPLIES) {
      expect(characterCount(replyTitle(reply))).toBeLessThanOrEqual(14);
      expect(replyHelp(reply).toLowerCase()).not.toContain("notch");
    }
  });
});

describe("coach study state and input", () => {
  it("reads no timer or an idle one as not studying", () => {
    expect(coachStudyState(undefined)).toBe("notStudying");
    expect(coachStudyState(shared(new FocusTimer()))).toBe("notStudying");
  });

  it("reads running, paused and break phases", () => {
    const timer = new FocusTimer();
    timer.start(t0);
    expect(coachStudyState(shared(timer))).toBe("focusing");
    const paused = timer.clone();
    paused.pause(t0 + 60);
    expect(coachStudyState(shared(paused))).toBe("paused");
    timer.advance(t0 + timer.config.focusDuration + 1);
    expect(timer.phase).toBe("rest");
    expect(coachStudyState(shared(timer))).toBe("onBreak");
  });

  it("counts long focus phases as deep focus", () => {
    const short = new FocusTimer(new FocusTimerConfig(25 * 60));
    short.start(t0);
    const long = new FocusTimer(new FocusTimerConfig(50 * 60));
    long.start(t0);
    expect(coachInput(t0, 0, "neutral", shared(short)).deepFocus).toBe(false);
    const longInput = coachInput(t0, 0, "neutral", shared(long));
    expect(longInput.deepFocus).toBe(true);
    expect(longInput.study).toBe("focusing");
  });

  it("nudges from timer input only while focusing", () => {
    const focusing = new FocusTimer();
    focusing.start(t0);
    const onBreak = focusing.clone();
    onBreak.skip(t0);
    const coach = new PetCoach();
    expect(coach.evaluate(coachInput(t0, 6 * 60, "neutral", shared(onBreak)), seeded(1)).type).toBe("none");
    expect(decisionNudge(coach.evaluate(coachInput(t0, 3 * 60, "neutral", shared(focusing)), seeded(1)))?.kind).toBe("idleCheck");
  });

  it("samples faster than the shortest threshold", () => {
    expect(PetCoach.sampleInterval).toBeLessThan(STANDARD_COACH_RULES.lookOverAfter);
  });
});

describe("PetCoachSave", () => {
  it("round-trips snooze, cooldowns and app lists, but not the open episode", () => {
    const focusing = new FocusTimer();
    focusing.start(t0);
    const coach = new PetCoach();
    coach.evaluate(coachInput(t0, 3 * 60, "neutral", shared(focusing)), seeded(3));
    coach.handle("snooze", t0);
    const apps = new CoachAppList();
    apps.markDistracting("Discord.exe");
    const save = new PetCoachSave(coach, apps);

    const text = save.encoded();
    expect(VersionedJSON.version(text)).toBe(1);
    const restored = PetCoachSave.decode(text);
    const expected = new PetCoachSave(coach.clone(), apps.clone());
    expected.coach.endEpisodes();
    expect(restored.toJSON()).toEqual(expected.toJSON());
    expect(restored.coach.idleStep).toBe("none");
    expect(restored.coach.isSnoozed(t0 + 60)).toBe(true);
    expect(restored.coach.lastNudgeAt).toBe(t0);
    expect(restored.apps.category("discord.exe")).toBe("distracting");
  });

  it("loads nothing without a document and throws on a corrupt one", async () => {
    const store = new InMemoryDocumentStore();
    expect(await PetCoachSave.load(store, "Pet/coach.json")).toBeUndefined();
    await new PetCoachSave().write(store, "Pet/coach.json");
    expect((await PetCoachSave.load(store, "Pet/coach.json"))?.toJSON()).toEqual(new PetCoachSave().toJSON());
    await store.write("Pet/coach.json", "not json");
    await expect(PetCoachSave.load(store, "Pet/coach.json")).rejects.toThrow();
  });

  it("round-trips the nudges switch and reads older saves as on", () => {
    expect(PetCoachSave.decode(new PetCoachSave(undefined, undefined, false).encoded()).nudgesOn).toBe(false);
    const json = new PetCoachSave().toJSON();
    delete json.nudgesOn;
    expect(PetCoachSave.decode(JSON.stringify(json)).nudgesOn).toBe(true);
  });

  it("keeps the Cat wisdom state and reads saves from before it as fresh", () => {
    const save = new PetCoachSave();
    save.wisdom.line({ outcome: "completed", end: t0, streakDays: 8, totalFocusMinutes: 30 }, "UTC", fixed(0));
    save.lastCompletion = t0;
    const restored = PetCoachSave.decode(save.encoded());
    expect(restored.wisdom.equals(save.wisdom)).toBe(true);
    expect(restored.lastCompletion).toBe(t0);

    const old = JSON.stringify({ version: 1, coach: new PetCoach().toJSON(), apps: new CoachAppList().toJSON() });
    const fresh = PetCoachSave.decode(old);
    expect(fresh.wisdom.equals(new CatWisdomSchedule())).toBe(true);
    expect(fresh.lastCompletion).toBeUndefined();
  });

  it("reads a save in the Mac's shape", () => {
    const mac = `{"version":1,"nudgesOn":true,"lastCompletion":820000000,
      "coach":{"rules":{"lookOverAfter":30,"distractionNudgeAfter":120,"offerPauseAfter":300,"idleCheckAfter":120,
        "idleAutoPauseAfter":300,"deepFocusIdleCheckAfter":600,"deepFocusIdleAutoPauseAfter":1200,
        "minimumNudgeInterval":600,"escalationGap":120,"maxNudgesPerHour":3},
        "nudgesEnabled":true,"lastNudgeAt":820000000,"recentNudges":[820000000],"recentMessageIDs":["idleCheck.quiet"]},
      "apps":{"focus":["net.ankiweb.anki"],"distracting":[]},
      "wisdom":{"dailyShown":[3],"comebackShown":[],"milestonesSeen":["sevenDayStreak","retired"],"baselined":true,"lastShownDay":"2026-12-25"}}`;
    const save = PetCoachSave.decode(mac);
    expect(save.lastCompletion).toBe(820_000_000 + 978_307_200);
    expect(save.coach.recentMessageIDs).toEqual(["idleCheck.quiet"]);
    expect(save.wisdom.lastShownDay).toBe("2026-12-25");
    expect([...save.wisdom.milestonesSeen]).toEqual(["sevenDayStreak"]);
  });
});
