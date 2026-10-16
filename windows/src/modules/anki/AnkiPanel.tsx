/*
 * Port of AnkiPanel: the Anki tab. Connected, it shows today's due cards in
 * a progress ring (the panel's primary element), the decks with the most
 * due, and a footer with the streak, a two-week heatmap, Sync and Start
 * reviews. Until AnkiConnect answers it walks the user through the one
 * setup step that's missing. `AnkiConnectSetupView` is onboarding's Anki
 * step, the same screens inside the setup flow.
 */

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { ANKI_CONNECT_ADD_ON_CODE, errorSuggestion, errorTitle, isUnexplained, quotedMessage, type AnkiConnectError } from "../../core/anki/ankiConnectError";
import type { AnkiDayCount, AnkiDeckStats } from "../../core/anki/ankiConnectModels";
import { addOnReminder, collectionUnavailableMessage, profileListHint, shortMessage } from "../../core/anki/ankiConnectError";
import { deckLeaf } from "../../core/anki/ankiDeckName";
import { ageText, heatLevels, progressHelp, streakText } from "../../core/anki/ankiFormat";
import { addingDays, sameAnkiDay, type AnkiDay } from "../../core/anki/ankiDay";
import { completionFraction, deckOutline, hasReviewedToday, summaryDueTotal, topDecks, type AnkiDeckOutlineRow, type AnkiSummary } from "../../core/anki/ankiSummary";
import { dueTotal } from "../../core/anki/ankiConnectModels";
import { currentLanguage, tr } from "../../core/localization/tr";
import { Card } from "../../ui/kit/Card";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { PawLoader, ProgressRing, Spinner } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Pill } from "../../ui/kit/Pill";
import { RowsThatFit } from "../../ui/kit/RowsThatFit";
import { StatusMessage } from "../../ui/kit/StatusMessage";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useKit, useTheme } from "../../ui/kit/context";
import { accentVariables } from "../../ui/kit/tokens";
import { useElementWidth } from "../../ui/kit/useElementWidth";
import type { ModuleAccent } from "../../core/themes/themeColor";
import type { AnkiOpenNotice, AnkiOpening, AnkiStore } from "./ankiStore";
import "./anki.css";

/* Anki's own colors for the three queues, so the numbers read the same as in Anki's deck list. */
const QUEUE = { new: "var(--accent)", learning: "var(--danger)", review: "var(--success)" } as const;

/** The ring card's width beside the decks; narrower panels drop its queue names. */
const DUE_CARD_WIDTH = 240;
/** The narrowest the decks card gets beside the full ring card. */
const DECKS_MIN_WIDTH = 240;
const COLLAPSED_COUNT = 4;

export function AnkiPanel({ store }: { readonly store: AnkiStore }) {
  const state = useStore(store);
  useEffect(() => {
    store.panelDidAppear();
    return () => store.panelDidDisappear();
  }, [store]);
  if (state.summary !== undefined && keepsSummary(state.connection.kind)) return <AnkiDeckView store={store} summary={state.summary} />;
  if (state.connection.kind === "checking") return <AnkiLoadingView />;
  return <AnkiSetupView store={store} />;
}

function keepsSummary(kind: string): boolean {
  return kind === "ready" || kind === "problem" || kind === "checking";
}

/* MARK: Connected */

function AnkiDeckView({ store, summary }: { readonly store: AnkiStore; readonly summary: AnkiSummary }) {
  const showsAll = useStore(store, (state) => state.showsAllDecks);
  const [container, width] = useElementWidth<HTMLDivElement>();
  /* On a narrow panel the ring card drops its queue names, so the deck names beside it stay readable. */
  const compactRing = width > 0 && width < DUE_CARD_WIDTH + 8 + DECKS_MIN_WIDTH;
  const outline = deckOutline(summary);
  /* Reviewing or a refresh can leave too few decks for the toggle to show; collapse then, or the ring would stay hidden with no way back. */
  useEffect(() => {
    if (showsAll && outline.length <= COLLAPSED_COUNT) store.setShowsAllDecks(false);
  }, [store, showsAll, outline.length]);
  return (
    <div ref={container} className="anki-panel">
      <div className="anki-cards">
        {!showsAll && <DueCard summary={summary} compact={compactRing} style={compactRing ? undefined : { width: DUE_CARD_WIDTH, flex: "none" }} />}
        <DecksCard store={store} summary={summary} outline={outline} showsAll={showsAll} />
      </div>
      <AnkiFooter store={store} summary={summary} />
    </div>
  );
}

