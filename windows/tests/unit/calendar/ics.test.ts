import { describe, expect, it } from "vitest";
import { eventsInRange, icsEvents, parseICS, MAX_INSTANCES_PER_EVENT } from "../../../src/core/calendar/ics";
import { parseComponents, parseContentLine, unescapeText, unfoldLines } from "../../../src/core/calendar/icsLexer";
import { parseDuration, resolveTZID } from "../../../src/core/calendar/icsTime";
import { parseRecurrenceRule } from "../../../src/core/calendar/icsRecurrence";
import { WINDOWS_ZONES, windowsZoneToIANA } from "../../../src/core/calendar/windowsZones";
import { isKnownTimeZone } from "../../../src/core/calendar/zonedCalendar";

/* Seconds since 1970 of a UTC time; months are 1-based. */
function utc(year: number, month: number, day: number, hour = 0, minute = 0): number {
  return Date.UTC(year, month - 1, day, hour, minute) / 1000;
}

function ics(...lines: string[]): string {
  return ["BEGIN:VCALENDAR", "VERSION:2.0", ...lines, "END:VCALENDAR"].join("\r\n");
}

const LA = "America/Los_Angeles";

const GOOGLE = [
  "BEGIN:VCALENDAR",
  "PRODID:-//Google Inc//Google Calendar 70.9054//EN",
  "VERSION:2.0",
  "CALSCALE:GREGORIAN",
  "METHOD:PUBLISH",
  "X-WR-CALNAME:Work",
  "X-WR-TIMEZONE:America/Los_Angeles",
  "BEGIN:VTIMEZONE",
  "TZID:America/Los_Angeles",
  "X-LIC-LOCATION:America/Los_Angeles",
  "BEGIN:DAYLIGHT",
  "TZOFFSETFROM:-0800",
  "TZOFFSETTO:-0700",
  "TZNAME:PDT",
  "DTSTART:19700308T020000",
  "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU",
  "END:DAYLIGHT",
  "BEGIN:STANDARD",
  "TZOFFSETFROM:-0700",
  "TZOFFSETTO:-0800",
  "TZNAME:PST",
  "DTSTART:19701101T020000",
  "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU",
  "END:STANDARD",
  "END:VTIMEZONE",
  "BEGIN:VEVENT",
  "DTSTART;TZID=America/Los_Angeles:20261012T093000",
  "DTEND;TZID=America/Los_Angeles:20261012T100000",
  "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR",
  "EXDATE;TZID=America/Los_Angeles:20261014T093000",
  "DTSTAMP:20261001T120000Z",
  "UID:standup-1@google.com",
  "SUMMARY:Team standup",
  "DESCRIPTION:Join with Google Meet: https://meet.google.com/abc-defg-hij\\nOr d",
  " ial by phone: +1 650-555-0100 PIN: 123456#",
  "LOCATION:",
  "STATUS:CONFIRMED",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "DTSTART;TZID=America/Los_Angeles:20261016T110000",
  "DTEND;TZID=America/Los_Angeles:20261016T113000",
  "RECURRENCE-ID;TZID=America/Los_Angeles:20261016T093000",
  "UID:standup-1@google.com",
  "SUMMARY:Team standup (moved)",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "DTSTART;VALUE=DATE:20261012",
  "DTEND;VALUE=DATE:20261013",
  "UID:holiday-1@google.com",
  "SUMMARY:Columbus Day",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "DTSTART:20261013T200000Z",
  "DTEND:20261013T210000Z",
  "UID:dentist@google.com",
  "SUMMARY:Dentist\\, then lunch\\; bring card",
  "LOCATION:123 Main St\\, Suite 4",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "DTSTART:20261014T200000Z",
  "DTEND:20261014T210000Z",
  "UID:cancelled@google.com",
  "SUMMARY:Called off",
  "STATUS:CANCELLED",
  "END:VEVENT",
  "END:VCALENDAR",
  "",
].join("\r\n");

