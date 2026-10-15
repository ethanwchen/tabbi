import type { AIProviderID } from "../ai/aiProviderID";
import { wallTime } from "../calendar/zonedCalendar";
import type { Instant } from "../time";
import type { ClaudeAskAttachment } from "./claudeAskAttachment";
import { type ClaudeAskRole, type ClaudeAskStatus, demoConversation, summarize } from "./claudeAskConversation";

/** One message of a saved chat. */
export interface ClaudeAskChatMessage {
  role: ClaudeAskRole;
  text: string;
  status: ClaudeAskStatus;
  /** Screenshots sent with a question; empty on answers. */
  attachments: ClaudeAskAttachment[];
}

/**
 * Port of ClaudeAskChat: an Ask chat as the history keeps it. Only finished
 * exchanges are stored (`ClaudeAskConversation.savedChat`), so a restored
 * chat reads like the one the user left.
 */
export interface ClaudeAskChat {
  id: string;
  createdAt: Instant;
  /** When the last answer arrived; the history lists newest first by this. */
  updatedAt: Instant;
  /** The CLI session the chat continues with `--resume`, if it had one. */
  sessionID?: string;
  /** The command line tool that holds `sessionID`. */
  sessionProvider?: AIProviderID;
  messages: ClaudeAskChatMessage[];
}

export const CHAT_TITLE_LIMIT = 60;

/** The first question on one line, short enough for a history row. */
export function chatTitle(chat: ClaudeAskChat): string {
  const question = chat.messages.find((message) => message.role === "user")?.text;
  const oneLine = question?.split(/\s+/u).filter((word) => word.length > 0).join(" ");
  return summarize(oneLine, CHAT_TITLE_LIMIT) ?? "Untitled chat";
}

/** Every screenshot in the chat, in message order. */
export function chatAttachments(chat: ClaudeAskChat): ClaudeAskAttachment[] {
  return chat.messages.flatMap((message) => message.attachments);
}

/** Newest answered first, ties by id, as the history lists them. */
export function compareChats(a: ClaudeAskChat, b: ClaudeAskChat): number {
  if (a.updatedAt !== b.updatedAt) return b.updatedAt - a.updatedAt;
  return a.id < b.id ? 1 : a.id > b.id ? -1 : 0;
}

function dayNumber(instant: Instant, timeZone: string): number {
  const parts = wallTime(instant, timeZone);
  return Date.UTC(parts.year, parts.month - 1, parts.day) / 86_400_000;
}

/**
 * When the chat was last answered, as a history row shows it: the time
 * today, "Yesterday", the weekday within the past week, then the date (with
 * the year once it is another year).
 */
export function chatDateLabel(chat: ClaudeAskChat, now: Instant, timeZone: string, locale = "en-US"): string {
  const daysAgo = dayNumber(now, timeZone) - dayNumber(chat.updatedAt, timeZone);
  let options: Intl.DateTimeFormatOptions;
  if (daysAgo < 1) {
    options = { hour: "numeric", minute: "2-digit" };
  } else if (daysAgo === 1) {
    return "Yesterday";
  } else if (daysAgo < 7) {
    options = { weekday: "long" };
  } else {
    const sameYear = wallTime(chat.updatedAt, timeZone).year === wallTime(now, timeZone).year;
    options = sameYear ? { month: "short", day: "numeric" } : { year: "numeric", month: "short", day: "numeric" };
  }
  return new Intl.DateTimeFormat(locale, { ...options, timeZone }).format(new Date(chat.updatedAt * 1000));
}

/**
 * Sample saved chats for demo runs, newest first. The first is the demo
 * conversation, which the panel opens on launch. With `screenshot`, the
 * second is a question asked about it, so the demo shows a sent thumbnail.
 * `newID` makes each chat's id (the core never generates randomness).
 */
export function demoHistory(now: Instant, newID: () => string, screenshot?: ClaudeAskAttachment): ClaudeAskChat[] {
  const hour = 3600;
  const chat = (question: string, answer: string, hoursAgo: number, session: string): ClaudeAskChat => {
    const date = now - hoursAgo * hour;
    return {
      id: newID(),
      createdAt: date,
      updatedAt: date,
      sessionID: session,
      messages: [
        { role: "user", text: question, status: "complete", attachments: [] },
        { role: "assistant", text: answer, status: "complete", attachments: [] },
      ],
    };
  };
  const current = demoConversation(newID(), now - 0.2 * hour).savedChat(now - 0.2 * hour);
  const withScreenshot = screenshot ? demoScreenshotChat(screenshot, now - 1.5 * hour, newID()) : undefined;
  return [
    ...(current ? [current] : []),
    ...(withScreenshot ? [withScreenshot] : []),
    chat(
      "Explain the difference between a mutex and a semaphore",
      "A **mutex** lets one thread in at a time and is released by the thread that took it. " +
        "A **semaphore** counts, so up to *n* threads can hold it.",
      5,
      "demo-session-2",
    ),
    chat(
      "Write a polite reminder about the overdue invoice",
      "Hi Sam, a quick reminder that invoice 1042 was due last Friday. Could you take a look this week?",
      28,
      "demo-session-3",
    ),
    chat(
      "Quick dinner ideas with chickpeas and spinach",
      "- Chickpea and spinach curry\n- Crispy chickpeas over garlicky spinach\n- A warm salad with feta",
      80,
      "demo-session-4",
    ),
    chat(
      "Summarize the main ideas of spaced repetition",
      "Review just before you would forget, and stretch the gap each time you remember.",
      24 * 12,
      "demo-session-5",
    ),
  ];
}

/** A sample chat whose question carries `screenshot`, for demo runs, which never record the real screen. */
export function demoScreenshotChat(screenshot: ClaudeAskAttachment, date: Instant, id: string): ClaudeAskChat {
  return {
    id,
    createdAt: date,
    updatedAt: date,
    sessionID: "demo-session-screenshot",
    messages: [
      { role: "user", text: "How can I make this page easier to read?", status: "complete", attachments: [screenshot] },
      {
        role: "assistant",
        text: "Shorten the lines to about **70 characters** and darken the grey text.",
        status: "complete",
        attachments: [],
      },
    ],
  };
}