/** Cards due today inside a ring of reviewed versus due, with the new / learning / review split beside it. */
export function DueCard({ summary, compact = false, style }: { readonly summary: AnkiSummary; readonly compact?: boolean; readonly style?: CSSProperties }) {
  const due = summaryDueTotal(summary);
  return (
    <Tooltip text={progressHelp(summary)}>
      <Card className="anki-due" style={style}>
        <ProgressRing progress={completionFraction(summary)} tint={due === 0 ? "var(--success)" : "var(--accent)"} track="var(--accent-faint)" lineWidth={7} size={92}>
          {due === 0 ? (
            <div className="anki-ring-done">
              <Icon id="check" size={20} />
              <span className="kit-caption kit-tertiary">{tr("All done")}</span>
            </div>
          ) : (
            <div className="anki-ring-due">
              <span className="kit-metric">{due}</span>
              <span className="kit-caption kit-tertiary">{tr("due")}</span>
            </div>
          )}
        </ProgressRing>
        <div className="anki-queues">
          <QueueRow title={tr("New")} count={summary.newDue} color={QUEUE.new} compact={compact} />
          <QueueRow title={tr("Learning")} count={summary.learnDue} color={QUEUE.learning} compact={compact} />
          <QueueRow title={tr("Review")} count={summary.reviewDue} color={QUEUE.review} compact={compact} />
          <div className="anki-queue-rule" />
          <div className="anki-done kit-caption">
            {compact ? <Icon id="check" size={9} className="kit-tertiary" /> : <span className="kit-tertiary">{tr("Done")}</span>}
            <span className="kit-secondary anki-count">{summary.reviewedToday}</span>
          </div>
        </div>
      </Card>
    </Tooltip>
  );
}

function QueueRow({ title, count, color, compact }: { readonly title: string; readonly count: number; readonly color: string; readonly compact: boolean }) {
  const row = (
    <div className="anki-queue kit-body">
      <span className="anki-queue-dot" style={{ background: color }} />
      {!compact && <MarqueeText text={title} className="kit-secondary anki-queue-title" />}
      <span className={["anki-count", count > 0 ? "" : "kit-tertiary"].join(" ")}>{count}</span>
    </div>
  );
  return compact ? <Tooltip text={title}>{row}</Tooltip> : row;
}

/**
 * The decks with the most due. Collapsed it fits the top four beside the
 * ring; expanded it takes the full width, scrolls, and lists subdecks under
 * their parents so any exact deck is one click away.
 */