const OUTLOOK = [
  "BEGIN:VCALENDAR",
  "METHOD:PUBLISH",
  "PRODID:Microsoft Exchange Server 2010",
  "VERSION:2.0",
  "X-WR-CALNAME:Calendar",
  "BEGIN:VTIMEZONE",
  "TZID:Pacific Standard Time",
  "BEGIN:STANDARD",
  "DTSTART:16010101T020000",
  "TZOFFSETFROM:-0700",
  "TZOFFSETTO:-0800",
  "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11",
  "END:STANDARD",
  "BEGIN:DAYLIGHT",
  "DTSTART:16010101T020000",
  "TZOFFSETFROM:-0800",
  "TZOFFSETTO:-0700",
  "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3",
  "END:DAYLIGHT",
  "END:VTIMEZONE",
  "BEGIN:VTIMEZONE",
  "TZID:Customized Time Zone",
  "BEGIN:STANDARD",
  "DTSTART:16010101T020000",
  "TZOFFSETFROM:-0700",
  "TZOFFSETTO:-0800",
  "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11",
  "END:STANDARD",
  "BEGIN:DAYLIGHT",
  "DTSTART:16010101T020000",
  "TZOFFSETFROM:-0800",
  "TZOFFSETTO:-0700",
  "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3",
  "END:DAYLIGHT",
  "END:VTIMEZONE",
  "BEGIN:VEVENT",
  "DESCRIPTION:\\n____________________________________\\nMicrosoft Teams meeting\\nJoin on your computer or mobile app\\n",
  " Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d>\\n",
  "RRULE:FREQ=MONTHLY;COUNT=6;INTERVAL=1;BYDAY=2TU",
  "UID:040000008200E00074C5B7101A82E00800000000AB12",
  "SUMMARY;LANGUAGE=en-US:Monthly planning",
  "DTSTART;TZID=Pacific Standard Time:20261013T140000",
  "DTEND;TZID=Pacific Standard Time:20261013T150000",
  "CLASS:PUBLIC",
  "PRIORITY:5",
  "TRANSP:OPAQUE",
  "STATUS:CONFIRMED",
  "LOCATION;LANGUAGE=en-US:Microsoft Teams Meeting",
  "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:040000008200E00074C5B7101A82E00800000000AB12",
  "RECURRENCE-ID;TZID=Pacific Standard Time:20261208T140000",
  "SUMMARY;LANGUAGE=en-US:Monthly planning",
  "DTSTART;TZID=Pacific Standard Time:20261208T140000",
  "DTEND;TZID=Pacific Standard Time:20261208T150000",
  "STATUS:CANCELLED",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:040000008200E00074C5B7101A82E00800000000CD34",
  "SUMMARY:Customer call",
  "DTSTART;TZID=Customized Time Zone:20261020T083000",
  "DTEND;TZID=Customized Time Zone:20261020T090000",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:040000008200E00074C5B7101A82E00800000000EF56",
  "SUMMARY:Offsite",
  'DTSTART;TZID="(UTC-08:00) Pacific Time (US & Canada)":20261021T090000',
  'DTEND;TZID="(UTC-08:00) Pacific Time (US & Canada)":20261021T170000',
  "END:VEVENT",
  "END:VCALENDAR",
].join("\r\n");

const ICLOUD = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//Apple Inc.//macOS 15.0//EN",
  "CALSCALE:GREGORIAN",
  "BEGIN:VTIMEZONE",
  "TZID:Europe/Berlin",
  "BEGIN:DAYLIGHT",
  "TZOFFSETFROM:+0100",
  "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU",
  "DTSTART:19810329T020000",
  "TZNAME:CEST",
  "TZOFFSETTO:+0200",
  "END:DAYLIGHT",
  "BEGIN:STANDARD",
  "TZOFFSETFROM:+0200",
  "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU",
  "DTSTART:19961027T030000",
  "TZNAME:CET",
  "TZOFFSETTO:+0100",
  "END:STANDARD",
  "END:VTIMEZONE",
  "BEGIN:VEVENT",
  "UID:7A4C1C1E-0E0B-4C55-9A3C-4B0A2E1C1A01",
  "DTSTART;TZID=Europe/Berlin:20261015T183000",
  "DURATION:PT1H30M",
  "SUMMARY:Yoga",
  "URL;VALUE=URI:https://zoom.us/j/5551234567",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:7A4C1C1E-0E0B-4C55-9A3C-4B0A2E1C1A02",
  "DTSTART;VALUE=DATE:19900314",
  "DTEND;VALUE=DATE:19900315",
  "RRULE:FREQ=YEARLY",
  "SUMMARY:Mia's birthday",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:7A4C1C1E-0E0B-4C55-9A3C-4B0A2E1C1A03",
  "DTSTART:20261016T070000",
  "DTEND:20261016T073000",
  "SUMMARY:Morning run",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:7A4C1C1E-0E0B-4C55-9A3C-4B0A2E1C1A04",
  "DTSTART;TZID=Europe/Berlin:20260130T170000",
  "DTEND;TZID=Europe/Berlin:20260130T180000",
  "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;UNTIL=20261231T225959Z",
  "SUMMARY:Pay rent",
  "END:VEVENT",
  "END:VCALENDAR",
].join("\n");

