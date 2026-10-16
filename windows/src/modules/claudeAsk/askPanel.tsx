/*
 * Port of ClaudeAskPanel: a small chat with the AI the user picked, named in
 * the copy. Messages fill the panel and a question field sits at the
 * bottom; the saved chats list, the empty chat and the setup screen take the
 * messages' place. The large chat view and screenshots are not on Windows
 * yet, so the Expand and Attach controls are left out.
 */

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { assistantName, displayName } from "../../core/ai/aiProviderID";
import { chatDateLabel, chatTitle, type ClaudeAskChat } from "../../core/claudeAsk/claudeAskChat";
import {
  failureDetail,
  failureNeedsSetup,
  failureSetupAction,
  failureSetupTitle,
  failureTitle,
  type ClaudeAskFailure,
  type ClaudeAskMessage,
} from "../../core/claudeAsk/claudeAskConversation";
import { inlineRuns } from "../../core/claudeAsk/claudeAskInline";
import { markdownBlocks, simplifyBlocks } from "../../core/claudeAsk/claudeAskMarkdown";
import { currentLanguage, tr } from "../../core/localization/tr";
import { Card } from "../../ui/kit/Card";
import { useKit } from "../../ui/kit/context";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { PawLoader } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Pill } from "../../ui/kit/Pill";
import { StatusMessage } from "../../ui/kit/StatusMessage";
import { useTactile } from "../../ui/kit/tactile";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { ClaudeAskSession } from "./askSession";
import "./claudeAsk.css";

export interface AskPanelProps {
  readonly session: ClaudeAskSession;
  readonly context: ModuleContext;
}

/** The most lines the field grows to before it scrolls (the Mac's 3 in the notch). */
const MAX_FIELD_LINES = 3;
const FIELD_LINE_HEIGHT = 16;

export function AskPanel({ session, context }: AskPanelProps) {
  const state = useStore(session);
  const { still } = useKit();
  const [draft, setDraft] = useState("");
  const openConnections = useCallback(() => void context.host.openSettings("connections"), [context]);

  /* The panel looks at the setup again each time it opens. */
  useEffect(() => session.prepare(), [session]);

  const send = (prompt: string) => {
    if (state.isStreaming || prompt.trim().length === 0) return;
    session.ask(prompt);
    setDraft("");
  };

  const showsSetup = state.setupNeeded !== undefined && state.isEmpty;
  const canSend = draft.trim().length > 0 && !state.isStreaming;

  let content: ReactNode;
  if (state.isShowingHistory) content = <HistoryList session={session} context={context} />;
  else if (state.isEmpty) content = <EmptyChatView assistant={state.assistant} onPick={send} />;
  else content = <MessageList session={session} still={still} onOpenConnections={openConnections} />;

  return (
    <div className="ask-panel">
      {showsSetup && state.setupNeeded ? (
        <SetupView setup={state.setupNeeded} onOpenConnections={openConnections} />
      ) : (
        <>
          <div className="ask-content">{content}</div>
          <div className="ask-input-bar">
            <InputField
              value={draft}
              onChange={setDraft}
              placeholder={tr("Ask %@ anything…", state.assistant)}
              help={tr("Enter to send, Shift+Enter for a new line")}
              still={still}
              onSubmit={() => send(draft)}
              trailing={<SendButton isStreaming={state.isStreaming} canSend={canSend} send={() => send(draft)} stop={() => session.stop()} />}
            />
            {(state.isShowingHistory || state.savedChats.length > 0) && (
              <IconButton
                symbol={state.isShowingHistory ? "xmark" : "clock.arrow.circlepath"}
                size={32}
                help={state.isShowingHistory ? tr("Back to the chat") : tr("Chat history")}
                onClick={() => session.setShowingHistory(!state.isShowingHistory)}
              />
            )}
            {!state.isEmpty && (
              <IconButton
                symbol="square.and.pencil"
                size={32}
                help={tr("New chat")}
                onClick={() => {
                  session.newChat();
                  setDraft("");
                }}
              />
            )}
          </div>
        </>
      )}
    </div>
  );
}

