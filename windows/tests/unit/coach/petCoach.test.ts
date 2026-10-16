import { describe, expect, it } from "vitest";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { kitModuleSettings } from "../../../src/core/kits/kitManifest";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import {
  CoachAppList,
  DEFAULT_FOCUS_APPS,
  SUGGESTED_DISTRACTING_APPS,
  normalizedExecutable,
  type CoachAppCategory,
} from "../../../src/core/coach/coachAppList";
import {
  decisionNudge,
  nudgePausesTimer,
  PetCoach,
  STANDARD_COACH_RULES,
  type PetCoachDecision,
  type PetCoachInput,
  type PetCoachStudyState,
} from "../../../src/core/coach/petCoach";
import {
  coachLines,
  coachMessages,
  kitCoachLines,
  PET_COACH_MAX_LINE_LENGTH,
  PET_COACH_NUDGE_KINDS,
  pickCoachMessage,
  STANDARD_COACH_LINES,
  type PetCoachMessage,
} from "../../../src/core/coach/petCoachMessages";
import { characterCount } from "../../../src/core/kits/kitSettingsSchema";
import { seeded } from "./support";

const t0 = 1_800_000_000;
const at = (seconds: number) => t0 + seconds;

function input(seconds: number, options: { idle?: number; app?: CoachAppCategory; study?: PetCoachStudyState; deep?: boolean } = {}): PetCoachInput {
  return {
    now: at(seconds),
    idleSeconds: options.idle ?? 0,
    frontmost: options.app ?? "neutral",
    study: options.study ?? "focusing",
    deepFocus: options.deep ?? false,
  };
}

const rng = seeded(42);
const evaluate = (coach: PetCoach, value: PetCoachInput) => coach.evaluate(value, rng);

/* Ticks the coach every `step` seconds over a range, returning the decisions that did something. */
function run(coach: PetCoach, from: number, to: number, make: (t: number) => PetCoachInput, step = 5): [number, PetCoachDecision][] {
  const out: [number, PetCoachDecision][] = [];
  for (let t = from; t <= to; t += step) {
    const decision = evaluate(coach, make(t));
    if (decision.type !== "none") out.push([t, decision]);
  }
  return out;
}

const kinds = (events: [number, PetCoachDecision][]) => events.map(([, decision]) => decisionNudge(decision)?.kind ?? "lookOver");
const times = (events: [number, PetCoachDecision][]) => events.map(([t]) => t);

describe("CoachAppList (Windows executables)", () => {
  it("categorises by executable name, ignoring case, spaces and folders", () => {
    const list = new CoachAppList(DEFAULT_FOCUS_APPS, ["Discord.exe"]);
    expect(list.category("discord.exe")).toBe("distracting");
    expect(list.category(" DISCORD.EXE ")).toBe("distracting");
    expect(list.category("C:\\Users\\me\\AppData\\Local\\Discord\\app-1.0\\Discord.exe")).toBe("distracting");
    expect(list.category("anki.exe")).toBe("focus");
    expect(list.category("chrome.exe")).toBe("neutral");
    expect(list.category(undefined)).toBe("neutral");
    expect(list.category("")).toBe("neutral");
  });

  it("starts with an empty distracting list and unique suggestions, none of them browsers", () => {
    expect(new CoachAppList().distracting).toEqual([]);
    const ids = SUGGESTED_DISTRACTING_APPS.map((app) => normalizedExecutable(app.executable));
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.length).toBeGreaterThan(0);
    expect(ids.every((id) => id.endsWith(".exe"))).toBe(true);
    expect(ids).not.toContain("chrome.exe");
    expect(ids).not.toContain("msedge.exe");
  });

  it("lets focus win and moves apps between lists", () => {
    const list = new CoachAppList(["a.exe"], ["A.EXE", "c.exe"]);
    expect(list.category("a.exe")).toBe("focus");
    list.markDistracting("a.exe");
    expect(list.category("a.exe")).toBe("distracting");
    expect(list.focus).not.toContain("a.exe");
    list.markFocus("c.exe");
    expect(list.category("c.exe")).toBe("focus");
    list.forget("c.exe");
    expect(list.category("c.exe")).toBe("neutral");
  });

  it("toggles distracting and takes a focus app off the focus list", () => {
    const apps = new CoachAppList();
    apps.toggleDistracting("Discord.exe");
    expect(apps.isDistracting("DISCORD.EXE")).toBe(true);
    apps.toggleDistracting("discord.exe");
    expect(apps.isDistracting("Discord.exe")).toBe(false);
    expect(apps.category("Discord.exe")).toBe("neutral");
    apps.toggleDistracting("anki.exe");
    expect(apps.category("anki.exe")).toBe("distracting");
  });

  it("lists only apps added beyond the suggestions, sorted", () => {
    const apps = new CoachAppList();
    apps.markDistracting("steam.exe");
    apps.markDistracting("Zeta.exe");
    apps.markDistracting("alpha.exe");
    expect(apps.addedDistracting).toEqual(["alpha.exe", "zeta.exe"]);
  });

  it("round-trips through JSON", () => {
    const list = new CoachAppList(DEFAULT_FOCUS_APPS, ["Discord.exe"]);
    const decoded = CoachAppList.fromJSON(JSON.parse(JSON.stringify(list.toJSON())));
    expect(decoded.equals(list)).toBe(true);
    expect(() => CoachAppList.fromJSON({ focus: [1], distracting: [] })).toThrow();
  });
});