describe("content lines", () => {
  it("unfolds lines continued with a space or tab", () => {
    expect(unfoldLines("A:1\r\n 2\n\t3\r\nB:4")).toEqual(["A:123", "B:4"]);
  });

  it("reads parameters, quoted values with colons and lists", () => {
    const line = parseContentLine('DESCRIPTION;ALTREP="https://x.example/a:b";LANGUAGE=en,de:Hello: world');
    expect(line?.name).toBe("DESCRIPTION");
    expect(line?.params.ALTREP).toEqual(["https://x.example/a:b"]);
    expect(line?.params.LANGUAGE).toEqual(["en", "de"]);
    expect(line?.value).toBe("Hello: world");
    expect(parseContentLine("no colon here")).toBeUndefined();
  });

  it("undoes TEXT escapes", () => {
    expect(unescapeText("a\\, b\\; c\\\\d\\ne\\Nf")).toBe("a, b; c\\d\ne\nf");
  });

  it("closes components left open and ignores stray ENDs", () => {
    const root = parseComponents("BEGIN:VCALENDAR\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:x");
    expect(root.components[0]?.components[0]?.name).toBe("VEVENT");
  });

  it("reads durations", () => {
    expect(parseDuration("PT1H30M")).toEqual({ days: 0, seconds: 5400 });
    expect(parseDuration("P1W2D")).toEqual({ days: 9, seconds: 0 });
    expect(parseDuration("-PT15M")).toEqual({ days: -0, seconds: -900 });
    expect(parseDuration("P")).toBeUndefined();
    expect(parseDuration("soon")).toBeUndefined();
  });
});

describe("time zones", () => {
  it("maps every Windows zone id to a zone this runtime knows", () => {
    for (const [windows, iana] of Object.entries(WINDOWS_ZONES)) expect(isKnownTimeZone(iana), windows).toBe(true);
    expect(windowsZoneToIANA("Pacific Standard Time")).toBe(LA);
    expect(windowsZoneToIANA("w. europe standard time")).toBe("Europe/Berlin");
    expect(windowsZoneToIANA("(UTC-08:00) Pacific Time (US & Canada)")).toBe(LA);
    expect(windowsZoneToIANA("Mars Standard Time")).toBeUndefined();
  });

  it("resolves TZIDs by IANA name, prefixed path, Windows id, display name and offset", () => {
    const zones = new Map();
    const at = { year: 2026, month: 7, day: 1, hour: 12 };
    expect(resolveTZID("America/New_York", zones)?.instant(at)).toBe(utc(2026, 7, 1, 16));
    expect(resolveTZID("/mozilla.org/20050126_1/America/New_York", zones)?.instant(at)).toBe(utc(2026, 7, 1, 16));
    expect(resolveTZID("Eastern Standard Time", zones)?.instant(at)).toBe(utc(2026, 7, 1, 16));
    expect(resolveTZID("tzone://Microsoft/Utc", zones)?.instant(at)).toBe(utc(2026, 7, 1, 12));
    expect(resolveTZID("(UTC+05:30) Somewhere new", zones)?.instant(at)).toBe(utc(2026, 7, 1, 6, 30));
    expect(resolveTZID("Nowhere/Special", zones)).toBeUndefined();
  });
});

