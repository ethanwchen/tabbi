/*
 * Port of NotchPreview: the live preview in the two wings of the closed
 * pill, an icon (or artwork, a pet, a ring) on the leading side and short
 * text on the trailing side, either side of the empty middle where the Mac
 * keeps its camera. As the ticker rotates, the new item rises in from below
 * and the old one leaves upward, fading (the Mac's row transition), and the
 * pill's width follows on the content spring. Under Reduce Motion the items
 * only crossfade.
 */

import { useState, type CSSProperties, type ReactNode } from "react";
import type { MusicWings } from "../../app/module";
import type { ModuleCatalog } from "../../core/modules/moduleCatalog";
import type { Instant } from "../../core/time";
import {
  meetingOffersJoin,
  tickerFocusProgress,
  tickerItemKind,
  tickerItemModule,
  tickerPetIsSipping,
  tickerPetUnlockHint,
  type TickerItem,
} from "../../core/ticker/tickerItem";
import {
  tickerCharging,
  tickerFocusClock,
  tickerMeetingCountdown,
  tickerPartySize,
  tickerPetExploring,
  tickerPetLabel,
  tickerProgressLeft,
  tickerTasksLeft,
  TICKER_PET_SLEEPING,
} from "../../core/ticker/tickerFormat";
import type { TickerHighlightTone } from "../../core/providers/tickerHighlight";
import { tr } from "../../core/localization/tr";
import { useTheme } from "../kit/context";
import { Icon } from "../kit/Icon";
import { ProgressRing } from "../kit/Loading";
import { MarqueeText } from "../kit/MarqueeText";
import { PetView } from "../kit/PetView";
import { accentVariables } from "../kit/tokens";
import { VIRTUAL_NOTCH } from "./geometry";
import { PREVIEW, previewSummary, previewSymbol } from "./previewLayout";

export interface ClosedPreviewProps {
  readonly item: TickerItem;
  readonly wing: number;
  readonly catalog: ModuleCatalog;
  readonly now: Instant;
  readonly locale: string;
  /** The playing module's own music wings, if it draws them. */
  readonly musicWings?: MusicWings;
  /** Opens a meeting's call from the Join button. */
  readonly onJoin?: (url: string) => void;
}

/** One preview, with the item that just left kept until its exit has played. */
export function ClosedPreview(props: ClosedPreviewProps) {
  const kind = tickerItemKind(props.item);
  const [leaving, setLeaving] = useState<{ kind: string; props: ClosedPreviewProps } | undefined>(undefined);
  const [current, setCurrent] = useState<{ kind: string; props: ClosedPreviewProps }>({ kind, props });
  if (current.kind !== kind) {
    setLeaving(current);
    setCurrent({ kind, props });
  } else if (current.props !== props) {
    setCurrent({ kind, props });
  }
  return (
    <div className="preview-stage">
      {leaving !== undefined && (
        <PreviewRow key={`out-${leaving.kind}`} {...leaving.props} phase="out" onDone={() => setLeaving(undefined)} />
      )}
      <PreviewRow key={`in-${kind}`} {...props} phase={leaving === undefined ? "rest" : "in"} />
    </div>
  );
}

function toneColor(tone: TickerHighlightTone): string {
  switch (tone) {
    case "accent":
      return "var(--accent)";
    case "primary":
      return "var(--primary-text)";
    case "secondary":
      return "var(--secondary-text)";
    case "danger":
      return "var(--danger)";
  }
}

function PreviewRow({ item, wing, catalog, now, locale, musicWings, onJoin, phase, onDone }: ClosedPreviewProps & { phase: "in" | "out" | "rest"; onDone?: () => void }) {
  const theme = useTheme();
  const accent = catalog.descriptor(tickerItemModule(item)).accent;
  const isMusic = item.type === "nowPlaying";
  const nudging = item.type === "meeting" && item.meeting.isNudging;
  return (
    <div
      className="preview-row"
      data-phase={phase}
      data-music={isMusic || undefined}
      data-nudging={nudging || undefined}
      title={previewSummary(item, now, locale)}
      style={accentVariables(theme, accent) as CSSProperties}
      onAnimationEnd={phase === "out" ? onDone : undefined}
    >
      <div className="wing leading" style={{ width: wing }}>
        <Leading item={item} catalog={catalog} musicWings={musicWings} />
      </div>
      <div className="wing-gap" style={{ width: VIRTUAL_NOTCH.width }} />
      <div className="wing trailing" style={{ width: wing }}>
        <Trailing item={item} locale={locale} musicWings={musicWings} onJoin={onJoin} />
      </div>
    </div>
  );
}

function PreviewIcon({ symbol }: { symbol: string }) {
  return (
    <span className="preview-icon" style={{ width: PREVIEW.iconSize, height: PREVIEW.iconSize }}>
      <Icon id={symbol} size={13} />
    </span>
  );
}