function DecksCard({
  store,
  summary,
  outline,
  showsAll,
}: {
  readonly store: AnkiStore;
  readonly summary: AnkiSummary;
  readonly outline: readonly AnkiDeckOutlineRow[];
  readonly showsAll: boolean;
}) {
  const state = useStore(store);
  const top = topDecks(summary);
  const header = (expandable: boolean) => (
    <div className="anki-decks-header">
      <div className="anki-decks-notice">
        {state.opening !== undefined ? (
          <OpeningNotice opening={state.opening} />
        ) : state.openNotice !== undefined ? (
          <OpenNotice notice={state.openNotice} />
        ) : store.problem !== undefined ? (
          <StaleNotice problem={store.problem} updatedAt={state.updatedAt} now={store.now()} />
        ) : (
          <span className="kit-caption kit-tertiary">{showsAll ? tr("All decks with cards due") : tr("Top decks")}</span>
        )}
      </div>
      {expandable && (
        <Pill
          title={showsAll ? tr("Show less") : tr("All %lld", outline.length)}
          symbol={showsAll ? "chevron.up" : "chevron.down"}
          symbolPosition="trailing"
          height={20}
          help={showsAll ? tr("Show the top decks beside today's total") : tr("Show every deck with cards due")}
          onClick={() => store.setShowsAllDecks(!showsAll)}
        />
      )}
    </div>
  );
  const row = (item: AnkiDeckOutlineRow) => (
    <DeckRow
      row={item}
      isOpening={state.opening?.deck === item.deck.name}
      isFavorite={store.isFavorite(item.deck)}
      onToggleFavorite={() => store.toggleFavorite(item.deck)}
      onOpen={() => store.startReviews(item.deck.name)}
    />
  );
  return (
    <Card padding={8} className="anki-decks" style={{ minWidth: showsAll ? 0 : DECKS_MIN_WIDTH }}>
      {top.length === 0 ? (
        <>
          {header(false)}
          <AllCaughtUp />
        </>
      ) : showsAll ? (
        <>
          {header(true)}
          <EdgeFade edge="bottom" length={12} className="anki-decks-scroll">
            <div className="anki-decks-rows">
              {outline.map((item) => (
                <div key={item.deck.deckID}>{row(item)}</div>
              ))}
            </div>
          </EdgeFade>
        </>
      ) : (
        /* A shorter panel lists fewer decks instead of clipping the card, and offers All N for the rest. */
        <RowsThatFit
          data={top.slice(0, COLLAPSED_COUNT).map((deck): AnkiDeckOutlineRow => ({ deck, depth: 0, title: deck.name }))}
          keyOf={(item) => item.deck.deckID}
          spacing={2}
          header={(shown) => header(outline.length > shown)}
          row={row}
          className="anki-decks-fit"
        />
      )}
    </Card>
  );
}

/** Anki is opening a deck after a click. */
function OpeningNotice({ opening }: { readonly opening: AnkiOpening }) {
  return (
    <Tooltip text={opening.deck === undefined ? tr("Waiting for Anki to start") : tr("Waiting for Anki to start, then opening %@", opening.deck)}>
      <span className="anki-notice kit-caption">
        <Spinner tint="var(--accent)" size={10} lineWidth={1.5} />
        <MarqueeText text={tr("Opening Anki…")} className="kit-secondary" />
      </span>
    </Tooltip>
  );
}

/** Why the last click didn't open its deck, with the next step in the tooltip. */
function OpenNotice({ notice }: { readonly notice: AnkiOpenNotice }) {
  const title = notice.kind === "ankiClosed" ? tr("Anki is closed") : notice.kind === "deckNotFound" ? tr("Deck not found") : errorTitle(notice.error);
  const help =
    notice.kind === "ankiClosed"
      ? tr("Open Anki to see your due cards.")
      : notice.kind === "deckNotFound"
        ? tr("Anki has no deck called %@. It may have been renamed or deleted.", notice.deck)
        : errorSuggestion(notice.error);
  return (
    <Tooltip text={help}>
      <span className="anki-notice kit-caption">
        <Icon id="exclamationmark.triangle.fill" size={10} style={{ color: "var(--warning)" }} />
        <MarqueeText text={title} className="kit-secondary" />
      </span>
    </Tooltip>
  );
}

/** Why the numbers may be out of date: the refresh or the last action failed. The suggestion is in the tooltip. */
function StaleNotice({ problem, updatedAt, now }: { readonly problem: AnkiConnectError; readonly updatedAt: number | undefined; readonly now: number }) {
  const text = updatedAt === undefined ? errorTitle(problem) : `${errorTitle(problem)} · ${ageText(updatedAt, now)}`;
  return (
    <Tooltip text={errorSuggestion(problem)}>
      <span className="anki-notice kit-caption">
        <Icon id="exclamationmark.triangle.fill" size={10} style={{ color: "var(--warning)" }} />
        <MarqueeText text={text} className="kit-secondary" />
      </span>
    </Tooltip>
  );
}

