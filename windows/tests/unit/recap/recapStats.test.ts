import { beforeAll, describe, expect, it } from "vitest";
import { recapNotice } from "../../../src/core/recap/recapNotice";
import {
  RECAP_SHARE_FORMATS,
  RECAP_SHARE_SCALE,
  recapShareFileName,
  recapSharePixelSize,
  recapSharePointSize,
} from "../../../src/core/recap/recapShareFormat";
import { recapDayInitials, recapStats, recapWeekTitle } from "../../../src/core/recap/recapStats";
import { WeeklyRecap } from "../../../src/core/recap/weeklyRecap";
import { switchLanguage } from "../../support/catalogs";

/* Port of RecapStatsTests. */

const locale = "en-US";
const zone = "America/Los_Angeles";

function recap(minutesByDay: number[], fields: { sessions?: number; cards?: number; tasks?: number; points?: number; streak?: number }) {
  return new WeeklyRecap({
    week: "2026-10-05",
    minutesByDay,
    sessions: fields.sessions ?? 0,
    cardsReviewed: fields.cards ?? 0,
    tasksDone: fields.tasks ?? 0,
    points: fields.points ?? 0,
    longestStreak: fields.streak ?? 0,
  });
}

const heavyMinutes = [100, 125, 75, 150, 100, 50, 75];

beforeAll(() => switchLanguage("en"));

describe("recap stats", () => {
  it("shows every stat of a heavy week in order", () => {
    const stats = recapStats(recap(heavyMinutes, { sessions: 27, cards: 1320, tasks: 17, points: 1240, streak: 7 }), locale);
    expect(stats.map((stat) => stat.kind)).toEqual(["sessions", "bestDay", "streak", "cards", "tasks", "points"]);
    expect(stats.map((stat) => stat.value)).toEqual(["27", "Thu", "7", "1,320", "17", "1,240"]);
    expect(stats.map((stat) => stat.label)).toEqual(["sessions", "best day", "day streak", "cards", "tasks", "points"]);
  });

  it("leaves out what a light week did not have", () => {
    const stats = recapStats(recap([0, 0, 0, 0, 0, 25, 0], { sessions: 1, tasks: 1, streak: 1 }), locale);
    expect(stats.map((stat) => stat.kind)).toEqual(["sessions", "bestDay", "tasks"]);
    expect(stats.map((stat) => stat.label)).toEqual(["session", "best day", "task"]);
    expect(stats[1]?.value).toBe("Sat");
  });

  it("has no best day without focus", () => {
    expect(recapStats(recap([0, 0, 0, 0, 0, 0, 0], { cards: 40, streak: 3 }), locale).map((stat) => stat.kind)).toEqual(["streak", "cards"]);
  });
});

describe("recap notice", () => {
  it("says the week is ready with the time focused, and points at Tabbi", () => {
    const notice = recapNotice(recap(heavyMinutes, { sessions: 27, streak: 7 }), "bestYet");
    expect(notice.title).toBe("Your week with Tabbi is ready");
    expect(notice.body).toBe("Your best week yet! 11h 15m of focus. Open Tabbi to see your recap.");
    expect(recapNotice(recap([0, 0, 0, 0, 0, 0, 0], { cards: 40, streak: 1 }), "light").body).toBe(
      "A lighter week. Every minute counts. Open Tabbi to see your recap.",
    );
  });
});

describe("recap week title", () => {
  it("names the month once or twice", () => {
    expect(recapWeekTitle("2026-10-05", locale, zone)).toBe("Oct 5 - 11");
    expect(recapWeekTitle("2026-09-28", locale, zone)).toBe("Sep 28 - Oct 4");
    expect(recapWeekTitle("2026-12-28", locale, zone)).toBe("Dec 28, 2026 - Jan 3, 2027");
  });

  it("follows the locale with plain hyphens", () => {
    expect(recapWeekTitle("2026-10-05", "de", zone)).toBe("5.-11. Okt.");
    expect(recapWeekTitle("2026-10-05", "ja", zone)).toBe("10月5日～11日");
    expect(recapWeekTitle("2026-09-28", "ru", zone)).toBe("28 сент. - 4 окт.");
  });

  it("starts the day initials on Monday", () => {
    expect(recapDayInitials(locale)).toEqual(["M", "T", "W", "T", "F", "S", "S"]);
  });
});

describe("recap share format", () => {
  it("is 1080 pixels wide", () => {
    expect(recapSharePixelSize("square")).toEqual({ width: 1080, height: 1080 });
    expect(recapSharePixelSize("story")).toEqual({ width: 1080, height: 1920 });
    for (const format of RECAP_SHARE_FORMATS) {
      expect(recapSharePointSize(format).width * RECAP_SHARE_SCALE).toBe(recapSharePixelSize(format).width);
      expect(recapSharePointSize(format).height * RECAP_SHARE_SCALE).toBe(recapSharePixelSize(format).height);
    }
  });

  it("names the week and shape", () => {
    expect(recapShareFileName("square", "2026-10-05", locale, zone)).toBe("Tabbi week Oct 5 - 11 (square).png");
    expect(recapShareFileName("story", "2026-09-28", locale, zone)).toBe("Tabbi week Sep 28 - Oct 4 (story).png");
  });

  it("has no characters Windows forbids in a file name", () => {
    /* Numeric dates in some locales use slashes. */
    const name = recapShareFileName("square", "2026-10-05", "en-ZA", zone);
    expect(name).not.toMatch(/[/\\:*?"<>|]/);
    expect(name.startsWith("Tabbi week ")).toBe(true);
  });
});
