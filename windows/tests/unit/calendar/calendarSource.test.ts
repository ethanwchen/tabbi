import { describe, expect, it } from "vitest";
import {
  CALENDAR_REFRESH_INTERVAL,
  IcsCalendarSource,
  feedURL,
  loadCalendarSubscriptions,
  safeSubscriptionID,
  saveCalendarSubscriptions,
  type CalendarSubscription,
} from "../../../src/core/calendar/calendarSource";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";

function utc(year: number, month: number, day: number, hour = 0, minute = 0): number {
  return Date.UTC(year, month - 1, day, hour, minute) / 1000;
}

function feed(summary: string, start = "20261015T160000Z", end = "20261015T170000Z"): string {
  return ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", `UID:${summary}`, `DTSTART:${start}`, `DTEND:${end}`, `SUMMARY:${summary}`, "END:VEVENT", "END:VCALENDAR"].join("\r\n");
}

const work: CalendarSubscription = { id: "work", name: "Work", url: "webcal://calendar.example.com/work.ics", color: { red: 0.2, green: 0.55, blue: 0.98 } };
const home: CalendarSubscription = { id: "home", name: "Home", url: "https://example.org/home.ics", color: { red: 0.98, green: 0.62, blue: 0.2 } };

/* A fetcher that answers from `answers` (a string, or an Error to reject) and logs every URL. */
function fakeFetcher(answers: Record<string, string | Error>) {
  const calls: string[] = [];
  const fetcher = async (url: string) => {
    calls.push(url);
    const answer = answers[url];
    if (answer === undefined || answer instanceof Error) throw answer ?? new Error("404");
    return answer;
  };
  return { calls, fetcher, answers };
}

const DAY = { from: utc(2026, 10, 15), to: utc(2026, 10, 16) };

describe("feed addresses", () => {
  it("turns webcal links into https and refuses other schemes", () => {
    expect(feedURL("webcal://p01-calendars.icloud.com/published/2/abc")).toBe("https://p01-calendars.icloud.com/published/2/abc");
    expect(feedURL(" webcals://x.example/a.ics ")).toBe("https://x.example/a.ics");
    expect(feedURL("https://calendar.google.com/calendar/ical/x/basic.ics")).toBe("https://calendar.google.com/calendar/ical/x/basic.ics");
    expect(feedURL("file:///C:/cal.ics")).toBeUndefined();
    expect(feedURL("not a url")).toBeUndefined();
  });

  it("makes ids file-name safe", () => {
    expect(safeSubscriptionID("a/b:c")).toBe("a-b-c");
    expect(safeSubscriptionID("")).toBe("calendar");
  });
});