/**
 * One deck: its name and the three queue counts, like Anki's deck list.
 * Clicking it starts reviewing that deck in Anki. The star, shown on hover
 * and always on the favorite, pins it as the Study button's deck.
 */
function DeckRow({
  row,
  isOpening,
  isFavorite,
  onToggleFavorite,
  onOpen,
}: {
  readonly row: AnkiDeckOutlineRow;
  readonly isOpening: boolean;
  readonly isFavorite: boolean;
  readonly onToggleFavorite: () => void;
  readonly onOpen: () => void;
}) {
  const deck = row.deck;
  const help = tr("Review %@ in Anki: %lld new, %lld learning, %lld review", deck.name, deck.newCount, deck.learnCount, deck.reviewCount);
  return (
    <Tooltip text={help}>
      <div
        className="anki-deck"
        role="button"
        tabIndex={0}
        data-favorite={isFavorite || undefined}
        data-depth={row.depth}
        style={{ paddingInlineStart: 4 + row.depth * 12 }}
        onClick={onOpen}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            onOpen();
          }
        }}
        aria-label={`${row.title}: ${tr("%lld new, %lld learning, %lld review", deck.newCount, deck.learnCount, deck.reviewCount)}`}
      >
        <MarqueeText text={row.title} userText className={row.depth === 0 ? "kit-body-emphasis anki-deck-name" : "kit-body kit-secondary anki-deck-name"} />
        <span className="anki-deck-star" onClick={(event) => event.stopPropagation()}>
          <IconButton
            symbol={isFavorite ? "star.fill" : "star"}
            size={16}
            tint={isFavorite ? "var(--accent)" : undefined}
            help={isFavorite ? tr("Unpin %@ from the Study button", deck.name) : tr("Pin %@ to the Study button", deck.name)}
            onClick={onToggleFavorite}
            className="anki-star"
          />
        </span>
        {isOpening ? <Spinner tint="var(--accent)" size={10} lineWidth={1.5} /> : <Icon id="play.fill" size={9} className="anki-deck-play" />}
        <span className="anki-deck-count kit-caption" style={{ color: deck.newCount > 0 ? QUEUE.new : "var(--tertiary-text)" }}>
          {deck.newCount}
        </span>
        <span className="anki-deck-count kit-caption" style={{ color: deck.learnCount > 0 ? QUEUE.learning : "var(--tertiary-text)" }}>
          {deck.learnCount}
        </span>
        <span className="anki-deck-count kit-caption" style={{ color: deck.reviewCount > 0 ? QUEUE.review : "var(--tertiary-text)" }}>
          {deck.reviewCount}
        </span>
      </div>
    </Tooltip>
  );
}

function AllCaughtUp() {
  return (
    <div className="anki-caught-up">
      <Icon id="checkmark.seal.fill" size={18} style={{ color: "var(--success)" }} />
      <span className="kit-body kit-secondary">{tr("Every deck is caught up")}</span>
    </div>
  );
}