describe("PetCoach distraction escalation", () => {
  it("looks over, then speaks, then offers a pause", () => {
    const coach = new PetCoach();
    const events = run(coach, 0, 600, (t) => input(t, { app: "distracting" }));
    expect(kinds(events)).toEqual(["lookOver", "distraction", "offerPause"]);
    expect(times(events)).toEqual([30, 120, 300]);
    expect(coach.distractionStep).toBe("offeredPause");
  });

  it("does nothing before thirty seconds", () => {
    expect(run(new PetCoach(), 0, 25, (t) => input(t, { app: "distracting" }))).toEqual([]);
  });

  it("steps one at a time even when first seen late", () => {
    const coach = new PetCoach();
    expect(evaluate(coach, input(0, { app: "distracting" })).type).toBe("none");
    expect(evaluate(coach, input(400, { app: "distracting" })).type).toBe("lookOver");
    expect(decisionNudge(evaluate(coach, input(405, { app: "distracting" })))?.kind).toBe("distraction");
    expect(evaluate(coach, input(410, { app: "distracting" })).type).toBe("none");
    expect(decisionNudge(evaluate(coach, input(525, { app: "distracting" })))?.kind).toBe("offerPause");
  });

  it("ends the episode when the user leaves the distracting app", () => {
    const coach = new PetCoach();
    run(coach, 0, 60, (t) => input(t, { app: "distracting" }));
    expect(coach.distractionStep).toBe("lookedOver");
    expect(evaluate(coach, input(65)).type).toBe("none");
    expect(coach.distractionStartedAt).toBeUndefined();
    expect(coach.distractionStep).toBe("none");
    expect(evaluate(coach, input(70, { app: "distracting" })).type).toBe("none");
    expect(evaluate(coach, input(95, { app: "distracting" })).type).toBe("none");
    expect(evaluate(coach, input(100, { app: "distracting" })).type).toBe("lookOver");
  });

  it("never treats focus apps as distracting", () => {
    expect(run(new PetCoach(), 0, 900, (t) => input(t, { app: "focus" }))).toEqual([]);
  });

  it("stays quiet outside focus phases", () => {
    for (const study of ["onBreak", "paused", "notStudying"] as const) {
      expect(run(new PetCoach(), 0, 900, (t) => input(t, { idle: t, app: "distracting", study }))).toEqual([]);
    }
  });

  it("ends the episode on a break so the next focus starts fresh", () => {
    const coach = new PetCoach();
    run(coach, 0, 60, (t) => input(t, { app: "distracting" }));
    evaluate(coach, input(65, { app: "distracting", study: "onBreak" }));
    expect(coach.distractionStartedAt).toBeUndefined();
    expect(evaluate(coach, input(70, { app: "distracting" })).type).toBe("none");
  });
});