describe("Google Calendar feed", () => {
  const calendar = parseICS(GOOGLE);
  const week = eventsInRange(calendar, { from: utc(2026, 10, 12, 7), to: utc(2026, 10, 19, 7), timeZone: LA, idPrefix: "work" });

  it("reads the calendar's name", () => {
    expect(calendar.name).toBe("Work");
  });

  it("expands the weekly standup, skips the EXDATE and uses the moved occurrence", () => {
    const standups = week.filter((event) => event.title.startsWith("Team standup"));
    expect(standups.map((event) => [event.title, event.start, event.end])).toEqual([
      ["Team standup", utc(2026, 10, 12, 16, 30), utc(2026, 10, 12, 17)],
      ["Team standup (moved)", utc(2026, 10, 16, 18), utc(2026, 10, 16, 18, 30)],
    ]);
    expect(standups[0]?.id).toBe(`work/standup-1@google.com#T${utc(2026, 10, 12, 16, 30)}`);
    expect(standups[1]?.id).toBe(`work/standup-1@google.com#T${utc(2026, 10, 16, 16, 30)}`);
  });

  it("finds the Meet link in a folded description", () => {
    expect(week[1]?.meetingLink).toEqual({ provider: "googleMeet", url: "https://meet.google.com/abc-defg-hij" });
  });

  it("reads all-day events from midnight to midnight in the user's zone", () => {
    const holiday = week.find((event) => event.title === "Columbus Day");
    expect(holiday).toMatchObject({ isAllDay: true, start: utc(2026, 10, 12, 7), end: utc(2026, 10, 13, 7), id: "work/holiday-1@google.com" });
    const tokyo = icsEvents(GOOGLE, { from: 0, to: utc(2027, 1, 1), timeZone: "Asia/Tokyo" }).find((event) => event.isAllDay);
    expect(tokyo?.start).toBe(utc(2026, 10, 11, 15));
  });

  it("reads UTC times and escaped text, and skips cancelled events", () => {
    const dentist = week.find((event) => event.id === "work/dentist@google.com");
    expect(dentist).toMatchObject({ title: "Dentist, then lunch; bring card", start: utc(2026, 10, 13, 20), end: utc(2026, 10, 13, 21) });
    expect(week.some((event) => event.title === "Called off")).toBe(false);
  });

  it("sorts by start", () => {
    expect(week.map((event) => event.start)).toEqual([...week.map((event) => event.start)].sort((a, b) => a - b));
  });
});

describe("Outlook and Microsoft 365 feed", () => {
  const calendar = parseICS(OUTLOOK);
  const all = eventsInRange(calendar, { from: utc(2026, 10, 1), to: utc(2027, 6, 1), timeZone: "Europe/London" });

  it("expands the second Tuesday each month for COUNT occurrences, minus the cancelled one", () => {
    const planning = all.filter((event) => event.title === "Monthly planning");
    expect(planning.map((event) => event.start)).toEqual([
      utc(2026, 10, 13, 21),
      utc(2026, 11, 10, 22),
      utc(2027, 1, 12, 22),
      utc(2027, 2, 9, 22),
      utc(2027, 3, 9, 22),
    ]);
  });

  it("joins Teams through the meeting URL property", () => {
    const planning = all.find((event) => event.title === "Monthly planning");
    expect(planning?.meetingLink?.provider).toBe("teams");
    expect(planning?.meetingLink?.url).toContain("https://teams.microsoft.com/l/meetup-join/");
  });

  it("reads a custom zone from its VTIMEZONE and an Outlook display name", () => {
    expect(all.find((event) => event.title === "Customer call")?.start).toBe(utc(2026, 10, 20, 15, 30));
    expect(all.find((event) => event.title === "Offsite")?.start).toBe(utc(2026, 10, 21, 16));
  });

  it("follows a VTIMEZONE's own rules when its id is not a known zone", () => {
    const text = OUTLOOK.replace(/Customized Time Zone/g, "Strange Zone");
    const winter = icsEvents(text.replace("20261020T083000", "20261210T083000").replace("20261020T090000", "20261210T090000"), {
      from: utc(2026, 12, 1),
      to: utc(2027, 1, 1),
      timeZone: "UTC",
    }).find((event) => event.title === "Customer call");
    expect(winter?.start).toBe(utc(2026, 12, 10, 16, 30));
  });
});

describe("iCloud feed", () => {
  const events = icsEvents(ICLOUD, { from: utc(2026, 10, 1), to: utc(2027, 4, 1), timeZone: "America/New_York" });

  it("reads DURATION and the URL field", () => {
    const yoga = events.find((event) => event.title === "Yoga");
    expect(yoga).toMatchObject({ start: utc(2026, 10, 15, 16, 30), end: utc(2026, 10, 15, 18) });
    expect(yoga?.meetingLink).toEqual({ provider: "zoom", url: "https://zoom.us/j/5551234567" });
  });

  /* Midnight on March 14, 2027 is still EST: the clocks change at 2:00 that day. */
  it("repeats a yearly all-day birthday", () => {
    const birthday = events.filter((event) => event.title === "Mia's birthday");
    expect(birthday.map((event) => [event.start, event.isAllDay])).toEqual([[utc(2027, 3, 14, 5), true]]);
    expect(birthday[0]?.id).toBe("7A4C1C1E-0E0B-4C55-9A3C-4B0A2E1C1A02#D20270314");
  });

  it("reads floating times in the user's zone", () => {
    expect(events.find((event) => event.title === "Morning run")?.start).toBe(utc(2026, 10, 16, 11));
  });

  it("takes the last weekday of each month with BYSETPOS until UNTIL", () => {
    const rent = events.filter((event) => event.title === "Pay rent").map((event) => event.start);
    /* Oct 30 (Fri, CET+2 then), Nov 30 (Mon), Dec 31 (Thu) at 17:00 Berlin. */
    expect(rent).toEqual([utc(2026, 10, 30, 16), utc(2026, 11, 30, 16), utc(2026, 12, 31, 16)]);
  });
});

