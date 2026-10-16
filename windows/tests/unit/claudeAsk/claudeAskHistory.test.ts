import { describe, expect, it } from "vitest";
import {
  ClaudeAskHistory,
  CLAUDE_ASK_CHAT_SCHEMA,
  decodeClaudeAskChat,
  encodeClaudeAskChat,
  iso8601,
  parseISO8601,
  type ClaudeAskChat,
} from "../../../src/core/claudeAsk/claudeAskChat";
import { ClaudeAskConversation } from "../../../src/core/claudeAsk/claudeAskConversation";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { sampleUUID } from "../../../src/core/planner/uuid";

/* Port of ClaudeAskHistoryTests (the on-disk half) plus the exact file shape and each migration. */

/** 2027-01-15 08:00:00 UTC. */
const start = 1_800_000_000;
let next = 0;
const newID = () => sampleUUID(++next);

function answered(conversation: ClaudeAskConversation, prompt: string, answer: string, session: string | undefined = "s1"): void {
  conversation.begin(prompt);
  conversation.applyClaude({ type: "result", result: { text: answer, ...(session === undefined ? {} : { sessionID: session }), isError: false } });
}

function savedChat(conversation: ClaudeAskConversation, updatedAt: number): ClaudeAskChat {
  const chat = conversation.savedChat(updatedAt);
  if (!chat) throw new Error("Nothing to save");
  return chat;
}

function setUp(): { store: InMemoryDocumentStore; history: ClaudeAskHistory } {
  const store = new InMemoryDocumentStore();
  return { store, history: new ClaudeAskHistory(store) };
}

const sample: ClaudeAskChat = {
  id: "6f9619ff-8b86-4d01-b42d-00cf4fc964ff",
  createdAt: start,
  updatedAt: start + 60.75,
  sessionID: "s1",
  sessionProvider: "claude-cli",
  messages: [
    {
      role: "user",
      text: "Is 1/2 bigger?",
      status: "complete",
      attachments: [{ id: "A1B2C3D4-0000-4000-8000-000000000001", pixelWidth: 800, pixelHeight: 600 }],
    },
    { role: "assistant", text: "Yes.", status: "complete", attachments: [] },
  ],
};

/* What the Mac's history encoder (pretty, sorted keys, ISO 8601 dates) writes for `sample`. */
const sampleFile = `{
  "createdAt" : "2027-01-15T08:00:00Z",
  "id" : "6F9619FF-8B86-4D01-B42D-00CF4FC964FF",
  "messages" : [
    {
      "attachments" : [
        {
          "id" : "A1B2C3D4-0000-4000-8000-000000000001",
          "pixelHeight" : 600,
          "pixelWidth" : 800
        }
      ],
      "role" : "user",
      "status" : "complete",
      "text" : "Is 1\\/2 bigger?"
    },
    {
      "role" : "assistant",
      "status" : "complete",
      "text" : "Yes."
    }
  ],
  "schemaVersion" : 2,
  "sessionID" : "s1",
  "sessionProvider" : "claude-cli",
  "updatedAt" : "2027-01-15T08:01:00Z"
}`;

describe("ClaudeAskHistory file format", () => {
  it("writes exactly what the Mac writes", async () => {
    expect(encodeClaudeAskChat(sample)).toBe(sampleFile);
    const { store, history } = setUp();
    await history.save(sample);
    expect(store.snapshot()).toEqual({ "Claude Chats/6F9619FF-8B86-4D01-B42D-00CF4FC964FF.json": sampleFile });
  });

  it("reads the Mac's file back, dates to the second", () => {
    expect(decodeClaudeAskChat(sampleFile)).toEqual({ ...sample, id: "6F9619FF-8B86-4D01-B42D-00CF4FC964FF", updatedAt: start + 60 });
  });

  it("leaves out a missing session and empty attachments", () => {
    const text = encodeClaudeAskChat({
      id: sampleUUID(1),
      createdAt: start,
      updatedAt: start,
      messages: [{ role: "assistant", text: "Yes.", status: "complete", attachments: [] }],
    });
    expect(JSON.parse(text)).toEqual({
      createdAt: "2027-01-15T08:00:00Z",
      id: sampleUUID(1),
      messages: [{ role: "assistant", status: "complete", text: "Yes." }],
      schemaVersion: 2,
      updatedAt: "2027-01-15T08:00:00Z",
    });
  });

  it("reads and writes dates like the iso8601 strategy", () => {
    expect(iso8601(start)).toBe("2027-01-15T08:00:00Z");
    expect(iso8601(start + 0.999)).toBe("2027-01-15T08:00:00Z");
    expect(parseISO8601("2027-01-15T08:00:00Z")).toBe(start);
    expect(parseISO8601("2027-01-15T10:00:00+02:00")).toBe(start);
    expect(parseISO8601("2027-01-15T03:00:00-0500")).toBe(start);
    for (const bad of ["2027-01-15T08:00:00.5Z", "2027-01-15 08:00:00Z", "2027-02-30T08:00:00Z", "2027-01-15T08:00:00", "yesterday"]) {
      expect(() => parseISO8601(bad), bad).toThrow();
    }
  });

  it("has the Mac's schema", () => {
    expect(ClaudeAskHistory.schema.current).toBe(2);
    expect(CLAUDE_ASK_CHAT_SCHEMA.migrations.map((step) => step.version)).toEqual([2]);
    expect(ClaudeAskHistory.folderName).toBe("Claude Chats");
  });
});

