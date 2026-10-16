/*
 * Port of ClaudeUsagePanel: the 5-hour and weekly limits as rings, today's
 * local usage in a card, and a footer with freshness and a manual refresh.
 * Relative labels ("resets in 2h 14m", "Updated 3m ago") only need minute
 * precision, so the panel re-reads the clock every 30 seconds while shown.
 */

import { useEffect, useState, type ReactNode } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import type { ClaudeUsageWindow } from "../../core/claude/claudeStreamEvent";
import { periodMessages, periodTokens, topModel, type ClaudeLocalStats } from "../../core/claudeUsage/claudeLocalStats";
import { compactTokens, modelName, percentText, resetDescription, updatedDescription, usageLevel } from "../../core/claudeUsage/claudeUsageFormat";
import { usageToolName, type AIUsageSource } from "../../core/claudeUsage/claudeUsageHighlights";
import { totalTokens } from "../../core/claudeUsage/claudeUsageRecord";
import { currentLanguage, tr } from "../../core/localization/tr";
import type { Instant } from "../../core/time";
import { Card } from "../../ui/kit/Card";
import { useKit } from "../../ui/kit/context";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { ProgressRing, Spinner } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { CLIStatus, ClaudeUsageStore } from "./claudeUsageStore";
import "./claudeUsage.css";

export interface ClaudeUsagePanelProps {
  readonly store: ClaudeUsageStore;
  readonly context: ModuleContext;
}

/** The environment variable that points at the claude tool (ai_paths.rs `override_variable`). */
const CLAUDE_OVERRIDE_VARIABLE = "TABBI_CLAUDE_PATH";

/** The clock, re-read every `seconds` while the panel is shown; still in a snapshot. */
function useNow(context: ModuleContext, seconds: number): Instant {
  const { still } = useKit();
  const [now, setNow] = useState(() => context.now());
  useEffect(() => {
    if (still) return;
    const timer = window.setInterval(() => setNow(context.now()), seconds * 1000);
    return () => window.clearInterval(timer);
  }, [context, seconds, still]);
  return now;
}

export function ClaudeUsagePanel({ store, context }: ClaudeUsagePanelProps) {
  const state = useStore(store);
  const now = useNow(context, 30);
  useEffect(() => store.panelDidAppear(), [store]);
  const snapshot = state.limits?.snapshot;
  return (
    <div className="usage-panel">
      <div className="usage-top">
        {state.cliStatus === "missing" && state.limits === undefined ? (
          <CLIMissingCard source={state.source} />
        ) : (
          <div className="usage-rings">
            <UsageRing title={tr("5-hour")} window={snapshot?.fiveHour} now={now} timeZone={context.timeZone()} help={tr("Usage of your rolling 5-hour limit")} />
            <UsageRing title={tr("Weekly")} window={snapshot?.sevenDay} now={now} timeZone={context.timeZone()} help={tr("Usage of your weekly limit")} />
          </div>
        )}
        <TodayCard stats={state.stats} source={state.source} />
      </div>
      <UsageFooter
        source={state.source}
        cliStatus={state.cliStatus}
        isFetching={state.isFetching}
        probeError={state.probeError}
        updated={state.limits === undefined ? undefined : updatedDescription(state.limits.fetchedAt, now)}
        onRefresh={() => store.refresh()}
      />
    </div>
  );
}

interface UsageRingProps {
  readonly title: string;
  readonly window: ClaudeUsageWindow | undefined;
  readonly now: Instant;
  readonly timeZone: string;
  readonly help: string;
}

const RING_DIAMETER = 80;
const RING_LINE_WIDTH = 7;

/** One usage window as a ring with the percentage inside. */
function UsageRing({ title, window, now, timeZone, help }: UsageRingProps) {
  const utilization = window?.utilization ?? 0;
  const level = usageLevel(utilization);
  const tint = level === "normal" ? "var(--accent)" : level === "warning" ? "var(--warning)" : "var(--danger)";
  const reset = window === undefined ? undefined : resetDescription(window.resetsAt, now, timeZone, currentLanguage());
  return (
    <Tooltip text={help}>
      <div className="usage-ring">
        <ProgressRing className="usage-ring-dial" progress={utilization} tint={tint} track="var(--surface)" lineWidth={RING_LINE_WIDTH} size={RING_DIAMETER}>
          {window ? (
            <span className="usage-ring-value">{percentText(window.utilization)}</span>
          ) : (
            <Icon id="questionmark" size={18} className="usage-ring-unknown" />
          )}
        </ProgressRing>
        <span className="usage-ring-title">{title}</span>
        {/* Keeps its line even without a reset time, so the rings stay level. */}
        <MarqueeText className="usage-ring-reset" text={reset ?? " "} />
      </div>
    </Tooltip>
  );
}

