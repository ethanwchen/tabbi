import { addingDays, ankiDayAt } from "../anki/ankiDay";
import { instantOf } from "../calendar/zonedCalendar";
import type { Instant } from "../time";
import { addTokens, type ClaudeTokenUsage, type ClaudeUsageRecord, totalTokens, ZERO_TOKENS } from "./claudeUsageRecord";

/** Usage of one model within a period. */
export interface ClaudeModelUsage {
  model: string;
  tokens: ClaudeTokenUsage;
  messages: number;
}

/** Totals for one period, by model, sorted by total tokens, largest first. */
export interface ClaudeUsagePeriod {
  models: ClaudeModelUsage[];
}

export function periodTokens(period: ClaudeUsagePeriod): ClaudeTokenUsage {
  return period.models.reduce((sum, model) => addTokens(sum, model.tokens), { ...ZERO_TOKENS });
}

export function periodMessages(period: ClaudeUsagePeriod): number {
  return period.models.reduce((sum, model) => sum + model.messages, 0);
}

/** The model that processed the most tokens. */
export function topModel(period: ClaudeUsagePeriod): string | undefined {
  return period.models[0]?.model;
}

/** Port of ClaudeLocalStats: local usage computed from session logs. */
export interface ClaudeLocalStats {
  /** Since local midnight. */
  today: ClaudeUsagePeriod;
  /** Today plus the six calendar days before it. */
  lastSevenDays: ClaudeUsagePeriod;
}

export function emptyLocalStats(): ClaudeLocalStats {
  return { today: { models: [] }, lastSevenDays: { models: [] } };
}

/** Local midnight of the day containing `now` in `timeZone`. */
export function startOfDay(now: Instant, timeZone: string): Instant {
  const day = ankiDayAt(now, timeZone, 0);
  return instantOf({ year: day.year, month: day.month, day: day.day }, timeZone);
}

/** Start of the seven-day window: midnight six days before `now`. */
export function windowStart(now: Instant, timeZone: string): Instant {
  const day = addingDays(ankiDayAt(now, timeZone, 0), -6);
  return instantOf({ year: day.year, month: day.month, day: day.day }, timeZone);
}

/**
 * Aggregates records into today and last-seven-days totals. Records are
 * expected to be unique by message id; records after `now` are ignored.
 */
export function aggregateUsage(records: Iterable<ClaudeUsageRecord>, now: Instant, timeZone: string): ClaudeLocalStats {
  const todayStart = startOfDay(now, timeZone);
  const weekStart = windowStart(now, timeZone);
  const today = new Map<string, ClaudeModelUsage>();
  const week = new Map<string, ClaudeModelUsage>();
  const add = (record: ClaudeUsageRecord, bucket: Map<string, ClaudeModelUsage>) => {
    const entry = bucket.get(record.model) ?? { model: record.model, tokens: { ...ZERO_TOKENS }, messages: 0 };
    bucket.set(record.model, { model: record.model, tokens: addTokens(entry.tokens, record.usage), messages: entry.messages + 1 });
  };
  for (const record of records) {
    if (record.timestamp < weekStart || record.timestamp > now) continue;
    add(record, week);
    if (record.timestamp >= todayStart) add(record, today);
  }
  const period = (bucket: Map<string, ClaudeModelUsage>): ClaudeUsagePeriod => ({
    models: [...bucket.values()].sort((a, b) => {
      const difference = totalTokens(b.tokens) - totalTokens(a.tokens);
      if (difference !== 0) return difference;
      return a.model < b.model ? -1 : a.model > b.model ? 1 : 0;
    }),
  });
  return { today: period(today), lastSevenDays: period(week) };
}
