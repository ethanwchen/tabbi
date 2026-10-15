import type { Instant, Seconds } from "../time";
import { formatISODate, parseISODate } from "../activity/isoDate";
import type { DocumentStore } from "../persistence/documentStore";
import { isJSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import type { EventColor, UpcomingEvent } from "../planner/upcomingEvent";
import { eventsInRange, parseICS, type IcsCalendar } from "./ics";

/**
 * Where Today and the Schedule read calendar events on Windows, which has
 * no EventKit: subscribed ICS feeds, or demo data. Both read the same way,
 * so the panels never know which one they have.
 */
export interface CalendarSource {
  /** Events touching `[from, to)`, sorted by start. Never rejects; a feed that fails keeps its last good copy. */
  events(from: Instant, to: Instant): Promise<UpcomingEvent[]>;
  /** Fetches every feed again now, whatever the refresh interval says. */
  reload(): Promise<void>;
  /** How each feed is doing, for the empty and error states. */
  status(): CalendarFeedStatus[];
}

/** One subscribed calendar: a feed URL with the name and color the user gave it. */
export interface CalendarSubscription {
  /** Stable and file-name safe; it prefixes event ids and names the cache file. */
  readonly id: string;
  readonly name: string;
  readonly url: string;
  readonly color: EventColor;
}

/**
 * Why a feed has no fresh copy, for the UI to word: the address is not a
 * calendar link, the server could not be reached (or answered with an
 * error), or it answered with something other than iCalendar.
 */
export type CalendarFeedError = "invalidAddress" | "unreachable" | "notACalendar";

export interface CalendarFeedStatus {
  readonly subscriptionID: string;
  readonly name: string;
  /** When the copy in use was fetched; undefined before the first good fetch. */
  readonly lastUpdated?: Instant;
  /** Why the last fetch failed; undefined after a good one. */
  readonly lastError?: CalendarFeedError;
  readonly hasData: boolean;
}

/** Fetches a feed's text, the host's `httpFetchCalendar`. Rejects on network or HTTP errors. */
export type CalendarFetcher = (url: string) => Promise<string>;

/** How long a fetched feed is used before asking again; calendars change slowly and publishers rate-limit. */
export const CALENDAR_REFRESH_INTERVAL: Seconds = 15 * 60;

/** The edition storage folder for calendar subscriptions and cached feeds. */
export const CALENDAR_FOLDER = "Calendars";
const FEED_FOLDER = `${CALENDAR_FOLDER}/Feeds`;
const SUBSCRIPTIONS_DOCUMENT = `${CALENDAR_FOLDER}/subscriptions.json`;

/** The cached feed format. Version 1 is the first. */
export const calendarFeedSchema = new VersionedJSON(1);
/** The subscription list format. Version 1 is the first. */
export const calendarSubscriptionsSchema = new VersionedJSON(1);

/**
 * The https URL to fetch for a feed address: `webcal://` and `webcals://`
 * (how Google, Outlook and iCloud hand out subscription links) become
 * `https://`; plain `http(s)` stays. Undefined for anything else.
 */
export function feedURL(address: string): string | undefined {
  const trimmed = address.trim();
  const rewritten = trimmed.replace(/^webcals?:\/\//i, "https://");
  let url: URL;
  try {
    url = new URL(rewritten);
  } catch {
    return undefined;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return undefined;
  if (url.hostname === "") return undefined;
  return rewritten;
}

/** A subscription id made safe for a file name. */
export function safeSubscriptionID(id: string): string {
  const cleaned = id.replace(/[^A-Za-z0-9_-]/g, "-").slice(0, 64);
  return cleaned === "" ? "calendar" : cleaned;
}

function isColor(value: unknown): value is EventColor {
  if (!isJSONObject(value)) return false;
  return ["red", "green", "blue"].every((key) => typeof value[key] === "number");
}

/** The saved subscriptions; empty when none are saved or the file can't be read. */
export async function loadCalendarSubscriptions(store: DocumentStore): Promise<CalendarSubscription[]> {
  try {
    const text = await store.read(SUBSCRIPTIONS_DOCUMENT);
    if (text === undefined) return [];
    return calendarSubscriptionsSchema.decode(text, (document) => {
      const list = Array.isArray(document.subscriptions) ? document.subscriptions : [];
      return list.flatMap((entry): CalendarSubscription[] => {
        if (!isJSONObject(entry)) return [];
        const { id, name, url, color } = entry;
        if (typeof id !== "string" || typeof name !== "string" || typeof url !== "string" || !isColor(color)) return [];
        return [{ id, name, url, color: { red: color.red, green: color.green, blue: color.blue } }];
      });
    });
  } catch {
    return [];
  }
}

export async function saveCalendarSubscriptions(store: DocumentStore, subscriptions: readonly CalendarSubscription[]): Promise<void> {
  const list = subscriptions.map((entry) => ({
    id: entry.id,
    name: entry.name,
    url: entry.url,
    color: { red: entry.color.red, green: entry.color.green, blue: entry.color.blue },
  }));
  await store.write(SUBSCRIPTIONS_DOCUMENT, calendarSubscriptionsSchema.encode({ subscriptions: list }, { pretty: true, sortedKeys: true }));
}

interface FeedState {
  url: string;
  calendar?: IcsCalendar;
  fetchedAt?: Instant;
  lastAttempt?: Instant;
  lastError?: CalendarFeedError;
  cacheRead: boolean;
  inFlight?: Promise<void>;
}

export interface IcsCalendarSourceOptions {
  readonly subscriptions: readonly CalendarSubscription[];
  readonly fetcher: CalendarFetcher;
  /** Where the last good copy of each feed is kept, so a launch offline still shows the calendar. */
  readonly store: DocumentStore;
  readonly now: () => Instant;
  /** The user's IANA zone, read on every call so a zone change takes effect. */
  readonly timeZone: () => string;
  readonly refreshInterval?: Seconds;
}

/**
 * Port target of the Mac's EventKit reads: events from subscribed ICS
 * feeds. Each feed is fetched at most once per refresh interval (failures
 * count, so a broken feed isn't hammered), and its last good text is
 * cached through the DocumentStore and served while a fetch fails.
 */
export class IcsCalendarSource implements CalendarSource {
  private subscriptions: CalendarSubscription[];
  private readonly feeds = new Map<string, FeedState>();
  private readonly refreshInterval: Seconds;

  constructor(private readonly options: IcsCalendarSourceOptions) {
    this.subscriptions = [...options.subscriptions];
    this.refreshInterval = options.refreshInterval ?? CALENDAR_REFRESH_INTERVAL;
  }

  /** Replaces the subscribed calendars; a feed whose URL changed is fetched again. */
  setSubscriptions(subscriptions: readonly CalendarSubscription[]): void {
    this.subscriptions = [...subscriptions];
    const ids = new Set(subscriptions.map((entry) => safeSubscriptionID(entry.id)));
    for (const id of [...this.feeds.keys()]) if (!ids.has(id)) this.feeds.delete(id);
  }

  async events(from: Instant, to: Instant): Promise<UpcomingEvent[]> {
    await Promise.all(this.subscriptions.map((entry) => this.refresh(entry, false)));
    const timeZone = this.options.timeZone();
    const events: UpcomingEvent[] = [];
    for (const entry of this.subscriptions) {
      const calendar = this.feeds.get(safeSubscriptionID(entry.id))?.calendar;
      if (calendar === undefined) continue;
      events.push(...eventsInRange(calendar, { from, to, timeZone, calendarColor: entry.color, idPrefix: safeSubscriptionID(entry.id) }));
    }
    return events.sort((a, b) => a.start - b.start || a.end - b.end || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  }

  async reload(): Promise<void> {
    await Promise.all(this.subscriptions.map((entry) => this.refresh(entry, true)));
  }

  status(): CalendarFeedStatus[] {
    return this.subscriptions.map((entry) => {
      const feed = this.feeds.get(safeSubscriptionID(entry.id));
      const status: { -readonly [Key in keyof CalendarFeedStatus]: CalendarFeedStatus[Key] } = {
        subscriptionID: entry.id,
        name: entry.name,
        hasData: feed?.calendar !== undefined,
      };
      if (feed?.fetchedAt !== undefined) status.lastUpdated = feed.fetchedAt;
      if (feed?.lastError !== undefined) status.lastError = feed.lastError;
      return status;
    });
  }

  private state(entry: CalendarSubscription): FeedState | undefined {
    const url = feedURL(entry.url);
    if (url === undefined) return undefined;
    const id = safeSubscriptionID(entry.id);
    let feed = this.feeds.get(id);
    if (feed === undefined || feed.url !== url) {
      feed = { url, cacheRead: false };
      this.feeds.set(id, feed);
    }
    return feed;
  }

  private refresh(entry: CalendarSubscription, force: boolean): Promise<void> {
    const feed = this.state(entry);
    if (feed === undefined) {
      const id = safeSubscriptionID(entry.id);
      this.feeds.set(id, { url: entry.url, cacheRead: true, lastError: "invalidAddress" });
      return Promise.resolve();
    }
    if (feed.inFlight !== undefined) return feed.inFlight;
    const run = async () => {
      if (!feed.cacheRead) {
        feed.cacheRead = true;
        await this.readCache(entry, feed);
      }
      const now = this.options.now();
      const fresh = feed.lastAttempt !== undefined && now - feed.lastAttempt < this.refreshInterval && now >= feed.lastAttempt;
      if (fresh && !force) return;
      feed.lastAttempt = now;
      try {
        const text = await this.options.fetcher(feed.url);
        if (!/BEGIN:VCALENDAR/i.test(text)) throw new Error("not a calendar");
        feed.calendar = parseICS(text);
        feed.fetchedAt = now;
        delete feed.lastError;
        await this.writeCache(entry, feed.url, now, text);
      } catch (error) {
        feed.lastError =
          error instanceof Error && error.message === "not a calendar"
            ? "notACalendar"
            : "unreachable";
      }
    };
    feed.inFlight = run().finally(() => {
      delete feed.inFlight;
    });
    return feed.inFlight;
  }

  private document(entry: CalendarSubscription): string {
    return `${FEED_FOLDER}/${safeSubscriptionID(entry.id)}.json`;
  }

  private async readCache(entry: CalendarSubscription, feed: FeedState): Promise<void> {
    try {
      const text = await this.options.store.read(this.document(entry));
      if (text === undefined) return;
      const cached = calendarFeedSchema.decode(text, (document) => document);
      const fetchedAt = typeof cached.fetchedAt === "string" ? parseISODate(cached.fetchedAt) : undefined;
      if (cached.url !== feed.url || typeof cached.text !== "string" || fetchedAt === undefined) return;
      feed.calendar = parseICS(cached.text);
      feed.fetchedAt = fetchedAt;
      /* A copy younger than the interval is used as it is, without fetching. */
      feed.lastAttempt = fetchedAt;
    } catch {
      /* An unreadable cache is ignored; the next fetch replaces it. */
    }
  }

  private async writeCache(entry: CalendarSubscription, url: string, fetchedAt: Instant, text: string): Promise<void> {
    try {
      await this.options.store.write(
        this.document(entry),
        calendarFeedSchema.encode({ url, fetchedAt: formatISODate(fetchedAt), text }, { pretty: true, sortedKeys: true }),
      );
    } catch {
      /* The feed still shows this session; the cache is a convenience. */
    }
  }
}