describe("PetCoach rate limits", () => {
  it("holds a new episode's bubble for the ten minute cooldown", () => {
    const coach = new PetCoach();
    run(coach, 0, 130, (t) => input(t, { app: "distracting" }));
    expect(coach.lastNudgeAt).toBe(at(120));
    evaluate(coach, input(135));
    const events = run(coach, 140, 900, (t) => input(t, { app: "distracting" }));
    expect(kinds(events)).toEqual(["lookOver", "distraction", "offerPause"]);
    expect(times(events)).toEqual([170, 720, 840]);
  });

  it("goes quiet past the hourly cap until the window rolls", () => {
    const coach = new PetCoach({ ...STANDARD_COACH_RULES, minimumNudgeInterval: 0, escalationGap: 0, maxNudgesPerHour: 2 });
    const events = run(coach, 0, 3000, (t) => input(t, { app: Math.floor(t / 400) % 2 === 0 ? "distracting" : "neutral" }));
    expect(events.filter(([, decision]) => decision.type === "nudge")).toHaveLength(2);
    const later = run(coach, 3700, 4200, (t) => input(t, { app: "distracting" }));
    expect(later.some(([, decision]) => decision.type === "nudge")).toBe(true);
  });
});

describe("PetCoach idle", () => {
  it("asks, then pauses the timer", () => {
    const events = run(new PetCoach(), 0, 400, (t) => input(t, { idle: t }));
    expect(kinds(events)).toEqual(["idleCheck", "autoPause"]);
    expect(times(events)).toEqual([120, 300]);
    const [first, second] = events.map(([, decision]) => decisionNudge(decision));
    expect(first && nudgePausesTimer(first)).toBe(false);
    expect(second && nudgePausesTimer(second)).toBe(true);
  });

  it("fires each step once per episode", () => {
    expect(run(new PetCoach(), 0, 2000, (t) => input(t, { idle: t }))).toHaveLength(2);
  });

  it("ends the idle episode on activity", () => {
    const coach = new PetCoach();
    evaluate(coach, input(0, { idle: 130 }));
    expect(coach.idleStep).toBe("asked");
    evaluate(coach, input(10, { idle: 1 }));
    expect(coach.idleStep).toBe("none");
  });

  it("waits much longer in deep focus", () => {
    const events = run(new PetCoach(), 0, 1500, (t) => input(t, { idle: t, deep: true }));
    expect(kinds(events)).toEqual(["idleCheck", "autoPause"]);
    expect(times(events)).toEqual([600, 1200]);
  });

  it("auto-pauses through the cooldown but asks only after it", () => {
    const coach = new PetCoach();
    run(coach, 0, 130, (t) => input(t, { app: "distracting" }));
    const events = run(coach, 135, 500, (t) => input(t, { idle: t - 135 }));
    expect(kinds(events)).toEqual(["autoPause"]);
    expect(times(events)).toEqual([435]);
  });

  it("can still auto-pause while a distracting app is in front", () => {
    const coach = new PetCoach({ ...STANDARD_COACH_RULES, offerPauseAfter: 10_000 });
    const events = run(coach, 0, 400, (t) => input(t, { idle: t, app: "distracting" }));
    expect(kinds(events)).toEqual(["lookOver", "distraction", "autoPause"]);
  });
});

describe("PetCoach snooze and mute", () => {
  it("silences everything until the snooze ends", () => {
    const coach = new PetCoach();
    coach.snooze(1800, t0);
    expect(coach.isSnoozed(at(100))).toBe(true);
    expect(run(coach, 0, 1795, (t) => input(t, { idle: t, app: "distracting" }))).toEqual([]);
    expect(coach.isSnoozed(at(1800))).toBe(false);
    expect(evaluate(coach, input(1800, { app: "distracting" })).type).toBe("lookOver");
    expect(coach.snoozedUntil).toBeUndefined();
  });

  it("ends a snooze and ignores a negative one", () => {
    const coach = new PetCoach();
    coach.snooze(-50, t0);
    expect(coach.isSnoozed(t0)).toBe(false);
    coach.snoozeUntil(at(600));
    coach.endSnooze();
    expect(coach.isSnoozed(at(1))).toBe(false);
  });

  it("stays quiet with the do-not-nudge switch", () => {
    const coach = new PetCoach(STANDARD_COACH_RULES, false);
    expect(run(coach, 0, 900, (t) => input(t, { idle: t, app: "distracting" }))).toEqual([]);
    coach.nudgesEnabled = true;
    expect(evaluate(coach, input(905, { idle: 905, app: "distracting" })).type).not.toBe("none");
  });
});