function Leading({ item, catalog, musicWings }: { item: TickerItem; catalog: ModuleCatalog; musicWings?: MusicWings }): ReactNode {
  const symbol = previewSymbol(item, catalog);
  switch (item.type) {
    case "nowPlaying":
      return musicWings ? <musicWings.Leading /> : <PreviewIcon symbol={symbol} />;
    case "pet":
      return <PetView profile={item.pet.profile} pixelSize={1} className="preview-pet" />;
    case "party":
      return (
        <span className="preview-party" style={{ width: PREVIEW.partyPetStep * (item.party.pets.length - 1) + 24 }}>
          {item.party.pets.map((pet, index) => (
            <span key={pet.id} className="preview-party-pet" data-away={pet.isAway || undefined} style={{ insetInlineStart: index * PREVIEW.partyPetStep, zIndex: item.party.pets.length - index }}>
              <PetView profile={pet.pet} pixelSize={PREVIEW.partyPetPixelSize} />
            </span>
          ))}
        </span>
      );
    case "meeting":
      return (
        <span className="preview-pair">
          <PreviewIcon symbol={symbol} />
          <span className="preview-text accent">{tickerMeetingCountdown(item.meeting.timing)}</span>
        </span>
      );
    case "focus": {
      const progress = tickerFocusProgress(item.focus);
      if (progress === undefined) return <PreviewIcon symbol={symbol} />;
      const tint = item.focus.isRunning ? "var(--accent)" : "var(--secondary-text)";
      return (
        <span className="preview-icon" style={{ width: PREVIEW.iconSize, height: PREVIEW.iconSize }}>
          <ProgressRing progress={progress} tint={tint} lineWidth={PREVIEW.focusRingWidth} size={PREVIEW.iconSize - 2}>
            <span style={{ color: tint, display: "grid" }}>
              <Icon id={symbol} size={9} />
            </span>
          </ProgressRing>
        </span>
      );
    }
    default:
      return <PreviewIcon symbol={symbol} />;
  }
}

function Trailing({ item, locale, musicWings, onJoin }: { item: TickerItem; locale: string; musicWings?: MusicWings; onJoin?: (url: string) => void }): ReactNode {
  switch (item.type) {
    case "nowPlaying":
      return musicWings ? <musicWings.Trailing /> : <Equalizer />;
    case "meeting": {
      const link = item.meeting.link;
      return (
        <span className="preview-pair">
          <MarqueeText className="preview-text title" text={item.meeting.title} />
          {meetingOffersJoin(item.meeting) && link !== undefined && (
            <button type="button" className="preview-join" title={tr("Join")} onClick={() => onJoin?.(link.url)}>
              {tr("Join")}
            </button>
          )}
        </span>
      );
    }
    case "focus":
      return <span className={`preview-text ${item.focus.isRunning ? "accent" : "secondary"}`}>{tickerFocusClock(item.focus.time)}</span>;
    case "tasks":
      return <span className="preview-text">{tickerTasksLeft(item.remaining)}</span>;
    case "progress":
      return <span className="preview-text">{tickerProgressLeft(item.item, locale)}</span>;
    case "highlight":
      return <MarqueeText className="preview-text" text={item.highlight.text} style={{ color: toneColor(item.highlight.tone) }} />;
    case "pet": {
      if (tickerPetIsSipping(item.pet)) {
        return (
          <span className="preview-pair success">
            <Icon id="power" size={PREVIEW.chargingSymbolSize} />
            <span className="preview-text">{tickerCharging()}</span>
          </span>
        );
      }
      const name = tickerPetLabel(item.pet);
      const state = item.pet.mood === "asleep" ? TICKER_PET_SLEEPING : item.pet.adventure !== undefined ? tickerPetExploring() : undefined;
      const unlock = state === undefined ? tickerPetUnlockHint(item.pet) : undefined;
      return (
        <span className="preview-pair">
          {name !== undefined && <span className={`preview-text ${item.pet.mood === "asleep" ? "secondary" : ""}`}>{name}</span>}
          {state !== undefined && <span className="preview-text tertiary">{state}</span>}
          {unlock !== undefined && (
            <span className="unlock-hint" aria-hidden="true">
              <span style={{ width: `${Math.max(0.15, Math.min(1, unlock.fraction)) * 100}%` }} />
            </span>
          )}
        </span>
      );
    }
    case "party":
      return <span className="preview-text accent">{tickerPartySize(item.party.memberCount)}</span>;
  }
}

/** The shared music glyph's partner: three bars that rest still (the playing module draws a live one). */
function Equalizer() {
  return (
    <span className="equalizer" aria-hidden="true">
      <span />
      <span />
      <span />
    </span>
  );
}