/** Streak, heatmap, and the two actions. */
function AnkiFooter({ store, summary }: { readonly store: AnkiStore; readonly summary: AnkiSummary }) {
  const state = useStore(store);
  const [slot, slotWidth] = useElementWidth<HTMLDivElement>();
  const historyMissing = summary.missing.has("history");
  const favorite = state.favorite;
  const deck = store.favoriteDeck;
  const name = deck?.name ?? favorite?.name;
  const due = deck === undefined ? 0 : dueTotal(deck);
  const top = topDecks(summary)[0];
  /* The latest days that fit, so a long favorite deck name keeps its button readable. */
  const days = [14, 10, 7].find((count) => count * 12 + (count - 1) * 3 <= slotWidth) ?? 0;
  return (
    <div className="anki-footer">
      {historyMissing ? (
        <StreakBadge streak={undefined} reviewedToday={false} unavailableReason={historyGap(summary)} />
      ) : (
        <StreakBadge streak={summary.streak} reviewedToday={hasReviewedToday(summary)} />
      )}
      <div ref={slot} className="anki-heatmap-slot">
        {!historyMissing && days > 0 && <ReviewHeatmap history={summary.history.slice(-days)} />}
      </div>
      <IconButton
        symbol="arrow.triangle.2.circlepath"
        help={state.isSyncing ? tr("Syncing with AnkiWeb…") : tr("Sync with AnkiWeb")}
        spinning={state.isSyncing}
        disabled={state.isSyncing}
        onClick={() => store.sync()}
      />
      {favorite !== undefined && name !== undefined ? (
        <Pill
          prominent
          height={28}
          lifts
          symbol="play.fill"
          title={tr("Study %@", deckLeaf(name))}
          userText
          badge={due > 0 ? due : undefined}
          help={due > 0 ? tr("Review %@ in Anki: %lld due. Pin another deck with its star.", name, due) : tr("Open %@ in Anki. Nothing is due there today.", name)}
          onClick={() => store.studyFavorite()}
          className="anki-primary"
        />
      ) : (
        <Pill
          prominent
          height={28}
          lifts
          symbol="play.fill"
          title={tr("Start reviews")}
          help={top === undefined ? tr("Nothing due today") : tr("Open %@ for review in Anki", top.name)}
          disabled={summaryDueTotal(summary) === 0}
          onClick={() => store.startReviews()}
          className="anki-primary"
        />
      )}
    </div>
  );
}

/** Why the history is missing, for the streak's tooltip. */
function historyGap(summary: AnkiSummary): string {
  const message = summary.gaps.find((gap) => gap.action === "getNumCardsReviewedByDay")?.message ?? "";
  return tr("Anki couldn't send your review history this time: “%@”", shortMessage(message));
}

function StreakBadge({ streak, reviewedToday, unavailableReason }: { readonly streak: number | undefined; readonly reviewedToday: boolean; readonly unavailableReason?: string }) {
  const help = streak === undefined ? (unavailableReason ?? "") : streak > 0 && !reviewedToday ? tr("Review today to keep your %lld-day streak", streak) : tr("Days in a row with at least one review");
  return (
    <Tooltip text={help}>
      <span className="anki-streak kit-caption">
        <Icon id="flame.fill" size={11} style={{ color: (streak ?? 0) > 0 ? "var(--warning)" : "var(--tertiary-text)" }} />
        <span className={streak === undefined ? "kit-tertiary" : "kit-secondary"}>{streak === undefined ? tr("Streak unavailable") : streakText(streak)}</span>
      </span>
    </Tooltip>
  );
}

/** "Today", "Yesterday", or a short weekday and date in the user's language. */
function heatDayName(day: AnkiDay, today: AnkiDay, locale: string): string {
  if (sameAnkiDay(day, today)) return tr("Today");
  if (sameAnkiDay(day, addingDays(today, -1))) return tr("Yesterday");
  return new Intl.DateTimeFormat(locale, { timeZone: "UTC", weekday: "short", month: "short", day: "numeric" }).format(new Date(Date.UTC(day.year, day.month - 1, day.day, 12)));
}

/** A heatmap cell's tooltip: "Today · 112 reviews". */
function heatDayHelp(entry: AnkiDayCount, today: AnkiDay, locale: string): string {
  const count = entry.count === 0 ? tr("No reviews") : tr("%lld reviews", entry.count);
  return `${heatDayName(entry.day, today, locale)} · ${count}`;
}