describe("PetCoach persistence", () => {
  const roundTrip = (coach: PetCoach) => PetCoach.fromJSON(JSON.parse(JSON.stringify(coach.toJSON())));

  it("keeps cooldowns and snooze across a relaunch, but not open episodes", () => {
    const coach = new PetCoach();
    run(coach, 0, 130, (t) => input(t, { app: "distracting" }));
    coach.snoozeUntil(at(200));
    const restored = roundTrip(coach);
    const ended = coach.clone();
    ended.endEpisodes();
    expect(restored.toJSON()).toEqual(ended.toJSON());
    expect(restored.distractionStep).toBe("none");
    expect(restored.isSnoozed(at(150))).toBe(true);
    evaluate(restored, input(300));
    expect(kinds(run(restored, 305, 600, (t) => input(t, { app: "distracting" })))).toEqual(["lookOver"]);
  });

  it("writes dates as the Mac does, seconds since 2001", () => {
    const coach = new PetCoach();
    coach.snoozeUntil(978_307_200 + 10);
    expect(coach.toJSON().snoozedUntil).toBe(10);
  });

  it("does not carry an episode open at relaunch into the next phase", () => {
    const coach = new PetCoach();
    run(coach, 0, 20, (t) => input(t, { app: "distracting" }));
    const resumed = roundTrip(coach);
    expect(resumed.distractionStartedAt).toBeUndefined();
    expect(run(resumed, 3600, 3625, (t) => input(t, { app: "distracting" }))).toEqual([]);
  });

  it("keeps cooldowns when episodes end", () => {
    const coach = new PetCoach();
    run(coach, 0, 130, (t) => input(t, { app: "distracting" }));
    expect(coach.distractionStep).toBe("nudged");
    coach.endEpisodes();
    expect(coach.distractionStartedAt).toBeUndefined();
    expect(coach.distractionStep).toBe("none");
    expect(kinds(run(coach, 135, 300, (t) => input(t, { app: "distracting" })))).toEqual(["lookOver"]);
  });
});

