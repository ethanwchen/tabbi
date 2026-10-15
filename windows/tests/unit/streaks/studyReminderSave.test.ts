import { describe, expect, it } from "vitest";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { breedDisplayName } from "../../../src/core/pets/petBreed";
import { zonedInstant, type DayCalendar } from "../../../src/core/streaks/dayCalendar";
import {
  StudyReminderSave,
  StudyReminderSettings,
  reminderGoalMet,
  reminderMessage,
  reminderSpeaker,
  type ReminderProgressItem,
} from "../../../src/core/streaks/studyReminder";

// Port of StudyReminderSaveTests and StudyReminderSpeakerTests.
const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };

function date(day: number, hour: number, minute = 0): number {
  return zonedInstant(2026, 10, day, hour, minute, 0, calendar.timeZone);
}

function onAtSeven(): StudyReminderSave {
  return new StudyReminderSave(StudyReminderSettings.at(true, 19, 0));
}

function sameSave(a: StudyReminderSave, b: StudyReminderSave): boolean {
  return JSON.stringify(a.toJSON()) === JSON.stringify(b.toJSON());
}

describe("StudyReminderSave", () => {
  it("a new save is off", () => {
    const save = new StudyReminderSave();
    expect(save.settings.isEnabled).toBe(false);
    expect(save.plan(date(9, 9), false, false, calendar)).toBeUndefined();
    expect(save.scheduledFor).toBeUndefined();
  });

  it("plans today and remembers it", () => {
    const save = onAtSeven();
    expect(save.plan(date(9, 9), false, false, calendar)).toBe(date(9, 19));
    expect(save.scheduledFor).toBe(date(9, 19));
    expect(save.lastDelivered).toBeUndefined();
  });

  it("a passed plan counts as delivered so the day gets no second", () => {
    const save = onAtSeven();
    save.plan(date(9, 9), false, false, calendar);
    // The user moves the time later the same evening, after 7 pm fired.
    save.settings = save.settings.withMinuteOfDay(22 * 60);
    const fire = save.plan(date(9, 20), false, false, calendar);
    expect(save.lastDelivered).toBe(date(9, 19));
    expect(fire).toBe(date(10, 22));
  });

  it("studying withdraws today's plan without counting it", () => {
    const save = onAtSeven();
    save.plan(date(9, 9), false, false, calendar);
    expect(save.plan(date(9, 15), true, false, calendar)).toBe(date(10, 19));
    expect(save.lastDelivered).toBeUndefined();
  });

  it("meeting the goal withdraws today's plan", () => {
    const save = onAtSeven();
    save.plan(date(9, 9), false, false, calendar);
    expect(save.plan(date(9, 15), false, true, calendar)).toBe(date(10, 19));
  });

  it("turning it off clears the plan but keeps the delivery", () => {
    const save = onAtSeven();
    save.plan(date(9, 9), false, false, calendar);
    save.settings = save.settings.withEnabled(false);
    expect(save.plan(date(9, 21), false, false, calendar)).toBeUndefined();
    expect(save.scheduledFor).toBeUndefined();
    expect(save.lastDelivered).toBe(date(9, 19));
    // Back on the same night: still none until tomorrow.
    save.settings = save.settings.withEnabled(true).withMinuteOfDay(23 * 60);
    expect(save.plan(date(9, 21), false, false, calendar)).toBe(date(10, 23));
  });

  // testRoundTripsThroughAFile becomes a JSON round trip: file I/O is the host's.
  it("round-trips through its JSON form", () => {
    const save = onAtSeven();
    save.plan(date(9, 9), false, false, calendar);
    save.lastDelivered = date(8, 19);
    const json = JSON.parse(JSON.stringify(save.toJSON())) as Record<string, unknown>;
    expect(sameSave(StudyReminderSave.fromJSON(json), save)).toBe(true);
    expect(json.schemaVersion).toBe(1);
    expect(json.scheduledFor).toBe(date(9, 19) - 978307200);
  });

  it("damaged fields read as off", () => {
    const save = StudyReminderSave.fromJSON({ schemaVersion: 1, settings: "loud", scheduledFor: "soon" });
    expect(sameSave(save, new StudyReminderSave())).toBe(true);
  });

  it("goal met reads the study focus goal", () => {
    // StudyDailyGoal belongs to the study methods port; its progress items carry the "minutes" id.
    const halfway: ReminderProgressItem = { id: "minutes", completed: 30, target: 60 };
    const done: ReminderProgressItem = { id: "minutes", completed: 75, target: 60 };
    const cards: ReminderProgressItem = { id: "cards", completed: 0, target: 0 };
    expect(reminderGoalMet([])).toBe(false);
    expect(reminderGoalMet([cards, halfway])).toBe(false);
    expect(reminderGoalMet([cards, done])).toBe(true);
  });
});

describe("StudyReminder speaker", () => {
  it("a named pet speaks by name", () => {
    const pet = new PetProfile("Mochi", "orangeTabby");
    expect(reminderSpeaker(pet)).toBe("Mochi");
    pet.rename("Pixel");
    expect(reminderSpeaker(pet)).toBe("Pixel");
    expect(reminderMessage(reminderSpeaker(pet), 0).title).toBe("Pixel misses you");
  });

  it("a cat that goes by its breed is your cat", () => {
    const pet = new PetProfile("", "britishShorthair");
    expect(pet.name).toBe(breedDisplayName("britishShorthair"));
    expect(reminderSpeaker(pet)).toBe("Your cat");
  });
});
