/*
 * Port of CrewComponents: the small building blocks of the Party tab's Crew
 * section: a crew's icon in its color with this week's laurel, the Party or
 * Crew switch, the invite button, the text field, a member's pet (or the
 * quiet silhouette when they hid it), the board's rank badge, and
 * `FirstThatFits`, the Mac's ViewThatFits over whole views.
 */

import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { crewInviteWebURL, crewPetColor, resolvedCrewColor } from "../../core/crews/crewCatalog";
import { CREW_ICON_REGULAR_PIXEL_SIZE, crewIconBitmap, crewIconScale, crewIconSet } from "../../core/crews/crewIconArt";
import { crewRank } from "../../core/crews/crewFormat";
import { memberPartyProfile, type CrewLaurel, type CrewMember, type CrewSummary } from "../../core/crews/crewModels";
import { tr } from "../../core/localization/tr";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { Tooltip } from "../../ui/kit/Tooltip";
import { copyText, PartyPet } from "./PartyComponents";
import type { CrewsStore } from "./crewsStore";

/** The device pixel ratio, kept current as the window moves between screens. */
function useDevicePixelRatio(): number {
  const [ratio, setRatio] = useState(() => (typeof window === "undefined" ? 1 : window.devicePixelRatio || 1));
  useLayoutEffect(() => {
    const update = () => setRatio(window.devicePixelRatio || 1);
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);
  return ratio;
}

/** The box a crew icon takes in the layout at `pixelSize` CSS px per sprite pixel. */
export function crewIconSide(pixelSize: number): number {
  return crewIconSet().canvas * pixelSize;
}

/** A crew's icon in its color, with the laurel it wears this week, drawn at whole device pixels like the Goals badges. */
export function CrewIconView({ icon, color, laurel, pixelSize = CREW_ICON_REGULAR_PIXEL_SIZE }: { icon: string; color: string; laurel?: CrewLaurel | undefined; pixelSize?: number }) {
  const element = useRef<HTMLCanvasElement>(null);
  const ratio = useDevicePixelRatio();
  useLayoutEffect(() => {
    const canvas = element.current;
    if (!canvas) return;
    /* The large panel scales its content as a whole (--panel-scale); the box divides that out so the icon lands on whole device pixels. */
    const panelScale = Number.parseFloat(getComputedStyle(canvas).getPropertyValue("--panel-scale")) || 1;
    const scale = crewIconScale(pixelSize * panelScale, ratio);
    const side = crewIconSet().canvas;
    const css = (side * scale) / ratio / panelScale;
    canvas.width = side * scale;
    canvas.height = side * scale;
    canvas.style.width = `${css}px`;
    canvas.style.height = `${css}px`;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.imageSmoothingEnabled = false;
    const bitmap = crewIconBitmap(icon, crewPetColor(resolvedCrewColor(color)), laurel, scale);
    const image = context.createImageData(bitmap.width, bitmap.height);
    image.data.set(bitmap.data);
    context.putImageData(image, 0, 0);
  }, [icon, color, laurel, pixelSize, ratio]);
  const side = crewIconSide(pixelSize);
  return (
    <span className="crew-icon" style={{ width: side, height: side }} aria-hidden="true">
      <canvas ref={element} className="crew-icon-canvas" />
    </span>
  );
}

export function CrewSummaryIcon({ crew, pixelSize }: { crew: CrewSummary; pixelSize?: number }) {
  return <CrewIconView icon={crew.icon} color={crew.color} laurel={crew.laurel} {...(pixelSize === undefined ? {} : { pixelSize })} />;
}

/**
 * The first of `candidates` that fits its container, along `axis`; the last
 * one shows whatever the room. The candidates are measured off screen in a
 * layout pass before paint, and again when the container resizes.
 */
export function FirstThatFits({ candidates, axis = "horizontal", className }: { candidates: readonly ReactNode[]; axis?: "horizontal" | "vertical"; className?: string }) {
  const container = useRef<HTMLDivElement>(null);
  const [chosen, setChosen] = useState(0);
  useLayoutEffect(() => {
    const element = container.current;
    if (!element) return;
    const measure = () => {
      const probes = [...element.querySelectorAll<HTMLElement>(":scope > .crew-fits-probe")];
      const room = axis === "horizontal" ? element.clientWidth : element.clientHeight;
      let index = probes.length - 1;
      for (let i = 0; i < probes.length; i++) {
        const probe = probes[i];
        if (!probe) continue;
        const size = axis === "horizontal" ? probe.scrollWidth : probe.scrollHeight;
        if (size <= room + 0.5) {
          index = i;
          break;
        }
      }
      setChosen(Math.max(index, 0));
    };
    measure();
    let cancelled = false;
    void document.fonts?.ready.then(() => {
      if (!cancelled) measure();
    });
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => {
      cancelled = true;
      observer.disconnect();
    };
  });
  return (
    <div ref={container} className={["crew-fits", `crew-fits-${axis}`, className].filter(Boolean).join(" ")}>
      {candidates.map((candidate, index) => (
        <div key={index} className="crew-fits-probe" aria-hidden="true">
          {candidate}
        </div>
      ))}
      <div className="crew-fits-shown">{candidates[Math.min(chosen, candidates.length - 1)]}</div>
    </div>
  );
}

/** The two-way switch at the Party tab's top left: the party and friends, or the Crew section. `showsTitles` spells out the words; the caller decides from the room its row has. */
export function PartySectionSwitch({ crews, showsTitles }: { crews: CrewsStore; showsTitles: boolean }) {
  const showsCrews = useStore(crews, (state) => state.showsCrews);
  return (
    <div className="party-section-switch" role="tablist">
      <SectionSegment title={tr("Party")} symbol="person.3.fill" titles={showsTitles} selected={!showsCrews} help={tr("Your party and friends")} onClick={() => crews.setShowsCrews(false)} />
      <SectionSegment title={tr("Crew")} symbol="flag.fill" titles={showsTitles} selected={showsCrews} help={tr("Your study crew and the weekly top 3")} onClick={() => crews.setShowsCrews(true)} />
    </div>
  );
}

function SectionSegment({ title, symbol, titles, selected, help, onClick }: { title: string; symbol: string; titles: boolean; selected: boolean; help: string; onClick: () => void }) {
  return (
    <Tooltip text={help}>
      <button type="button" role="tab" aria-selected={selected} aria-label={title} className="party-section-segment kit-caption" data-selected={selected || undefined} onClick={onClick}>
        {titles ? title : <Icon id={symbol} size={10} />}
      </button>
    </Tooltip>
  );
}

/** A small round icon button in the Party style, for Back, Find and Report. */
export function CrewIconButton({ symbol, help, busy = false, onClick }: { symbol: string; help: string; busy?: boolean; onClick: () => void }) {
  return <IconButton symbol={symbol} size={20} help={help} tint="var(--accent)" className="crew-icon-button" disabled={busy} onClick={onClick} />;
}

/** Copies my crew's invite link and confirms with a check. */
export function CrewInviteButton({ code, showsTitle }: { code: string; showsTitle: boolean }) {
  const [copied, setCopied] = useState(false);
  useLayoutEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1500);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return (
    <Tooltip text={copied ? tr("Copied") : tr("Copy the invite link. Friends who open it can join your crew.")}>
      <button type="button" className="crew-invite-button kit-caption" data-copied={copied || undefined} onClick={() => void copyText(crewInviteWebURL(code)).then((ok) => setCopied(ok))}>
        <Icon id={copied ? "checkmark" : "link"} size={10} />
        {showsTitle && <span>{copied ? tr("Copied") : tr("Invite")}</span>}
      </button>
    </Tooltip>
  );
}