/* Input */

interface InputFieldProps {
  readonly value: string;
  readonly onChange: (value: string) => void;
  readonly placeholder: string;
  readonly help: string;
  readonly still: boolean;
  readonly onSubmit: () => void;
  readonly trailing: ReactNode;
}

/** The rounded question field. Enter sends and Shift+Enter adds a line; it grows to three lines, then scrolls. */
function InputField({ value, onChange, placeholder, help, still, onSubmit, trailing }: InputFieldProps) {
  const [focused, setFocused] = useState(false);
  const area = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const element = area.current;
    if (!element) return;
    element.style.height = "0px";
    const lines = Math.min(MAX_FIELD_LINES, Math.max(1, Math.round((element.scrollHeight - 16) / FIELD_LINE_HEIGHT)));
    element.style.height = `${lines * FIELD_LINE_HEIGHT + 16}px`;
  }, [value]);
  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key !== "Enter" || event.shiftKey || event.nativeEvent.isComposing) return;
    event.preventDefault();
    onSubmit();
  };
  return (
    <Tooltip text={help}>
      <Card padding={0} className="ask-field" data-focused={focused} onClick={() => area.current?.focus()}>
        {still ? (
          <span className="ask-field-placeholder">{placeholder}</span>
        ) : (
          <textarea
            ref={area}
            className="ask-field-text"
            rows={1}
            value={value}
            placeholder={placeholder}
            aria-label={placeholder}
            autoFocus
            onChange={(event) => onChange(event.target.value)}
            onKeyDown={onKeyDown}
            onFocus={() => setFocused(true)}
            onBlur={() => setFocused(false)}
          />
        )}
        <div className="ask-field-trailing">{trailing}</div>
      </Card>
    </Tooltip>
  );
}

interface SendButtonProps {
  readonly isStreaming: boolean;
  readonly canSend: boolean;
  readonly send: () => void;
  readonly stop: () => void;
}

/** The field's primary action: an accent circle with an arrow once there is something to send, a quiet one before that, and Stop while the AI answers. */
function SendButton({ isStreaming, canSend, send, stop }: SendButtonProps) {
  const active = isStreaming || canSend;
  const tactile = useTactile({ disabled: !active });
  return (
    <Tooltip text={isStreaming ? tr("Stop answering") : tr("Send (Enter)")}>
      <button
        type="button"
        className="ask-send"
        data-active={active}
        aria-label={isStreaming ? tr("Stop answering") : tr("Send (Enter)")}
        disabled={!active}
        {...tactile.data}
        {...tactile.handlers}
        style={tactile.style}
        onClick={isStreaming ? stop : send}
      >
        <Icon id={isStreaming ? "stop.fill" : "arrow.up"} size={11} fixedDirection />
      </button>
    </Tooltip>
  );
}

/* Messages */

interface MessageListProps {
  readonly session: ClaudeAskSession;
  readonly still: boolean;
  readonly onOpenConnections: () => void;
}

function MessageList({ session, still, onOpenConnections }: MessageListProps) {
  const state = useStore(session);
  const scroller = useRef<HTMLDivElement>(null);
  const last = state.messages[state.messages.length - 1];
  /* Follows streamed text and the taller stopped or failed rows that replace it. */
  useLayoutEffect(() => {
    const element = scroller.current;
    if (element) element.scrollTop = element.scrollHeight;
  }, [state.messages.length, last?.text, last?.status, still]);
  return (
    <EdgeFade edge="top" length={24} style={{ height: "100%" }}>
      <div ref={scroller} className="ask-messages">
        <div className="ask-messages-rows">
          {state.messages.map((message) =>
            message.role === "user" ? (
              <UserBubble key={message.id} message={message} />
            ) : message.status === "failed" ? (
              <FailureRow
                key={message.id}
                failure={message === last ? session.state.phase.kind === "failed" ? session.state.phase.failure : undefined : undefined}
                assistant={message.provider === undefined ? tr("The AI") : assistantName(message.provider)}
                onRetry={message === last ? () => session.retry() : undefined}
                onOpenConnections={onOpenConnections}
              />
            ) : (
              <AssistantBubble key={message.id} message={message} still={still} />
            ),
          )}
        </div>
      </div>
    </EdgeFade>
  );
}

