import { parseAIProviderID, type AIProviderID } from "../ai/aiProviderID";
import { wallTime } from "../calendar/zonedCalendar";
import { documentName, type DocumentStore } from "../persistence/documentStore";
import { isJSONObject, type JSONObject, type JSONValue } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import { parseUUID } from "../planner/uuid";
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

/*
 * The chat file format, after ClaudeAskHistory. Each chat is one document,
 * `Claude Chats/<ID>.json` with the id upper case as `UUID.uuidString`
 * writes it, encoded the way the Mac's history encoder is set up: pretty,
 * sorted keys, dates as ISO 8601 in UTC to the second, optional keys left
 * out when empty.
 */

/**
 * The chat file format. Version 1 is the first. Version 2 records which
 * tool holds the session; every earlier chat was Claude Code's.
 */
export const CLAUDE_ASK_CHAT_SCHEMA = new VersionedJSON(2, [
  {
    version: 2,
    migrate: (chat) => {
      /* Only an absent key counts; an explicit null is left for the reader, as on the Mac. */
      if (typeof chat.sessionID === "string" && chat.sessionProvider === undefined) chat.sessionProvider = "claude-cli";
    },
  },
]);

const ISO_8601 = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|([+-])(\d{2}):?(\d{2}))$/;

/** `instant` as the `.iso8601` strategy writes a Date: whole seconds, UTC, `Z`. */
export function iso8601(instant: Instant): string {
  return new Date(Math.floor(instant) * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** A date as the `.iso8601` strategy reads one (internet date time, no fractional seconds); throws otherwise. */
export function parseISO8601(text: string): Instant {
  const match = ISO_8601.exec(text);
  if (!match) throw new TypeError(`Invalid date ${text}`);
  const [year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0] = match.slice(1, 7).map(Number);
  const utc = Date.UTC(year, month - 1, day, hour, minute, second);
  const check = new Date(utc);
  if (check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day || hour > 23 || minute > 59 || second > 59) {
    throw new TypeError(`Invalid date ${text}`);
  }
  const sign = match[8] === "-" ? -1 : 1;
  const offset = match[8] === undefined ? 0 : sign * (Number(match[9]) * 3600 + Number(match[10]) * 60);
  return utc / 1000 - offset;
}

function requiredString(value: JSONValue | undefined, key: string): string {
  if (typeof value !== "string") throw new TypeError(`Invalid ${key}`);
  return value;
}

function requiredUUID(value: JSONValue | undefined, key: string): string {
  const id = parseUUID(requiredString(value, key));
  if (id === undefined) throw new TypeError(`Invalid ${key}`);
  return id;
}

function requiredInteger(value: JSONValue | undefined, key: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function readAttachment(value: JSONValue): ClaudeAskAttachment {
  if (!isJSONObject(value)) throw new TypeError("Invalid attachment");
  return {
    id: requiredUUID(value.id, "attachment id"),
    pixelWidth: requiredInteger(value.pixelWidth, "pixelWidth"),
    pixelHeight: requiredInteger(value.pixelHeight, "pixelHeight"),
  };
}

function readMessage(value: JSONValue): ClaudeAskChatMessage {
  if (!isJSONObject(value)) throw new TypeError("Invalid message");
  const { role, text, status, attachments } = value;
  if (role !== "user" && role !== "assistant") throw new TypeError("Invalid role");
  if (status !== "streaming" && status !== "complete" && status !== "stopped" && status !== "failed") {
    throw new TypeError("Invalid status");
  }
  /* Absent in files written before attachments existed. */
  if (attachments !== undefined && attachments !== null && !Array.isArray(attachments)) throw new TypeError("Invalid attachments");
  return { role, text: requiredString(text, "text"), status, attachments: (attachments ?? []).map(readAttachment) };
}

/**
 * Reads an upgraded chat document the way ClaudeAskChat's `init(from:)`
 * does: every field is required except `sessionID` (absent or null is
 * none) and `sessionProvider`, where a tool this build doesn't know (from
 * a newer one) only means the session can't be resumed here.
 */
export function readClaudeAskChat(document: JSONObject): ClaudeAskChat {
  const { sessionID, messages } = document;
  if (sessionID !== undefined && sessionID !== null && typeof sessionID !== "string") throw new TypeError("Invalid sessionID");
  if (!Array.isArray(messages)) throw new TypeError("Invalid messages");
  const chat: ClaudeAskChat = {
    id: requiredUUID(document.id, "id"),
    createdAt: parseISO8601(requiredString(document.createdAt, "createdAt")),
    updatedAt: parseISO8601(requiredString(document.updatedAt, "updatedAt")),
    messages: messages.map(readMessage),
  };
  if (typeof sessionID === "string") chat.sessionID = sessionID;
  const provider = parseAIProviderID(document.sessionProvider);
  if (provider !== undefined) chat.sessionProvider = provider;
  return chat;
}

/** A chat file's chat, after the migrations its version hasn't had. Throws when it can't be read. */
export function decodeClaudeAskChat(text: string): ClaudeAskChat {
  return CLAUDE_ASK_CHAT_SCHEMA.decode(text, readClaudeAskChat);
}

/** The chat file the Mac writes for `chat`. Throws when an id isn't a UUID, which the Mac's types rule out. */
export function encodeClaudeAskChat(chat: ClaudeAskChat): string {
  const document: JSONObject = {
    id: requiredUUID(chat.id, "id"),
    createdAt: iso8601(chat.createdAt),
    updatedAt: iso8601(chat.updatedAt),
    messages: chat.messages.map((message) => {
      const encoded: JSONObject = { role: message.role, text: message.text, status: message.status };
      if (message.attachments.length > 0) {
        encoded.attachments = message.attachments.map((attachment) => ({
          id: requiredUUID(attachment.id, "attachment id"),
          pixelWidth: attachment.pixelWidth,
          pixelHeight: attachment.pixelHeight,
        }));
      }
      return encoded;
    }),
  };
  if (chat.sessionID !== undefined) document.sessionID = chat.sessionID;
  if (chat.sessionProvider !== undefined) document.sessionProvider = chat.sessionProvider;
  return CLAUDE_ASK_CHAT_SCHEMA.encode(document, { pretty: true, sortedKeys: true });
}

/**
 * Port of ClaudeAskHistory: the saved chats, one document per chat in the
 * edition's `Claude Chats` folder, with each chat's screenshots in a `<ID>`
 * folder beside it. A damaged chat is skipped when listing, so one bad
 * file never hides the rest; loading it alone rejects, so it is never
 * overwritten by mistake.
 */
export class ClaudeAskHistory {
  static readonly folderName = "Claude Chats";
  static readonly schema = CLAUDE_ASK_CHAT_SCHEMA;

  constructor(
    private readonly store: DocumentStore,
    readonly folder: string = ClaudeAskHistory.folderName,
  ) {}

  /** The chat's document name, `Claude Chats/<ID>.json`. */
  documentName(id: string): string {
    return documentName(this.folder, `${parseUUID(id) ?? id}.json`);
  }

  /** Where a chat's screenshots are kept once it is saved. */
  attachmentsFolder(id: string): string {
    return documentName(this.folder, parseUUID(id) ?? id);
  }

  /** Every readable saved chat, the most recently answered first. */
  async chats(): Promise<ClaudeAskChat[]> {
    const ids = (await this.store.list(this.folder)).flatMap((name) => {
      const id = name.endsWith(".json") ? parseUUID(name.slice(0, -5)) : undefined;
      return id === undefined ? [] : [id];
    });
    const loaded = await Promise.all(ids.map((id) => this.load(id).catch(() => undefined)));
    return loaded.filter((chat): chat is ClaudeAskChat => chat !== undefined).sort(compareChats);
  }

  /** The saved chat, or undefined when none exists. Rejects when the document is damaged. */
  async load(id: string): Promise<ClaudeAskChat | undefined> {
    const text = await this.store.read(this.documentName(id));
    if (text === undefined) return undefined;
    const chat = decodeClaudeAskChat(text);
    /* The file name is authoritative, so a copied file can't shadow another chat. */
    chat.id = parseUUID(id) ?? id;
    return chat;
  }

  async save(chat: ClaudeAskChat): Promise<void> {
    await this.store.write(this.documentName(chat.id), encodeClaudeAskChat(chat));
  }

  /** Removes one chat and its screenshots. Removing a chat that isn't saved is not an error. */
  async delete(id: string): Promise<void> {
    await this.store.remove(this.documentName(id));
    await this.removeFolder(this.attachmentsFolder(id));
  }

  /** Removes every chat document, readable or not, and every chat's screenshots, leaving unrelated files alone. */
  async deleteAll(): Promise<void> {
    for (const name of await this.store.list(this.folder)) {
      if (!name.endsWith(".json") || parseUUID(name.slice(0, -5)) === undefined) continue;
      await this.delete(name.slice(0, -5));
    }
  }

  private async removeFolder(folder: string): Promise<void> {
    for (const name of await this.store.list(folder)) await this.store.remove(documentName(folder, name));
  }
}