/** Today's local usage from Claude Code transcripts or Codex logs. */
function TodayCard({ stats, source }: { readonly stats: ClaudeLocalStats | undefined; readonly source: AIUsageSource }) {
  const tool = usageToolName(source);
  const locale = currentLanguage();
  let body: ReactNode;
  if (stats) {
    const week = compactTokens(totalTokens(periodTokens(stats.lastSevenDays)));
    const top = topModel(stats.today);
    body = (
      <>
        <Tooltip text={tr("Input, output, and cache tokens across all %@ sessions since midnight", tool)}>
          <div className="usage-today-hero">
            <span className="kit-metric">{compactTokens(totalTokens(periodTokens(stats.today)))}</span>
            <span className="usage-today-unit">{tr("tokens")}</span>
          </div>
        </Tooltip>
        <span className="usage-today-spacer" />
        <Row title={tr("Messages")} value={new Intl.NumberFormat(locale).format(periodMessages(stats.today))} />
        <Row title={tr("Top model")} value={top === undefined ? tr("None yet") : modelName(top)} />
        <Row title={tr("Last 7 days")} value={tr("%@ tokens", week)} />
      </>
    );
  } else {
    body = (
      <div className="usage-today-loading">
        <Spinner tint="var(--accent)" />
        <span>{tr("Reading %@ sessions…", tool)}</span>
      </div>
    );
  }
  return (
    <Card className="usage-today">
      <span className="usage-today-caption">{tr("Today in %@", tool)}</span>
      {body}
    </Card>
  );
}

/** The title stays whole; a long value scrolls rather than clipping. */
function Row({ title, value }: { readonly title: string; readonly value: string }) {
  return (
    <div className="usage-row">
      <span className="usage-row-title">{title}</span>
      <span className="usage-row-value">
        <MarqueeText text={value} />
      </span>
    </div>
  );
}

/** Shown in place of the rings when the source's CLI can't be found. */
function CLIMissingCard({ source }: { readonly source: AIUsageSource }) {
  const tool = usageToolName(source);
  const explanation =
    source === "codex"
      ? tr("Install Codex and sign in with ChatGPT to see your 5-hour and weekly limits.")
      : tr("Install Claude Code and sign in to see your live 5-hour and weekly limits.");
  /* Where the data comes from, with the folder or variable in monospace. */
  const note = source === "codex" ? tr("Tabbi reads %@ and sends nothing.", "\u0000") : tr("Installed elsewhere? Set %@ to its path.", "\u0000");
  const [before, after] = note.split("\u0000");
  const path = source === "codex" ? "%USERPROFILE%\\.codex\\sessions" : CLAUDE_OVERRIDE_VARIABLE;
  return (
    <Card className="usage-missing">
      <span className="usage-missing-title">
        <Icon id="terminal" size={14} />
        <MarqueeText text={tr("%@ not found", tool)} />
      </span>
      <span className="usage-missing-body">{explanation}</span>
      <span className="usage-missing-spacer" />
      <span className="usage-missing-note">
        {before}
        <code>{path}</code>
        {after}
      </span>
    </Card>
  );
}

interface UsageFooterProps {
  readonly source: AIUsageSource;
  readonly cliStatus: CLIStatus;
  readonly isFetching: boolean;
  readonly probeError: string | undefined;
  readonly updated: string | undefined;
  readonly onRefresh: () => void;
}

/** Freshness, read warnings, and the refresh button. */
function UsageFooter({ source, cliStatus, isFetching, probeError, updated, onRefresh }: UsageFooterProps) {
  const tool = usageToolName(source);
  let status: string;
  if (isFetching) {
    status = source === "codex" ? tr("Reading Codex logs…") : tr("Reading %@ sessions…", tool);
  } else if (probeError !== undefined) {
    status = updated === undefined ? probeError : tr("Refresh failed · %@", updated);
  } else if (updated !== undefined) {
    status = updated;
  } else if (cliStatus === "locating") {
    status = tr("Looking for %@…", tool);
  } else if (cliStatus === "missing") {
    status = tr("Showing local stats only");
  } else {
    /* Windows runs no live probe yet, so Claude Code only ever shows local stats until a snapshot exists. */
    status = source === "codex" ? tr("No limits in your Codex logs yet") : tr("Showing local stats only");
  }
  const footer = (
    <div className="usage-footer">
      {probeError !== undefined && !isFetching && <Icon id="exclamationmark.triangle.fill" size={11} className="usage-footer-warning" />}
      <MarqueeText className="usage-footer-status" text={status} />
      {cliStatus !== "missing" && (
        <IconButton
          symbol="arrow.clockwise"
          size={24}
          help={source === "codex" ? tr("Read the latest Codex logs (sends nothing)") : tr("Read the latest %@ sessions (sends nothing)", tool)}
          spinning={isFetching}
          disabled={isFetching}
          onClick={onRefresh}
        />
      )}
    </div>
  );
  return probeError === undefined ? footer : <Tooltip text={probeError}>{footer}</Tooltip>;
}