function UserBubble({ message }: { readonly message: ClaudeAskMessage }) {
  return (
    <div className="ask-row-user">
      <div className="ask-bubble-user">{message.text}</div>
    </div>
  );
}

function AssistantBubble({ message, still }: { readonly message: ClaudeAskMessage; readonly still: boolean }) {
  const canCopy = message.status !== "streaming" && message.text.length > 0;
  const stoppedEmpty = message.status === "stopped" && message.text.length === 0;
  let content: ReactNode;
  if (message.status === "streaming" && message.text.length === 0) {
    /* The AI often takes seconds to start; the paw trail says it's on its way. */
    content = (
      <div className="ask-thinking">
        <span>{tr("Thinking")}</span>
        {/* A still render shows the trail mid-stride rather than its empty first frame. */}
        <PawLoader size={16} label={tr("Thinking")} time={still ? 0.9 : undefined} />
      </div>
    );
  } else if (message.status === "streaming") {
    content = <AnswerBody text={message.text} caret />;
  } else if (message.text.length === 0) {
    content = <span className="kit-tertiary">{tr("No answer")}</span>;
  } else {
    content = <AnswerBody text={message.text} caret={false} />;
  }
  return (
    <div className="ask-row-assistant">
      <Card padding={0}>
        <div className="ask-bubble-assistant">
          {!stoppedEmpty && content}
          {message.status === "stopped" && (
            <span className="ask-note">
              <Icon id="stop.circle" size={11} />
              {tr("Stopped")}
            </span>
          )}
        </div>
      </Card>
      {/* Beside the card rather than over it, so short answers stay readable. */}
      <CopyButton className="ask-copy" text={message.text} canCopy={canCopy} />
    </div>
  );
}

/** An answer's prose and code blocks, top to bottom. The caret (while the answer streams) follows the last block. */
function AnswerBody({ text, caret }: { readonly text: string; readonly caret: boolean }) {
  const blocks = markdownBlocks(text);
  return (
    <div className="ask-answer">
      {blocks.map((block, index) => {
        const isLast = index === blocks.length - 1;
        if (block.kind === "text") {
          return (
            <div key={index} className="ask-prose">
              <Prose text={block.text} />
              {caret && isLast && <Caret />}
            </div>
          );
        }
        return <CodeBlock key={index} language={block.language} code={block.code} canCopy={block.isClosed || !caret} caret={caret && isLast} />;
      })}
    </div>
  );
}

/** The prose's inline Markdown as styled spans, line breaks kept. */
function Prose({ text }: { readonly text: string }) {
  return (
    <>
      {inlineRuns(simplifyBlocks(text)).map((run, index) => {
        let node: ReactNode = run.text;
        if (run.code) node = <code data-bold={run.bold || undefined}>{node}</code>;
        if (run.italic) node = <em>{node}</em>;
        if (run.bold && !run.code) node = <strong>{node}</strong>;
        return <span key={index}>{node}</span>;
      })}
    </>
  );
}

function Caret() {
  return (
    <span className="ask-caret" aria-hidden="true">
      {" ▍"}
    </span>
  );
}

interface CodeBlockProps {
  readonly language: string | undefined;
  readonly code: string;
  readonly canCopy: boolean;
  readonly caret: boolean;
}