/** Two weeks of reviews, one cell per day, today last and outlined. */
function ReviewHeatmap({ history }: { readonly history: readonly AnkiDayCount[] }) {
  const levels = heatLevels(history);
  const today = history.at(-1)?.day;
  const locale = currentLanguage();
  return (
    <div className="anki-heatmap" aria-hidden="true">
      {history.map((entry, index) => {
        const level = levels[index] ?? 0;
        const isToday = today !== undefined && entry.day.year === today.year && entry.day.month === today.month && entry.day.day === today.day;
        return (
          <Tooltip key={`${entry.day.year}-${entry.day.month}-${entry.day.day}`} text={today === undefined ? "" : heatDayHelp(entry, today, locale)}>
            <span
              className="anki-heat-cell"
              data-today={isToday || undefined}
              style={{ background: level > 0 ? `color-mix(in srgb, var(--accent) ${Math.round((0.25 + (0.75 * level) / 4) * 100)}%, transparent)` : "var(--surface)" }}
            />
          </Tooltip>
        );
      })}
    </div>
  );
}

/* MARK: Loading and setup */

export function AnkiLoadingView() {
  return <StatusMessage symbol={null} title={tr("Looking for Anki…")} message={tr("Your cards due today show up here.")} />;
}

interface SetupGuide {
  readonly symbol: string;
  readonly title: string;
  readonly message: string;
  readonly steps: readonly string[];
  readonly hint?: string;
  /** What Anki actually said, under the message, for an error Tabbi can't explain. */
  readonly detail?: string;
}

/** The words for each setup screen. Kept edition-neutral so any kit can include the Anki tab. */
function setupGuide(store: AnkiStore): SetupGuide {
  const { connection, opening, openNotice } = store.state;
  if (opening !== undefined) {
    return {
      symbol: "rectangle.stack",
      title: opening.deck === undefined ? tr("Opening Anki…") : tr("Opening %@…", deckLeaf(opening.deck)),
      message: tr("Asking Anki to open the deck for review."),
      steps: [],
    };
  }
  switch (connection.kind) {
    case "notInstalled":
      return {
        symbol: "arrow.down.app",
        title: tr("Anki isn't installed"),
        message: tr("Install the free Anki desktop app to see your due cards, decks and streak here."),
        steps: [],
      };
    case "notRunning":
      if (openNotice?.kind === "ankiClosed") {
        return {
          symbol: "power",
          title: tr("Anki is closed"),
          message: tr("Open Anki to see your due cards."),
          steps: [],
        };
      }
      return {
        symbol: "power",
        title: tr("Anki is closed"),
        message: tr("Open Anki to see today's due cards. This tab connects as soon as it's running."),
        steps: [],
      };
    case "starting":
      return { symbol: "hourglass", title: tr("Connecting to Anki…"), message: tr("Waiting for Anki to finish loading its add-ons."), steps: [] };
    case "addOnMissing":
      return {
        symbol: "puzzlepiece.extension",
        title: tr("Add AnkiConnect to Anki"),
        message: tr("This tab reads your decks through the free AnkiConnect add-on."),
        steps: [tr("In Anki, choose Tools › Add-ons › Get Add-ons…"), tr("Paste the code %@ and click OK", ANKI_CONNECT_ADD_ON_CODE), tr("Restart Anki to load it")],
      };
    case "needsPermission":
      if (connection.error.kind === "apiKeyRequired") {
        return {
          symbol: "key",
          title: tr("AnkiConnect wants an API key"),
          message: tr("Its config sets an API key, which this tab doesn't send."),
          steps: [tr("In Anki, choose Tools › Add-ons › AnkiConnect › Config"), tr('Set "apiKey" to null, then click OK'), tr("Restart Anki")],
        };
      }
      return {
        symbol: "hand.raised",
        title: tr("AnkiConnect blocked this app"),
        message: tr("Its settings turned the connection away."),
        steps: [tr("In Anki, choose Tools › Add-ons › AnkiConnect › Config"), tr("Click Restore Defaults, then OK"), tr("Restart Anki")],
      };
    case "addOnOutdated":
      return {
        symbol: "arrow.triangle.2.circlepath",
        title: tr("Update AnkiConnect"),
        message: tr("The installed AnkiConnect is too old for this tab."),
        steps: [tr("In Anki, choose Tools › Add-ons"), tr("Select AnkiConnect and click Check for Updates"), tr("Restart Anki")],
      };
    case "problem":
      if (connection.error.kind === "collectionUnavailable") {
        return { symbol: "clock.arrow.circlepath", title: errorTitle(connection.error), message: collectionUnavailableMessage(), steps: [], hint: profileListHint() };
      }
      if (isUnexplained(connection.error)) {
        /* Tabbi can't tell what's wrong, so it shows Anki's own words and the likeliest fix, with the add-on code one click away. */
        return {
          symbol: "exclamationmark.triangle",
          title: errorTitle(connection.error),
          message: addOnReminder(),
          steps: [],
          ...(quotedMessage(connection.error) === undefined ? {} : { detail: quotedMessage(connection.error) }),
        };
      }
      return { symbol: "exclamationmark.triangle", title: errorTitle(connection.error), message: errorSuggestion(connection.error), steps: [] };
    case "checking":
    case "ready":
      return { symbol: "rectangle.stack", title: tr("Looking for Anki…"), message: "", steps: [] };
  }
}

