/*
 * Port of SystemPanel: three equal cards (CPU, GPU, Memory), each with a
 * headline figure, a 60-second sparkline and a one-line footer. Sampling
 * only runs while the panel is on screen. Readings change every second, so
 * they are drawn without animation, as on the Mac: a spring on each sample
 * would keep the panel redrawing every frame. Windows has no thermal state
 * to report, so the CPU card's header shows the core count only.
 */

import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import type { HistorySeries } from "../../core/system/history";
import { type MemoryPressure, type MemoryStats, usedFraction } from "../../core/system/memoryStats";
import { gigabytes, memorySummary, percent, UNAVAILABLE } from "../../core/system/systemFormat";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { Placeholder } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { ProgressBar } from "../../ui/kit/ProgressBar";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { SystemStore } from "./systemStore";
import "./system.css";

export function SystemPanel({ store }: { store: SystemStore }) {
  const state = useStore(store);
  useEffect(() => {
    store.setPanelVisible(true);
    return () => store.setPanelVisible(false);
  }, [store]);
  const memory = state.memory;
  return (
    <div className="system-panel">
      <MetricCard
        title="CPU"
        symbol="cpu"
        value={state.cpu ? percent(state.cpu.total) : undefined}
        series={state.cpuSeries}
        help={tr("Total CPU usage across all cores, last 60 seconds")}
        accessory={state.cpu ? tr("%lld cores", state.cpu.perCore.length) : undefined}
        footer={<CoreStrip perCore={state.cpu?.perCore ?? []} />}
      />
      <MetricCard
        title="GPU"
        symbol="square.stack.3d.up"
        value={percent(state.gpu)}
        series={state.gpuSeries}
        help={tr("GPU utilization, last 60 seconds")}
        footer={
          state.gpu === undefined && state.gpuSeries.isEmpty ? (
            <FooterCaption text={tr("Not reported by this PC")} />
          ) : (
            <FooterCaption text={tr("Peak %@  ·  Avg %@", percent(state.gpuSeries.peak), percent(state.gpuSeries.average))} />
          )
        }
      />
      <MetricCard
        title={tr("Memory")}
        symbol="memorychip"
        value={memory ? gigabytes(memory.usedBytes, true) : UNAVAILABLE}
        unit={memory ? tr("GB") : undefined}
        series={state.memorySeries}
        help={memory ? tr("Memory in use: %@", memorySummary(memory)) : tr("Memory in use and memory pressure")}
        accessory={memory ? tr("of %@ GB", gigabytes(memory.totalBytes)) : undefined}
        /* The narrow Compact card drops the "of" before the title would clip. */
        accessoryShort={memory ? tr("%@ GB", gigabytes(memory.totalBytes)) : undefined}
        footer={<PressureBar memory={memory} />}
      />
    </div>
  );
}

interface MetricCardProps {
  readonly title: string;
  readonly symbol: string;
  /**
   * Undefined while the first reading is still being taken: the figure shows
   * as a placeholder bar of the same size, so the card neither jumps nor
   * shows a lone "-" for the second it takes.
   */
  readonly value: string | undefined;
  readonly unit?: string;
  readonly series: HistorySeries;
  readonly help: string;
  readonly accessory?: string;
  /** A shorter accessory for when the long one does not fit beside the title. */
  readonly accessoryShort?: string;
  readonly footer: ReactNode;
}

/** Shared card layout so the three cards line up row for row. */
function MetricCard({ title, symbol, value, unit, series, help, accessory, accessoryShort, footer }: MetricCardProps) {
  const unavailable = value === undefined || value === UNAVAILABLE;
  return (
    <Tooltip text={help}>
      <Card className="system-card">
        <div className="system-card-header kit-caption">
          <span className="system-card-symbol">
            <Icon id={symbol} size={12} />
          </span>
          <span className="system-card-title">{title}</span>
          {accessory !== undefined && <Accessory long={accessory} short={accessoryShort ?? accessory} />}
        </div>
        <div className="system-card-value">
          {value === undefined ? (
            <Placeholder width={44} height={14} className="system-card-placeholder" />
          ) : (
            <span className={["kit-metric", unavailable ? "kit-tertiary" : ""].filter(Boolean).join(" ")}>{value}</span>
          )}
          {unit !== undefined && <span className="kit-body-emphasis kit-secondary">{unit}</span>}
        </div>
        <Sparkline series={series} />
        <div className="system-card-footer">{footer}</div>
      </Card>
    </Tooltip>
  );
}