/** A fenced code block: monospaced on a darker inset, with its language and a Copy button above. Long lines wrap. */
function CodeBlock({ language, code, canCopy, caret }: CodeBlockProps) {
  return (
    <div className="ask-code">
      <div className="ask-code-head">
        <span className="ask-code-language">{language ?? tr("Code")}</span>
        <CopyButton className="ask-code-copy" text={code} canCopy={canCopy} help={tr("Copy code")} />
      </div>
      <pre className="ask-code-body">
        {code}
        {caret && <Caret />}
      </pre>
    </div>
  );
}

interface CopyButtonProps {
  readonly text: string;
  readonly canCopy: boolean;
  readonly help?: string;
  readonly className?: string;
}

/** Copies text (an answer's Markdown or a code block); shows a check mark briefly after copying. */
function CopyButton({ text, canCopy, help = tr("Copy answer"), className }: CopyButtonProps) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1500);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return (
    <IconButton
      symbol={copied ? "checkmark" : "doc.on.doc"}
      size={22}
      help={copied ? tr("Copied") : help}
      className={className}
      data-can-copy={canCopy}
      tabIndex={canCopy ? undefined : -1}
      onClick={() => {
        void navigator.clipboard?.writeText(text).then(() => setCopied(true));
      }}
    />
  );
}

interface FailureRowProps {
  readonly failure: ClaudeAskFailure | undefined;
  readonly assistant: string;
  readonly onRetry: (() => void) | undefined;
  readonly onOpenConnections: () => void;
}

/** Shown in place of an answer that failed. Only the latest failure explains itself and offers retry; older ones stay as a quiet note. */
function FailureRow({ failure, assistant, onRetry, onOpenConnections }: FailureRowProps) {
  const title = failureTitle(failure ?? { kind: "process", detail: "" }, assistant);
  const detail = failure === undefined ? undefined : failureDetail(failure);
  return (
    <Card padding={0}>
      <div className="ask-failure">
        <Icon id="exclamationmark.triangle.fill" size={12} className="ask-failure-icon" />
        <div className="ask-failure-text">
          <span className="ask-failure-title">{title}</span>
          {detail !== undefined && detail.length > 0 && (
            <span className="ask-failure-detail">
              <Prose text={detail} />
            </span>
          )}
        </div>
        {failure && failureNeedsSetup(failure) ? (
          <Pill title={failureSetupAction(failure)} symbol="link" help={tr("Open Connections to set up the AI")} onClick={onOpenConnections} />
        ) : (
          onRetry && <Pill title={tr("Retry")} symbol="arrow.clockwise" help={tr("Ask this question again")} onClick={onRetry} />
        )}
      </div>
    </Card>
  );
}

/* History */

/** Saved chats, newest first: open one to continue it, or delete it. The first line says where they live and offers Clear All. */
function HistoryList({ session, context }: { readonly session: ClaudeAskSession; readonly context: ModuleContext }) {
  const state = useStore(session);
  /* One clock for every row, so a list that stays open past midnight relabels together. */
  const now = context.now();
  const timeZone = context.timeZone();
  return (
    <div className="ask-history">
      <div className="ask-history-head">
        <Tooltip text={tr("Saved chats are kept only on this PC and never uploaded")}>
          <span className="ask-history-note">
            <Icon id="lock.fill" size={10} />
            <span>{tr("Chats stay on this PC")}</span>
          </span>
        </Tooltip>
        <span className="ask-history-spacer" />
        {state.savedChats.length > 0 && <ClearAllButton onClear={() => session.deleteAllChats()} />}
      </div>
      {state.savedChats.length === 0 ? (
        <StatusMessage symbol="clock.arrow.circlepath" title={tr("No saved chats")} message={tr("Chats are saved here once you get an answer.")} />
      ) : (
        <EdgeFade edge="bottom" className="ask-history-list">
          <div className="ask-history-rows">
            {state.savedChats.map((chat) => (
              <HistoryRow
                key={chat.id}
                chat={chat}
                date={chatDateLabel(chat, now, timeZone, currentLanguage())}
                isOpen={chat.id === state.chatID}
                open={() => session.open(chat)}
                remove={() => session.delete(chat)}
              />
            ))}
          </div>
        </EdgeFade>
      )}
    </div>
  );
}