describe("PetCoachMessages", () => {
  it("has several lines per kind with unique ids", () => {
    for (const kind of PET_COACH_NUDGE_KINDS) expect(coachMessages(kind).length).toBeGreaterThanOrEqual(4);
    const ids = STANDARD_COACH_LINES.map((line) => line.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("fits the bubble and never shames, bundled kit lines included", () => {
    const banned = ["lazy", "fail", "distracted", "again", "procrastinat", "wasted", "waste", "should", "disappoint", "shame", "guilt", "slack off", "!"];
    const kitLines = BUNDLED_KITS.kits.flatMap((kit) => kitCoachLines(kitModuleSettings(kit.defaults, MODULE_IDS.closet)));
    for (const message of [...STANDARD_COACH_LINES, ...kitLines]) {
      expect(characterCount(message.text)).toBeLessThanOrEqual(PET_COACH_MAX_LINE_LENGTH);
      expect(message.text).not.toBe("");
      for (const word of banned) expect(message.text.toLowerCase(), message.id).not.toContain(word);
    }
  });

  it("avoids recent lines and never repeats back to back", () => {
    const pool = coachMessages("idleCheck");
    const last = pool[pool.length - 1];
    const allButOne = pool.slice(0, -1).map((line) => line.id);
    for (let seed = 0; seed < 20; seed++) {
      const random = seeded(seed);
      expect(pickCoachMessage("idleCheck", random, STANDARD_COACH_LINES, allButOne).id).toBe(last?.id);
      const everything = pool.map((line) => line.id);
      const picked = pickCoachMessage("idleCheck", random, STANDARD_COACH_LINES, everything);
      expect(picked.id).not.toBe(everything[everything.length - 1]);
      expect(picked.kind).toBe("idleCheck");
    }
  });

  it("varies its lines across nudges", () => {
    const coach = new PetCoach({ ...STANDARD_COACH_RULES, minimumNudgeInterval: 0, maxNudgesPerHour: 100 });
    const said: string[] = [];
    for (let episode = 0; episode < 6; episode++) {
      const base = episode * 1000;
      evaluate(coach, input(base));
      for (const [, decision] of run(coach, base + 5, base + 200, (t) => input(t, { app: "distracting" }))) {
        const nudge = decisionNudge(decision);
        if (nudge?.kind === "distraction") said.push(nudge.message.id);
      }
    }
    expect(said).toHaveLength(6);
    expect(new Set(said).size).toBe(6);
    expect(coach.recentMessageIDs.length).toBeLessThanOrEqual(8);
  });

  it("names no subject in the standard lines", () => {
    const subjects = ["krebs", "card", "exam", "resident", "ward", "first aid", "vignette", "anki", "step 1"];
    for (const message of STANDARD_COACH_LINES) {
      for (const subject of subjects) expect(message.text.toLowerCase()).not.toContain(subject);
    }
  });

  it("joins kit lines to the standard ones and skips bad entries", () => {
    const settings = JSON.parse(`{ "coachLines": {
      "distraction": ["  Back to cardiology?  ", "", "${"x".repeat(65)}"],
      "idleCheck": ["Deep in First Aid?"],
      "scolding": ["Unknown kinds are ignored."]
    } }`);
    const kit = kitCoachLines(settings);
    expect(kit.map((line) => line.text)).toEqual(["Back to cardiology?", "Deep in First Aid?"]);
    expect(kit.map((line) => line.id)).toEqual(["kit.distraction.0", "kit.idleCheck.0"]);
    const lines = coachLines(settings);
    expect(lines).toHaveLength(STANDARD_COACH_LINES.length + 2);
    expect(coachMessages("distraction", lines)).toHaveLength(coachMessages("distraction").length + 1);
    expect(coachLines(undefined)).toEqual(STANDARD_COACH_LINES);
    expect(coachLines({ deck: "AnKing" })).toEqual(STANDARD_COACH_LINES);
  });

  it("keeps the other kit lines when one entry is badly shaped", () => {
    const kit = kitCoachLines(
      JSON.parse(`{ "coachLines": {
        "distraction": ["Back to the essay?", 3, "Thesis still waiting."],
        "idleCheck": "Still outlining?",
        "offerPause": { "oops": true }
      } }`),
    );
    expect(kit.map((line) => line.text)).toEqual(["Back to the essay?", "Thesis still waiting.", "Still outlining?"]);
    expect(kit.map((line) => line.id)).toEqual(["kit.distraction.0", "kit.distraction.2", "kit.idleCheck.0"]);
  });

  it("flavors the coach for the medicine kit and leaves essentials neutral", () => {
    const lines = (id: string) => {
      const kit = BUNDLED_KITS.get(id);
      if (!kit) throw new Error(`no kit ${id}`);
      return kitCoachLines(kitModuleSettings(kit.defaults, MODULE_IDS.closet));
    };
    expect(lines("medicine").some((line) => line.text.includes("Krebs"))).toBe(true);
    expect(lines("essentials")).toEqual([]);
  });

  it("picks the kit lines it is given and falls back for kinds a kit lacks", () => {
    const only: PetCoachMessage[] = [{ id: "kit.distraction.0", kind: "distraction", text: "Back to torts?" }];
    const coach = new PetCoach();
    coach.evaluate(input(0), rng, only);
    const said: string[] = [];
    for (let t = 5; t <= 300; t += 5) {
      const nudge = decisionNudge(coach.evaluate(input(t, { app: "distracting" }), rng, only));
      if (nudge) said.push(nudge.message.text);
    }
    expect(said[0]).toBe("Back to torts?");
    expect(pickCoachMessage("autoPause", rng, only).kind).toBe("autoPause");
  });

  it("is reproducible with a seeded source", () => {
    const pick = (random: () => number) => Array.from({ length: 5 }, () => pickCoachMessage("distraction", random).id);
    expect(pick(seeded(7))).toEqual(pick(seeded(7)));
  });
});