describe("recurrence rules", () => {
  function starts(rrule: string, start: string, zone: string, from: number, to: number, extra: string[] = []): number[] {
    return icsEvents(
      ics("BEGIN:VEVENT", "UID:r", `DTSTART;TZID=${zone}:${start}`, `RRULE:${rrule}`, ...extra, "END:VEVENT"),
      { from, to, timeZone: zone },
    ).map((event) => event.start);
  }

  it("keeps the wall-clock time across a daylight saving change", () => {
    expect(starts("FREQ=WEEKLY", "20261026T090000", "America/New_York", utc(2026, 10, 25), utc(2026, 11, 10))).toEqual([
      utc(2026, 10, 26, 13),
      utc(2026, 11, 2, 14),
      utc(2026, 11, 9, 14),
    ]);
  });

  it("follows INTERVAL, COUNT and UNTIL", () => {
    expect(starts("FREQ=DAILY;INTERVAL=2;COUNT=3", "20261001T080000", "UTC", 0, utc(2027, 1, 1))).toEqual([
      utc(2026, 10, 1, 8),
      utc(2026, 10, 3, 8),
      utc(2026, 10, 5, 8),
    ]);
    expect(starts("FREQ=DAILY;UNTIL=20261003", "20261001T080000", "UTC", 0, utc(2027, 1, 1))).toHaveLength(3);
    expect(starts("FREQ=DAILY;UNTIL=20261002T080000Z", "20261001T080000", "UTC", 0, utc(2027, 1, 1))).toHaveLength(2);
  });

  it("reads ordinal BYDAY, negative BYMONTHDAY and BYMONTH", () => {
    expect(starts("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH", "20261126T120000", "UTC", 0, utc(2029, 1, 1))).toEqual([
      utc(2026, 11, 26, 12),
      utc(2027, 11, 25, 12),
      utc(2028, 11, 23, 12),
    ]);
    expect(starts("FREQ=MONTHLY;BYDAY=-1FR;COUNT=3", "20261030T100000", "UTC", 0, utc(2028, 1, 1))).toEqual([
      utc(2026, 10, 30, 10),
      utc(2026, 11, 27, 10),
      utc(2026, 12, 25, 10),
    ]);
    expect(starts("FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3", "20260131T100000", "UTC", 0, utc(2028, 1, 1))).toEqual([
      utc(2026, 1, 31, 10),
      utc(2026, 2, 28, 10),
      utc(2026, 3, 31, 10),
    ]);
    expect(starts("FREQ=MONTHLY;BYMONTHDAY=31;COUNT=3", "20260131T100000", "UTC", 0, utc(2028, 1, 1))).toEqual([
      utc(2026, 1, 31, 10),
      utc(2026, 3, 31, 10),
      utc(2026, 5, 31, 10),
    ]);
    expect(starts("FREQ=DAILY;BYMONTH=2;COUNT=2", "20260130T100000", "UTC", 0, utc(2028, 1, 1))).toEqual([
      utc(2026, 1, 30, 10),
      utc(2026, 2, 1, 10),
    ]);
  });

  it("counts weeks from WKST", () => {
    const sundayStart = "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU;WKST=SU;COUNT=4";
    const mondayStart = "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU;WKST=MO;COUNT=4";
    expect(starts(sundayStart, "19970805T090000", "UTC", 0, utc(1998, 1, 1))).toEqual([
      utc(1997, 8, 5, 9),
      utc(1997, 8, 17, 9),
      utc(1997, 8, 19, 9),
      utc(1997, 8, 31, 9),
    ]);
    expect(starts(mondayStart, "19970805T090000", "UTC", 0, utc(1998, 1, 1))).toEqual([
      utc(1997, 8, 5, 9),
      utc(1997, 8, 10, 9),
      utc(1997, 8, 19, 9),
      utc(1997, 8, 24, 9),
    ]);
  });

  it("skips EXDATEs given as lists, dates and in another zone", () => {
    const result = starts("FREQ=DAILY;COUNT=5", "20261001T090000", "Europe/Berlin", 0, utc(2027, 1, 1), [
      "EXDATE;TZID=Europe/Berlin:20261002T090000,20261003T090000",
      "EXDATE;VALUE=DATE:20261004",
      "EXDATE:20261005T070000Z",
    ]);
    expect(result).toEqual([utc(2026, 10, 1, 7)]);
  });

  it("adds RDATEs", () => {
    expect(starts("FREQ=YEARLY;COUNT=1", "20261001T090000", "UTC", 0, utc(2027, 1, 1), ["RDATE:20261005T090000"])).toEqual([
      utc(2026, 10, 1, 9),
      utc(2026, 10, 5, 9),
    ]);
  });

  it("skips years of an old open-ended series to reach the range", () => {
    expect(starts("FREQ=DAILY", "20100101T090000", "UTC", utc(2026, 10, 15), utc(2026, 10, 17))).toEqual([
      utc(2026, 10, 15, 9),
      utc(2026, 10, 16, 9),
    ]);
  });

  it("caps the instances one event yields", () => {
    expect(starts("FREQ=DAILY", "20260101T090000", "UTC", 0, utc(2040, 1, 1))).toHaveLength(MAX_INSTANCES_PER_EVENT);
  });

  it("ends a rule that never matches", () => {
    expect(starts("FREQ=MONTHLY;BYMONTHDAY=30;BYMONTH=2", "20260101T090000", "UTC", 0, utc(2100, 1, 1))).toEqual([utc(2026, 1, 1, 9)]);
  });

  it("parses rules leniently", () => {
    expect(parseRecurrenceRule("FREQ=FORTNIGHTLY")).toBeUndefined();
    expect(parseRecurrenceRule("FREQ=WEEKLY;INTERVAL=0;BYDAY=XX,MO")?.interval).toBe(1);
    expect(parseRecurrenceRule("FREQ=WEEKLY;BYDAY=XX,MO")?.byDay).toEqual([{ weekday: 2 }]);
  });
});