interface HistoryRowProps {
  readonly chat: ClaudeAskChat;
  readonly date: string;
  readonly isOpen: boolean;
  readonly open: () => void;
  readonly remove: () => void;
}

function HistoryRow({ chat, date, isOpen, open, remove }: HistoryRowProps) {
  const title = chatTitle(chat);
  return (
    <div className="ask-history-row">
      <Tooltip text={isOpen ? tr("This chat is open") : tr("Open this chat and continue it")}>
        <button type="button" className="ask-history-open" onClick={open}>
          <span className="ask-history-dot" data-open={isOpen} />
          <MarqueeText text={title} className="ask-history-title" />
          <span className="ask-history-date">{date}</span>
        </button>
      </Tooltip>
      <IconButton symbol="trash" size={22} help={tr("Delete this chat")} className="ask-history-delete" onClick={remove} />
    </div>
  );
}

/** Clear All asks once more before deleting: the first click turns it into a warning, and it settles back if the second never comes. */
function ClearAllButton({ onClear }: { readonly onClear: () => void }) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const timer = window.setTimeout(() => setArmed(false), 3000);
    return () => window.clearTimeout(timer);
  }, [armed]);
  return (
    <Pill
      className="ask-clear"
      data-armed={armed}
      title={armed ? tr("Delete All Chats?") : tr("Clear All")}
      symbol={armed ? "trash" : undefined}
      help={armed ? tr("Click again to delete every saved chat") : tr("Delete every saved chat")}
      onClick={() => {
        if (armed) {
          setArmed(false);
          onClear();
        } else {
          setArmed(true);
        }
      }}
    />
  );
}

/* Empty and setup states */

function EmptyChatView({ assistant, onPick }: { readonly assistant: string; readonly onPick: (prompt: string) => void }) {
  const examples = [tr("Quick dinner ideas"), tr("Write a polite reminder"), tr("Tips to focus better")];
  return (
    <StatusMessage
      symbol="sparkles"
      title={tr("Ask %@ anything", assistant)}
      message={tr("Quick answers right here. %@ can't see your files.", assistant)}
      actions={examples.map((prompt) => (
        <Pill key={prompt} title={prompt} help={tr("Ask “%@”", prompt)} onClick={() => onPick(prompt)} />
      ))}
    />
  );
}

/** The setup screen's sentence, with Windows wording where the Mac names its Mac or Keychain. */
export function setupMessage(failure: ClaudeAskFailure): string {
  switch (failure.kind) {
    case "noProvider":
      return tr("Answers come from the AI you pick: Claude, ChatGPT, Gemini or a free model on this PC.");
    case "notInstalled":
      return tr("%@ isn't on this PC yet. Connections shows you how to add it.", displayName(failure.provider));
    case "needsKey":
      return tr("Paste a key in Connections to ask %@ questions. It stays in Windows Credential Manager.", assistantName(failure.provider));
    case "process":
      return failure.detail;
  }
}

/**
 * Shown before the first question while the AI isn't ready (none picked, a
 * key missing): one plain sentence and the one button that leads to
 * Connections, which walks through setting it up.
 */
function SetupView({ setup, onOpenConnections }: { readonly setup: ClaudeAskFailure; readonly onOpenConnections: () => void }) {
  return (
    <StatusMessage
      symbol="sparkles"
      title={failureSetupTitle(setup)}
      message={setupMessage(setup)}
      actions={<Pill title={failureSetupAction(setup)} symbol="link" help={tr("Open Connections to set up the AI")} onClick={onOpenConnections} />}
    />
  );
}