/** The header's trailing caption, falling back to its short form when the long one would overflow (the Mac's ViewThatFits). */
function Accessory({ long, short }: { long: string; short: string }) {
  const element = useRef<HTMLSpanElement>(null);
  const probe = useRef<HTMLSpanElement>(null);
  const [fits, setFits] = useState(true);
  useLayoutEffect(() => {
    const node = element.current;
    const measure = probe.current;
    if (!node || !measure) return;
    const check = () => setFits(measure.offsetWidth <= node.clientWidth + 0.5);
    check();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(check);
    observer.observe(node);
    return () => observer.disconnect();
  }, [long]);
  return (
    <span ref={element} className="system-card-accessory kit-tertiary">
      <span className="system-card-accessory-text">{fits ? long : short}</span>
      {/* The long form, hidden, is what the room is measured against. */}
      <span ref={probe} className="system-card-accessory-probe" aria-hidden="true">
        {long}
      </span>
    </span>
  );
}

/**
 * Area + line chart on a fixed 0-100% scale so cards compare at a glance.
 * Empty history draws a dashed baseline instead of a blank gap; it is only
 * empty for the second or two after the panel opens, so it carries no
 * caption of its own. Drawn in plot units (slots across, 0 to 1 up) and
 * stretched to the card, with strokes that keep their width.
 */
function Sparkline({ series }: { series: HistorySeries }) {
  const fillId = useId();
  const span = Math.max(series.capacity - 1, 1);
  if (series.points.length < 2) {
    return (
      <div className="system-sparkline" aria-hidden="true">
        <svg viewBox={`0 0 ${span} 1`} preserveAspectRatio="none">
          <line x1={0} y1={1} x2={span} y2={1} className="system-sparkline-baseline" />
        </svg>
      </div>
    );
  }
  const first = series.points[0];
  const last = series.points[series.points.length - 1];
  if (first === undefined || last === undefined) return null;
  const y = (value: number) => 1 - value;
  let line = `M ${first.x} ${y(first.y)}`;
  for (const segment of series.monotoneCurve) {
    line += ` C ${segment.control1.x} ${y(segment.control1.y)}, ${segment.control2.x} ${y(segment.control2.y)}, ${segment.end.x} ${y(segment.end.y)}`;
  }
  const area = `${line} L ${last.x} 1 L ${first.x} 1 Z`;
  return (
    <div className="system-sparkline" aria-hidden="true">
      <svg viewBox={`0 0 ${span} 1`} preserveAspectRatio="none">
        <defs>
          <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--accent)" stopOpacity={0.32} />
            <stop offset="1" stopColor="var(--accent)" stopOpacity={0.02} />
          </linearGradient>
        </defs>
        {/* A faint 50% rule gives low readings a sense of scale. */}
        <line x1={0} y1={0.5} x2={span} y2={0.5} className="system-sparkline-rule" />
        <path d={area} fill={`url(#${fillId})`} />
        <path d={line} className="system-sparkline-line" />
      </svg>
    </div>
  );
}

/** One tiny bar per core, filled bottom-up with that core's load. */
function CoreStrip({ perCore }: { perCore: readonly number[] }) {
  if (perCore.length === 0) return <FooterCaption text={tr("Measuring cores...")} />;
  return (
    <div className="system-cores" aria-hidden="true">
      {perCore.map((value, index) => {
        const load = Math.min(Math.max(value, 0), 1);
        return (
          <span key={index} className="system-core">
            <span className="system-core-fill" style={{ height: Math.max(2, 14 * load), opacity: 0.55 + 0.45 * load }} />
          </span>
        );
      })}
    </div>
  );
}

function pressureColor(pressure: MemoryPressure): string {
  switch (pressure) {
    case "normal":
      return "var(--success)";
    case "warning":
      return "var(--warning)";
    case "critical":
      return "var(--danger)";
  }
}

/** The pressure's name in the user's language; the Mac keeps these in code, so the keys are Windows-only. */
function pressureLabel(pressure: MemoryPressure): string {
  switch (pressure) {
    case "normal":
      return tr("Normal");
    case "warning":
      return tr("Elevated");
    case "critical":
      return tr("Critical");
  }
}

/** Used-memory bar colored by memory pressure. */
function PressureBar({ memory }: { memory: MemoryStats | undefined }) {
  if (memory === undefined) return <FooterCaption text={tr("Memory stats unavailable")} />;
  const color = pressureColor(memory.pressure);
  const label = pressureLabel(memory.pressure);
  const help = tr("Memory pressure: %@", label);
  return (
    <Tooltip text={help}>
      <div className="system-pressure">
        <ProgressBar value={usedFraction(memory)} tint={color} label={tr("Memory")} valueText={`${memorySummary(memory)}, ${label}`} still />
        <span className="kit-caption system-pressure-label" style={{ color }}>
          {label}
        </span>
      </div>
    </Tooltip>
  );
}

/** A footer line that scrolls rather than clips when a translation runs long. */
function FooterCaption({ text }: { text: string }) {
  return <MarqueeText className="system-footer-caption kit-caption kit-tertiary" text={text} />;
}