describe("robustness", () => {
  it("never throws on text that isn't a feed", () => {
    for (const text of ["", "<html><body>Sign in</body></html>", "BEGIN:VCALENDAR", "\u0000￿", "BEGIN:VEVENT\nDTSTART:garbage\nEND:VEVENT"]) {
      expect(() => icsEvents(text, { from: 0, to: utc(2030, 1, 1), timeZone: LA })).not.toThrow();
      expect(icsEvents(text, { from: 0, to: utc(2030, 1, 1), timeZone: LA })).toEqual([]);
    }
  });

  it("skips a bad event but keeps the good ones", () => {
    const text = ics(
      "BEGIN:VEVENT",
      "UID:bad",
      "DTSTART:20261399T990000",
      "END:VEVENT",
      "BEGIN:VEVENT",
      "UID:good",
      "DTSTART:20261015T090000Z",
      "SUMMARY:Good",
      "RRULE:FREQ=NEVER",
      "END:VEVENT",
      "BEGIN:VTODO",
      "UID:todo",
      "DTSTART:20261015T090000Z",
      "END:VTODO",
    );
    expect(icsEvents(text, { from: utc(2026, 10, 15), to: utc(2026, 10, 16), timeZone: LA }).map((event) => event.id)).toEqual(["good"]);
  });

  it("falls back to the user's zone for an unknown TZID and to the start for a missing end", () => {
    const text = ics("BEGIN:VEVENT", "UID:x", "DTSTART;TZID=Atlantis:20261015T090000", "END:VEVENT");
    expect(icsEvents(text, { from: 0, to: utc(2030, 1, 1), timeZone: "UTC" })[0]).toMatchObject({ start: utc(2026, 10, 15, 9), end: utc(2026, 10, 15, 9) });
  });

  it("gives an all-day event without an end one day, and an unknown user zone UTC", () => {
    const text = ics("BEGIN:VEVENT", "UID:x", "DTSTART;VALUE=DATE:20261015", "END:VEVENT");
    expect(icsEvents(text, { from: 0, to: utc(2030, 1, 1), timeZone: "Not/AZone" })[0]).toMatchObject({
      start: utc(2026, 10, 15),
      end: utc(2026, 10, 16),
      isAllDay: true,
    });
  });

  it("does not depend on the machine's zone", () => {
    expect(process.env.TZ).toBe("Pacific/Chatham");
  });
});