/**
 * One screen per setup step: what's wrong in a line, the steps to fix it,
 * and a button for the next action. The panel flips to the deck view on
 * its own a few seconds after the step is done.
 */
export function AnkiSetupView({ store, compact = false }: { readonly store: AnkiStore; readonly compact?: boolean }) {
  const state = useStore(store);
  const guide = setupGuide(store);
  const showsMessage = !(compact && guide.steps.length > 0);
  const connection = state.connection;
  const actions: ReactNode[] = [];
  if (state.opening === undefined) {
    switch (connection.kind) {
      case "notRunning":
        if (state.favorite !== undefined) {
          actions.push(
            <Pill
              key="study"
              prominent
              height={28}
              symbol="play.fill"
              title={tr("Study %@", deckLeaf(state.favorite.name))}
              userText
              help={tr("Open Anki straight into %@", state.favorite.name)}
              onClick={() => store.studyFavorite()}
            />,
          );
        }
        actions.push(<Pill key="get" height={28} symbol="arrow.down.circle.fill" title={tr("Get Anki")} help={tr("Open apps.ankiweb.net in your browser")} onClick={() => store.getAnki()} />);
        break;
      case "notInstalled":
        actions.push(
          <Pill key="get" prominent height={28} symbol="arrow.down.circle.fill" title={tr("Get Anki")} help={tr("Open apps.ankiweb.net in your browser")} onClick={() => store.getAnki()} />,
        );
        break;
      case "addOnMissing":
        actions.push(<CopyCodeButton key="copy" />);
        break;
      case "problem":
        actions.push(<Pill key="retry" prominent height={28} symbol="arrow.clockwise" title={tr("Try again")} help={tr("Ask Anki again")} onClick={() => store.refresh()} />);
        if (isUnexplained(connection.error)) actions.push(<CopyCodeButton key="copy" secondary />);
        break;
      default:
        break;
    }
  }
  return (
    <Card padding={compact ? 12 : 16} className="anki-setup" data-compact={compact || undefined}>
      <div className="anki-setup-badge">
        {state.opening !== undefined ? (
          <Spinner tint="var(--accent)" size={20} />
        ) : connection.kind === "starting" ? (
          <PawLoader tint="var(--accent)" size={20} label={tr("Starting Anki")} revealed />
        ) : (
          <Icon id={guide.symbol} size={22} />
        )}
      </div>
      <div className="anki-setup-text">
        <Tooltip text={guide.message}>
          <div className="anki-setup-words">
            <span className="kit-title">{guide.title}</span>
            {showsMessage && guide.message !== "" && <span className="kit-body kit-secondary anki-setup-message">{guide.message}</span>}
            {guide.detail !== undefined && (
              <Tooltip text={guide.detail}>
                <span className="kit-caption kit-tertiary anki-setup-detail">{guide.detail}</span>
              </Tooltip>
            )}
          </div>
        </Tooltip>
        {guide.steps.length > 0 && (
          <ol className="anki-steps" data-compact={compact || undefined}>
            {guide.steps.map((step, index) => (
              <li key={step} className="anki-step">
                <span className="anki-step-number">{index + 1}</span>
                <MarqueeText text={step} className="kit-body kit-secondary" />
              </li>
            ))}
          </ol>
        )}
        {(actions.length > 0 || guide.hint !== undefined) && (
          <div className="anki-setup-actions">
            {actions}
            {guide.hint !== undefined && <MarqueeText text={guide.hint} className="kit-caption kit-tertiary anki-setup-hint" />}
          </div>
        )}
      </div>
    </Card>
  );
}