/** A one-line text field in the Party look: Enter submits, Esc clears (or leaves an empty field). */
export function CrewTextField({
  placeholder,
  value,
  limit,
  symbol,
  help,
  onChange,
  onSubmit,
}: {
  placeholder: string;
  value: string;
  limit: number;
  symbol?: string;
  help: string;
  onChange: (value: string) => void;
  onSubmit?: () => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [focused, setFocused] = useState(false);
  return (
    <Tooltip text={help}>
      <div className="crew-text-field" data-focused={focused || undefined} onClick={() => input.current?.focus()}>
        {symbol !== undefined && <Icon id={symbol} size={11} className="crew-text-field-symbol" />}
        <input
          ref={input}
          className="crew-text-field-input kit-body"
          aria-label={placeholder}
          placeholder={placeholder}
          value={value}
          spellCheck={false}
          autoComplete="off"
          onChange={(event) => onChange([...event.target.value].slice(0, limit).join(""))}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              onSubmit?.();
            } else if (event.key === "Escape") {
              event.preventDefault();
              if (value === "") input.current?.blur();
              else onChange("");
            }
          }}
        />
      </div>
    </Tooltip>
  );
}

/** A member's pet, or a quiet silhouette when they hid it from crew pages. */
export function CrewMemberPet({ member, pixelSize = 1 }: { member: CrewMember; pixelSize?: number }) {
  const profile = memberPartyProfile(member);
  if (profile !== undefined) return <PartyPet profile={profile} pixelSize={pixelSize} />;
  return (
    <Tooltip text={tr("%@ keeps their pet private on crew pages.", member.name)}>
      <span className="crew-hidden-pet" style={{ width: 40 * pixelSize, height: 40 * pixelSize }}>
        <span className="crew-hidden-pet-disc" style={{ width: 30 * pixelSize, height: 30 * pixelSize }}>
          <Icon id="pawprint.fill" size={14 * pixelSize} />
        </span>
      </span>
    </Tooltip>
  );
}

const RANK_COLORS = ["rgb(242, 194, 79)", "rgb(199, 209, 222)", "rgb(217, 148, 92)"];

export function rankColor(rank: number): string {
  return RANK_COLORS[rank - 1] ?? "rgb(128, 128, 128)";
}

/** The medal-colored rank on the board: 1 gold, 2 silver, 3 bronze. */
export function CrewRankBadge({ rank }: { rank: number }) {
  return (
    <span className="crew-rank-badge" style={{ background: rankColor(rank) }} aria-label={crewRank(rank)}>
      {rank}
    </span>
  );
}