describe("IcsCalendarSource", () => {
  function make(answers: Record<string, string | Error>, store = new InMemoryDocumentStore(), clock = { now: utc(2026, 10, 15, 8) }) {
    const fake = fakeFetcher(answers);
    const source = new IcsCalendarSource({
      subscriptions: [work, home],
      fetcher: fake.fetcher,
      store,
      now: () => clock.now,
      timeZone: () => "America/Los_Angeles",
    });
    return { source, fake, store, clock };
  }

  it("merges every subscription with its color and a prefixed id", async () => {
    const { source, fake } = make({
      "https://calendar.example.com/work.ics": feed("Standup", "20261015T170000Z", "20261015T173000Z"),
      "https://example.org/home.ics": feed("Dentist"),
    });
    const events = await source.events(DAY.from, DAY.to);
    expect(events.map((event) => [event.id, event.calendarColor])).toEqual([
      ["home/Dentist", home.color],
      ["work/Standup", work.color],
    ]);
    expect(fake.calls.sort()).toEqual(["https://calendar.example.com/work.ics", "https://example.org/home.ics"]);
    expect(source.status().map((status) => [status.subscriptionID, status.hasData, status.lastUpdated, status.lastError])).toEqual([
      ["work", true, utc(2026, 10, 15, 8), undefined],
      ["home", true, utc(2026, 10, 15, 8), undefined],
    ]);
  });

  it("fetches again only after the refresh interval, or on reload", async () => {
    const { source, fake, clock } = make({ "https://calendar.example.com/work.ics": feed("A"), "https://example.org/home.ics": feed("B") });
    await source.events(DAY.from, DAY.to);
    clock.now += CALENDAR_REFRESH_INTERVAL - 1;
    await source.events(DAY.from, DAY.to);
    expect(fake.calls).toHaveLength(2);
    clock.now += 1;
    await source.events(DAY.from, DAY.to);
    expect(fake.calls).toHaveLength(4);
    await source.reload();
    expect(fake.calls).toHaveLength(6);
  });

  it("asks once when several reads arrive together", async () => {
    const { source, fake } = make({ "https://calendar.example.com/work.ics": feed("A"), "https://example.org/home.ics": feed("B") });
    await Promise.all([source.events(DAY.from, DAY.to), source.events(DAY.from, DAY.to)]);
    expect(fake.calls).toHaveLength(2);
  });

  it("keeps the last good copy when a fetch fails, and says why", async () => {
    const { source, fake, clock } = make({ "https://calendar.example.com/work.ics": feed("A"), "https://example.org/home.ics": feed("B") });
    await source.events(DAY.from, DAY.to);
    fake.answers["https://calendar.example.com/work.ics"] = new Error("offline");
    fake.answers["https://example.org/home.ics"] = "<html>Sign in</html>";
    clock.now += CALENDAR_REFRESH_INTERVAL;
    const events = await source.events(DAY.from, DAY.to);
    expect(events.map((event) => event.title).sort()).toEqual(["A", "B"]);
    expect(source.status().map((status) => [status.lastError, status.lastUpdated])).toEqual([
      ["unreachable", utc(2026, 10, 15, 8)],
      ["notACalendar", utc(2026, 10, 15, 8)],
    ]);
  });

  it("serves the cached feed after a restart, without fetching while it is fresh", async () => {
    const store = new InMemoryDocumentStore();
    const first = make({ "https://calendar.example.com/work.ics": feed("A"), "https://example.org/home.ics": feed("B") }, store);
    await first.source.events(DAY.from, DAY.to);
    expect(Object.keys(store.snapshot()).sort()).toEqual(["Calendars/Feeds/home.json", "Calendars/Feeds/work.json"]);
    const cached = JSON.parse(store.snapshot()["Calendars/Feeds/work.json"] ?? "{}") as Record<string, unknown>;
    expect(cached).toMatchObject({ schemaVersion: 1, url: "https://calendar.example.com/work.ics", fetchedAt: "2026-10-15T08:00:00Z" });

    const second = make({}, store, { now: utc(2026, 10, 15, 8, 10) });
    expect((await second.source.events(DAY.from, DAY.to)).map((event) => event.title).sort()).toEqual(["A", "B"]);
    expect(second.fake.calls).toHaveLength(0);

    const offline = make({}, store, { now: utc(2026, 10, 15, 12) });
    expect((await offline.source.events(DAY.from, DAY.to)).map((event) => event.title).sort()).toEqual(["A", "B"]);
    expect(offline.fake.calls).toHaveLength(2);
    expect(offline.source.status().every((status) => status.lastError === "unreachable" && status.hasData)).toBe(true);
  });

  it("ignores a cache written for another address", async () => {
    const store = new InMemoryDocumentStore({
      "Calendars/Feeds/work.json": JSON.stringify({ schemaVersion: 1, url: "https://old.example.com/x.ics", fetchedAt: "2026-10-15T08:00:00Z", text: feed("Old") }),
      "Calendars/Feeds/home.json": "not json",
    });
    const { source } = make({}, store);
    expect(await source.events(DAY.from, DAY.to)).toEqual([]);
    expect(source.status().map((status) => status.hasData)).toEqual([false, false]);
  });

  it("reports an address that isn't a calendar link without fetching it", async () => {
    const fake = fakeFetcher({});
    const source = new IcsCalendarSource({
      subscriptions: [{ ...work, url: "ftp://nope" }],
      fetcher: fake.fetcher,
      store: new InMemoryDocumentStore(),
      now: () => 0,
      timeZone: () => "UTC",
    });
    expect(await source.events(0, 1)).toEqual([]);
    expect(source.status()[0]?.lastError).toBe("invalidAddress");
    expect(fake.calls).toEqual([]);
  });

  it("drops a removed subscription and fetches a changed address", async () => {
    const { source, fake } = make({ "https://calendar.example.com/work.ics": feed("A"), "https://example.org/home.ics": feed("B"), "https://example.org/new.ics": feed("C") });
    await source.events(DAY.from, DAY.to);
    source.setSubscriptions([{ ...home, url: "https://example.org/new.ics" }]);
    expect((await source.events(DAY.from, DAY.to)).map((event) => event.title)).toEqual(["C"]);
    expect(fake.calls).toHaveLength(3);
  });
});

describe("subscription list", () => {
  it("saves and loads the subscriptions as versioned JSON", async () => {
    const store = new InMemoryDocumentStore();
    await saveCalendarSubscriptions(store, [work, home]);
    expect(JSON.parse(store.snapshot()["Calendars/subscriptions.json"] ?? "{}")).toMatchObject({ schemaVersion: 1 });
    expect(await loadCalendarSubscriptions(store)).toEqual([work, home]);
  });

  it("skips entries it can't read and survives a broken file", async () => {
    const store = new InMemoryDocumentStore({
      "Calendars/subscriptions.json": JSON.stringify({ schemaVersion: 1, subscriptions: [{ id: "x" }, { ...work }] }),
    });
    expect(await loadCalendarSubscriptions(store)).toEqual([work]);
    expect(await loadCalendarSubscriptions(new InMemoryDocumentStore({ "Calendars/subscriptions.json": "{" }))).toEqual([]);
    expect(await loadCalendarSubscriptions(new InMemoryDocumentStore())).toEqual([]);
  });
});