describe("ClaudeAskHistory migrations", () => {
  const legacy = (version: string, session: string) => `{${version}"id":"${sampleUUID(7)}","createdAt":"2027-01-15T08:00:00Z",
    "updatedAt":"2027-01-15T08:01:00Z",${session}
    "messages":[{"role":"user","text":"hi","status":"complete"},{"role":"assistant","text":"hello","status":"complete"}]}`;

  it("loads a version 0 document", async () => {
    const id = sampleUUID(7);
    const history = new ClaudeAskHistory(new InMemoryDocumentStore({ [`Claude Chats/${id}.json`]: legacy("", "") }));
    const chat = await history.load(id);
    expect(chat?.sessionID).toBeUndefined();
    expect(chat?.sessionProvider).toBeUndefined();
    expect(chat?.messages.map((m) => m.attachments)).toEqual([[], []]);
    expect(chat?.createdAt).toBe(start);
    expect(chat?.updatedAt).toBe(start + 60);
  });

  it("gives a version 0 or 1 chat with a session to Claude Code", () => {
    for (const version of ["", `"schemaVersion":1,`]) {
      expect(decodeClaudeAskChat(legacy(version, `"sessionID":"s1",`)).sessionProvider, version).toBe("claude-cli");
      expect(decodeClaudeAskChat(legacy(version, "")).sessionProvider, version).toBeUndefined();
    }
  });

  it("runs the version 2 step only on the raw document, and only when the key is absent", () => {
    const upgraded = CLAUDE_ASK_CHAT_SCHEMA.upgrade(legacy(`"schemaVersion":1,`, `"sessionID":"s1",`));
    expect(upgraded.sessionProvider).toBe("claude-cli");
    expect(upgraded.schemaVersion).toBe(2);
    const explicitNull = CLAUDE_ASK_CHAT_SCHEMA.upgrade(legacy(`"schemaVersion":1,`, `"sessionID":"s1","sessionProvider":null,`));
    expect(explicitNull.sessionProvider).toBeNull();
    const kept = CLAUDE_ASK_CHAT_SCHEMA.upgrade(legacy(`"schemaVersion":1,`, `"sessionID":"s1","sessionProvider":"codex-cli",`));
    expect(kept.sessionProvider).toBe("codex-cli");
    const notString = CLAUDE_ASK_CHAT_SCHEMA.upgrade(legacy("", `"sessionID":7,`));
    expect(notString.sessionProvider).toBeUndefined();
  });

  it("does not migrate a version 2 document", () => {
    expect(decodeClaudeAskChat(legacy(`"schemaVersion":2,`, `"sessionID":"s1",`)).sessionProvider).toBeUndefined();
  });

  it("only loses the session's tool when it comes from a newer build", () => {
    const chat = decodeClaudeAskChat(legacy(`"schemaVersion":2,`, `"sessionID":"s1","sessionProvider":"future-cli",`));
    expect(chat.sessionID).toBe("s1");
    expect(chat.sessionProvider).toBeUndefined();
    expect(ClaudeAskConversation.restoring(chat).sessionProvider).toBeUndefined();
    expect(decodeClaudeAskChat(legacy(`"schemaVersion":2,`, `"sessionID":"s1","sessionProvider":3,`)).sessionProvider).toBeUndefined();
  });
});