/** Copies the AnkiConnect code, confirming with a check for a moment. */
function CopyCodeButton({ secondary = false }: { readonly secondary?: boolean }) {
  const [copied, setCopied] = useState(false);
  const { still } = useKit();
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 2000);
    return () => window.clearTimeout(timer);
  }, [copied]);
  const copy = () => {
    if (still) return;
    void navigator.clipboard?.writeText(ANKI_CONNECT_ADD_ON_CODE).then(() => setCopied(true));
  };
  return (
    <Pill
      prominent={!secondary}
      height={28}
      symbol={copied ? "check" : secondary ? "doc.on.doc" : "doc.on.doc.fill"}
      title={copied ? tr("Copied") : tr("Copy code %@", ANKI_CONNECT_ADD_ON_CODE)}
      help={tr("Copy the AnkiConnect add-on code to paste into Anki")}
      onClick={copy}
    />
  );
}

/* MARK: Onboarding */

/**
 * Onboarding's Anki step: the Anki tab's own connection guide, so the one
 * setup step that is missing is fixed right here. Once AnkiConnect answers
 * it confirms the connection with today's due cards as the tab will show them.
 */
export function AnkiConnectSetupView({ store, accent }: { readonly store: AnkiStore; readonly accent: ModuleAccent }) {
  const state = useStore(store);
  const theme = useTheme();
  /* The takeover body carries no module accent; the step draws in Anki's. */
  const style = accentVariables(theme, accent) as CSSProperties;
  useEffect(() => {
    /* Visible like the panel, so it checks again while the user sets up. */
    store.panelDidAppear();
    return () => store.panelDidDisappear();
  }, [store]);
  if (state.summary !== undefined && keepsSummary(state.connection.kind)) {
    return (
      <div className="anki-connected" style={style}>
        <DueCard summary={state.summary} style={{ width: DUE_CARD_WIDTH, flex: "none" }} />
        <AnkiConnectedCard summary={state.summary} />
      </div>
    );
  }
  return (
    <div className="anki-setup-step" style={style}>
      {state.connection.kind === "checking" ? <AnkiLoadingView /> : <AnkiSetupView store={store} compact />}
    </div>
  );
}

/** What the connection gives: where the due cards show up from now on. */
function AnkiConnectedCard({ summary }: { readonly summary: AnkiSummary }) {
  const decks = topDecks(summary).length;
  const deckLine = decks === 0 ? tr("Nothing due today") : tr("%lld decks with cards due", decks);
  return (
    <Card className="anki-connected-card">
      <div className="anki-connected-head">
        <span className="anki-connected-check">
          <Icon id="check" size={13} />
        </span>
        <div className="anki-connected-lines">
          <MarqueeText text={tr("Anki is connected")} className="kit-body-emphasis" />
          <MarqueeText text={deckLine} className="kit-caption anki-connected-decks" />
        </div>
      </div>
      <span className="kit-caption kit-secondary anki-connected-note">{tr("The Anki tab shows your due cards, top decks and streak, and Today counts your reviews toward the day.")}</span>
      <Tooltip text={tr("Tabbi talks to Anki only on this PC and never uploads your decks")}>
        <span className="anki-connected-lock kit-caption kit-tertiary">
          <Icon id="lock.fill" size={9} />
          <MarqueeText text={tr("Read through AnkiConnect on this PC")} />
        </span>
      </Tooltip>
    </Card>
  );
}

export { dueTotal as deckDueTotal };
export type { AnkiDeckStats };