describe("ClaudeAskHistory damaged documents", () => {
  const good = JSON.parse(sampleFile) as Record<string, unknown>;
  const variant = (changes: Record<string, unknown>) => JSON.stringify({ ...good, ...changes });

  it("rejects what the Mac's decoder rejects", () => {
    const damaged = [
      "not json",
      "[1]",
      variant({ id: "not-a-uuid" }),
      variant({ id: undefined }),
      variant({ createdAt: 1_800_000_000 }),
      variant({ updatedAt: "2027-01-15T08:01:00.250Z" }),
      variant({ sessionID: 4 }),
      variant({ messages: undefined }),
      variant({ messages: [{ role: "robot", text: "x", status: "complete" }] }),
      variant({ messages: [{ role: "user", text: "x", status: "done" }] }),
      variant({ messages: [{ role: "user", status: "complete" }] }),
      variant({ messages: [{ role: "user", text: "x", status: "complete", attachments: [{ id: sampleUUID(1), pixelWidth: 1.5, pixelHeight: 2 }] }] }),
      variant({ messages: [{ role: "user", text: "x", status: "complete", attachments: {} }] }),
    ];
    for (const text of damaged) expect(() => decodeClaudeAskChat(text), text).toThrow();
  });

  it("reads null as none where the Mac decodes an optional", () => {
    const chat = decodeClaudeAskChat(variant({ sessionID: null, sessionProvider: null, messages: [{ role: "user", text: "x", status: "complete", attachments: null }] }));
    expect(chat.sessionID).toBeUndefined();
    expect(chat.sessionProvider).toBeUndefined();
    expect(chat.messages[0]?.attachments).toEqual([]);
  });

  it("rejects loading a damaged chat but skips it when listing, and deleteAll still removes it", async () => {
    const { store, history } = setUp();
    const conversation = new ClaudeAskConversation(newID(), start);
    answered(conversation, "kept", "yes");
    const chat = savedChat(conversation, start);
    await history.save(chat);
    const text = await store.read(history.documentName(chat.id));
    expect(VersionedJSON.version(text ?? "")).toBe(ClaudeAskHistory.schema.current);

    const corruptID = newID();
    await store.write(history.documentName(corruptID), "not json");
    await store.write("Claude Chats/notes.txt", "keep");
    await expect(history.load(corruptID)).rejects.toThrow();
    expect(await history.chats()).toEqual([chat]);

    await history.deleteAll();
    expect(await history.chats()).toEqual([]);
    expect(store.snapshot()).toEqual({ "Claude Chats/notes.txt": "keep" });
  });
});

describe("ClaudeAskHistory over a document store", () => {
  it("saves, lists, loads and deletes", async () => {
    const { store, history } = setUp();
    expect(await history.chats()).toEqual([]);
    const older = new ClaudeAskConversation(newID(), start);
    answered(older, "older", "1");
    const newer = new ClaudeAskConversation(newID(), start);
    answered(newer, "newer", "2", undefined);
    const olderChat = savedChat(older, start + 5);
    const newerChat = savedChat(newer, start + 50);
    await history.save(olderChat);
    await history.save(newerChat);
    await store.write(`${history.attachmentsFolder(olderChat.id)}/${sampleUUID(99)}.png`, "png");

    expect(await history.chats()).toEqual([newerChat, olderChat]);
    expect(await history.load(olderChat.id)).toEqual(olderChat);

    await history.delete(olderChat.id);
    await history.delete(olderChat.id);
    expect(await history.chats()).toEqual([newerChat]);
    expect(await history.load(olderChat.id)).toBeUndefined();
    expect(Object.keys(store.snapshot())).toEqual([history.documentName(newerChat.id)]);
  });

  it("replaces a chat saved again", async () => {
    const { history } = setUp();
    const conversation = new ClaudeAskConversation(newID(), start);
    answered(conversation, "one", "1");
    await history.save(savedChat(conversation, start));
    answered(conversation, "two", "2");
    await history.save(savedChat(conversation, start + 1));
    expect((await history.chats()).map((chat) => chat.messages.length)).toEqual([4]);
  });

  it("takes the chat's id from its document name", async () => {
    const { store, history } = setUp();
    const conversation = new ClaudeAskConversation(newID(), start);
    answered(conversation, "copied", "yes");
    const chat = savedChat(conversation, start);
    await history.save(chat);
    const copyID = newID();
    await store.write(history.documentName(copyID), (await store.read(history.documentName(chat.id))) ?? "");
    expect((await history.load(copyID))?.id).toBe(copyID);
    expect(new Set((await history.chats()).map((saved) => saved.id))).toEqual(new Set([chat.id, copyID]));
  });

  it("refuses to save a chat whose id is not a UUID", async () => {
    const { history } = setUp();
    await expect(history.save({ ...sample, id: "chat-1" })).rejects.toThrow();
  });
});
