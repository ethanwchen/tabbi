/*
 * Port of CrewComponents: the small building blocks of the Crews screens,
 * measured from the Crews UI spec (runs/crews/ui-design/spec.md):
 * Closet-style pills, crests, pixel medals and tallies, place chips, the
 * pet groups, whole-row lists and the friendly states, and `FirstThatFits`,
 * the Mac's ViewThatFits over whole views.
 */

import { createContext, useContext, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from "react";
import { crewInviteWebURL } from "../../core/crews/crewCatalog";
import {
  CREW_CREST_COMPACT_PIXEL_SIZE,
  CREW_CREST_REGULAR_PIXEL_SIZE,
  CREW_MEDAL_HEIGHT,
  CREW_MEDAL_WIDTH,
  crestEmblem,
  crewCrestArt,
  crewCrestBitmap,
  crewCrestScale,
  crewEmblemBitmap,
  crewMedalBitmap,
  type CrewCrest,
} from "../../core/crews/crewCrestArt";
import { crewOrdinal } from "../../core/crews/crewFormat";
import { crewCrest, crewPetProfile, crewPips, type CrewLaurel, type CrewMedals, type CrewPet, type CrewSummary } from "../../core/crews/crewModels";
import { tr } from "../../core/localization/tr";
import type { PetBitmap } from "../../core/pets/petRenderer";
import { Icon } from "../../ui/kit/Icon";
import { Tooltip } from "../../ui/kit/Tooltip";
import { copyText, PartyPet } from "./PartyComponents";

/** The Crews layout's fixed sizes, from the spec. */
export const CrewLayout = {
  /** Every list row. */
  rowHeight: 32,
  /** The pill row at the top of every Crews screen. */
  headHeight: 22,
  /** Between the pill row and the screen body. */
  headGap: 6,
  /** A featured tile's width at Regular and Large. */
  tileWidth: 80,
  /** The side column of My crew and a crew page. */
  sideWidth: 168,
  /** The crest editor's side column. */
  editorSideWidth: 160,
  /** The "+N more" caption under a list. */
  moreHeight: 14,
  /** The pinned row and the hairline above it. */
  pinnedHeight: 32 + 6,
} as const;

/** The card's inner width below which the Crews screens take their Compact form (Compact is 432, Regular 480, Large 496 before scaling). */
export const CREW_COMPACT_WIDTH = 456;

/** Whether the Crews screens show in the Compact panel: the featured tiles fold into the list. */
export const CrewCompactContext = createContext(false);

export function useCrewIsCompact(): boolean {
  return useContext(CrewCompactContext);
}

/* MARK: Pixel art */

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

/**
 * Pixel art drawn crisp: a whole number of device pixels per sprite pixel,
 * never mirrored in right-to-left layouts. The large panel scales its
 * content as a whole (--panel-scale), so the canvas divides that out to land
 * on whole device pixels inside a box of `width` by `height` at `pixelSize`.
 */
export function CrewPixelImage({
  width,
  height,
  pixelSize,
  bitmap,
  deps,
  limit,
  className,
  style,
}: {
  width: number;
  height: number;
  pixelSize: number;
  bitmap: (scale: number) => PetBitmap;
  deps: readonly unknown[];
  /** A side in CSS px the art never outgrows when rounding to whole device pixels goes up (1.5 px per sprite pixel on a 100 percent display). */
  limit?: number;
  className?: string;
  style?: CSSProperties;
}) {
  const element = useRef<HTMLCanvasElement>(null);
  const ratio = useDevicePixelRatio();
  useLayoutEffect(() => {
    const canvas = element.current;
    if (!canvas) return;
    const panelScale = Number.parseFloat(getComputedStyle(canvas).getPropertyValue("--panel-scale")) || 1;
    const rounded = crewCrestScale(pixelSize * panelScale, ratio);
    const scale = limit === undefined ? rounded : Math.max(1, Math.min(rounded, Math.floor((limit * ratio * panelScale) / Math.max(width, height))));
    const drawn = bitmap(scale);
    canvas.width = drawn.width;
    canvas.height = drawn.height;
    canvas.style.width = `${drawn.width / ratio / panelScale}px`;
    canvas.style.height = `${drawn.height / ratio / panelScale}px`;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.imageSmoothingEnabled = false;
    const image = context.createImageData(drawn.width, drawn.height);
    image.data.set(drawn.data);
    context.putImageData(image, 0, 0);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `deps` names what the bitmap is drawn from
  }, [pixelSize, ratio, limit, width, height, ...deps]);
  return (
    <span className={["crew-pixels", className].filter(Boolean).join(" ")} style={{ width: width * pixelSize, height: height * pixelSize, ...style }} aria-hidden="true">
      <canvas ref={element} />
    </span>
  );
}

/** The box a crest takes in the layout at `pixelSize` CSS px per sprite pixel. */
export function crewCrestSide(pixelSize: number): number {
  return crewCrestArt().grid * pixelSize;
}

/** A crew's crest with its laurel and gold pips: 32 px in rows (1 px per sprite pixel), 48 px on the hero and the editor preview. */
export function CrewCrestView({ crest, laurel, pips = 0, pixelSize = CREW_CREST_COMPACT_PIXEL_SIZE }: { crest: CrewCrest; laurel?: CrewLaurel | undefined; pips?: number; pixelSize?: number }) {
  const side = crewCrestArt().grid;
  return (
    <CrewPixelImage
      className="crew-crest"
      width={side}
      height={side}
      pixelSize={pixelSize}
      bitmap={(scale) => crewCrestBitmap(crest, laurel, pips, scale)}
      deps={[crest.frame, crest.emblem, crest.color, laurel, pips]}
    />
  );
}

/** A crew's crest with its laurel; the hero size also shows its gold pips. */
export function CrewSummaryCrest({ crew, hero = false, laurel = true }: { crew: CrewSummary; hero?: boolean; laurel?: boolean }) {
  return (
    <CrewCrestView
      crest={crewCrest(crew)}
      laurel={laurel ? crew.laurel : undefined}
      pips={hero ? crewPips(crew) : 0}
      pixelSize={hero ? CREW_CREST_REGULAR_PIXEL_SIZE : CREW_CREST_COMPACT_PIXEL_SIZE}
    />
  );
}

/** An emblem alone, in the crew color's outline, as large as fits a 24 px option. */
export function CrewEmblemView({ emblem, color }: { emblem: string; color: string }) {
  const shown = crestEmblem(emblem);
  /* Half-point steps, as the hero crest: 1.5 px per sprite pixel for a 15 px emblem (22.5 px in the 24 px option, whole device pixels at 2x), 1 for a 24 px one. */
  const pixelSize = Math.max(1, Math.floor(48 / Math.max(shown.width, shown.height)) / 2);
  return <CrewPixelImage width={shown.width} height={shown.height} pixelSize={pixelSize} limit={24} bitmap={(scale) => crewEmblemBitmap(emblem, color, scale)} deps={[emblem, color]} />;
}

/** One pixel medal. */
export function CrewMedalView({ metal, pixelSize = 1, className }: { metal: CrewLaurel; pixelSize?: number; className?: string }) {
  return <CrewPixelImage className={className} width={CREW_MEDAL_WIDTH} height={CREW_MEDAL_HEIGHT} pixelSize={pixelSize} bitmap={(scale) => crewMedalBitmap(metal, scale)} deps={[metal]} />;
}

export function crewTallyLabel(medals: CrewMedals): string {
  return tr("%lld gold, %lld silver, %lld bronze", medals.gold, medals.silver, medals.bronze);
}

/** Gold, silver and bronze with their counts; a zero greys its medal and number, so a crew with one medal reads at a glance. */
export function CrewTally({ medals, large = false }: { medals: CrewMedals; large?: boolean }) {
  const items: [CrewLaurel, number][] = [
    ["gold", medals.gold],
    ["silver", medals.silver],
    ["bronze", medals.bronze],
  ];
  return (
    <Tooltip text={tr("Ranked by golds, then silvers, then bronzes, then whoever reached the tally first.")}>
      <span className="crew-tally" data-large={large || undefined} role="img" aria-label={crewTallyLabel(medals)}>
        {items.map(([metal, count]) => (
          <span key={metal} className="crew-tally-item" data-zero={count === 0 || undefined}>
            <CrewMedalView metal={metal} pixelSize={large ? 1.5 : 1} className="crew-tally-medal" />
            <span className="crew-number">{count.toLocaleString("en-US")}</span>
          </span>
        ))}
      </span>
    </Tooltip>
  );
}

const METALS = ["gold", "silver", "bronze"] as const;

/** The metal of a top 3 place, for its chip and history color. */
export function crewPlaceMetal(place: number): CrewLaurel | undefined {
  return METALS[place - 1];
}

/** The "1st", "2nd", "3rd" chip in the metal's tint. */
export function CrewPlaceChip({ place }: { place: number }) {
  return (
    <span className="crew-place-chip crew-number" data-metal={crewPlaceMetal(place)}>
      {crewOrdinal(place)}
    </span>
  );
}

/** A member's pet, or a quiet paw when they hid it from crew pages. */
export function CrewPetView({ pet, name = "", asleep = false, pixelSize = 1 }: { pet: CrewPet | undefined; name?: string; asleep?: boolean; pixelSize?: number }) {
  if (pet === undefined) {
    return (
      <Tooltip text={tr("%@ keeps their pet private on crew pages.", name)}>
        <span
          className="crew-hidden-pet"
          style={{
            width: 32 * pixelSize,
            height: 32 * pixelSize,
            paddingBottom: 4 * pixelSize,
          }}
        >
          <Icon id="pawprint.fill" size={11 * pixelSize} />
        </span>
      </Tooltip>
    );
  }
  return (
    <Tooltip text={pet.petName}>
      <span className="crew-pet" dir="ltr">
        <PartyPet profile={crewPetProfile(pet, name)} asleep={asleep} pixelSize={pixelSize} />
      </span>
    </Tooltip>
  );
}

/** A little group of pets standing on one baseline; their sprite frames overlap so the pets stand close. */
export function CrewPetGroup({ pets, overlap = 12 }: { pets: readonly CrewPet[]; overlap?: number }) {
  return (
    <span className="crew-pet-group" style={{ "--crew-pet-overlap": `${-overlap}px` } as CSSProperties}>
      {pets.map((pet, index) => (
        <span key={index} className="crew-pet-slot">
          <CrewPetView pet={pet} />
        </span>
      ))}
    </span>
  );
}

/* MARK: Pills and buttons */

/** A Closet-style pill: accent tint when selected, a glyph and an optional title. */
export function CrewPill({
  title,
  symbol,
  showsTitle = true,
  selected = false,
  help,
  dot = false,
  onClick,
}: {
  title: string;
  symbol: string;
  showsTitle?: boolean;
  selected?: boolean;
  help: string;
  dot?: boolean;
  onClick: () => void;
}) {
  return (
    <Tooltip text={showsTitle ? help : `${title}: ${help}`}>
      <button type="button" role="tab" aria-selected={selected} aria-label={title} className="crew-pill kit-caption" data-titled={showsTitle || undefined} onClick={onClick}>
        <Icon id={symbol} size={10} />
        {showsTitle && <span className="crew-pill-title">{title}</span>}
        {dot && <span className="crew-pill-dot" />}
      </button>
    </Tooltip>
  );
}

/**
 * The Party and Crews mode switch in the Party stage's header; `partyTitle`
 * and `crewsTitle` step down the spec's fit ladder, and `otherModeOnly`, its
 * last step, keeps only the pill that switches to the other mode.
 */
export function PartyModeSwitch({
  showsCrews,
  partyTitle = true,
  crewsTitle = true,
  otherModeOnly = false,
  onChange,
}: {
  showsCrews: boolean;
  partyTitle?: boolean;
  crewsTitle?: boolean;
  otherModeOnly?: boolean;
  onChange: (crews: boolean) => void;
}) {
  return (
    <div className="crew-pills" role="tablist">
      {!(otherModeOnly && !showsCrews) && (
        <CrewPill title={tr("Party")} symbol="person.3.fill" showsTitle={partyTitle} selected={!showsCrews} help={tr("Back to your party and friends")} onClick={() => onChange(false)} />
      )}
      {!(otherModeOnly && showsCrews) && (
        <CrewPill title={tr("Crews")} symbol="shield.fill" showsTitle={crewsTitle} selected={showsCrews} help={tr("Study crews: weekly board and Hall of Fame")} onClick={() => onChange(true)} />
      )}
    </div>
  );
}

/** A capsule button: tint, prominent (filled) or quiet, 20 px in rows and headers and 24 px in the friendly states. */
export function CrewButton({
  title,
  symbol,
  titled = true,
  style = "tint",
  height = 20,
  enabled = true,
  busy = false,
  help,
  role,
  checked,
  onClick,
}: {
  title: string;
  symbol?: string;
  /** False shows the glyph alone, with the title in the tooltip and the accessible name. */
  titled?: boolean;
  style?: "tint" | "prominent" | "quiet";
  height?: 20 | 24;
  enabled?: boolean;
  busy?: boolean;
  help: string;
  role?: "switch";
  checked?: boolean;
  onClick: () => void;
}) {
  return (
    <Tooltip text={titled ? help : `${title}: ${help}`}>
      <button type="button" className="crew-button kit-caption" data-style={style} data-height={height} data-glyph={!titled || undefined} role={role} aria-checked={checked} aria-label={titled ? undefined : title} disabled={!enabled || busy} onClick={onClick}>
        {symbol !== undefined && <Icon id={symbol} size={10} />}
        {titled && <span>{title}</span>}
      </button>
    </Tooltip>
  );
}

/** A small round icon button, 20 px. */
export function CrewIconButton({
  symbol,
  help,
  filled = false,
  busy = false,
  expanded,
  onClick,
}: {
  symbol: string;
  help: string;
  filled?: boolean;
  busy?: boolean;
  expanded?: boolean;
  onClick: () => void;
}) {
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className="crew-icon-button"
        data-filled={filled || undefined}
        aria-label={help}
        aria-haspopup={expanded === undefined ? undefined : "menu"}
        aria-expanded={expanded}
        disabled={busy}
        onClick={onClick}
      >
        <Icon id={symbol} size={9} fixedDirection />
      </button>
    </Tooltip>
  );
}

/** A small tag: "Requested", "Your crew", "Private". */
export function CrewTag({ title, symbol, accent = false, help }: { title: string; symbol?: string; accent?: boolean; help?: string }) {
  const tag = (
    <span className="crew-tag kit-caption" data-accent={accent || undefined}>
      {symbol !== undefined && <Icon id={symbol} size={8} fixedDirection />}
      <span>{title}</span>
    </span>
  );
  return help === undefined ? tag : <Tooltip text={help}>{tag}</Tooltip>;
}

/** Copies my crew's invite link and confirms with a check. */
export function CrewInviteButton({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1500);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return (
    <CrewButton
      title={copied ? tr("Copied") : tr("Invite link")}
      symbol={copied ? "checkmark" : "link"}
      help={tr("Copy an invite link. A friend who opens it joins this crew in one click.")}
      onClick={() => void copyText(crewInviteWebURL(code)).then((ok) => setCopied(ok))}
    />
  );
}

/** A one-line text field in the Party code field's shape: Enter submits, Esc clears (or leaves an empty field). */
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
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") {
      event.preventDefault();
      onSubmit?.();
    } else if (event.key === "Escape") {
      event.preventDefault();
      if (value === "") input.current?.blur();
      else onChange("");
    }
  };
  return (
    <Tooltip text={help}>
      <div className="crew-field" onClick={() => input.current?.focus()}>
        {symbol !== undefined && <Icon id={symbol} size={10} className="crew-field-symbol" />}
        <input
          ref={input}
          className="crew-field-input kit-body kit-user-text"
          aria-label={placeholder}
          placeholder={placeholder}
          value={value}
          spellCheck={false}
          autoComplete="off"
          onChange={(event) => onChange([...event.target.value].slice(0, limit).join(""))}
          onKeyDown={onKeyDown}
        />
      </div>
    </Tooltip>
  );
}

/* MARK: Names */

/** Words this long or longer get break points, as on the Mac. */
export const CREW_HYPHENATE_MINIMUM_WORD = 9;
/** The Latin-script languages tried after the app's own when a long word finds no break in it (the Mac asks the word's detected language, then English). */
const HYPHENATION_FALLBACKS = ["de", "en", "fr", "es", "pt"];

/**
 * Hyphenates a crew name the way the Mac does: in the app's language first;
 * when that leaves a long word with no break (an Arabic or Japanese panel, or
 * a German name in an English one), in the first language that breaks it;
 * and only when none does, anywhere in the word. Each try is measured in the
 * layout pass, before paint: a word with no break overflows the box.
 */
export function useCrewNameHyphenation<T extends HTMLElement>(text: string): React.RefObject<T | null> {
  const element = useRef<T>(null);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const fit = () => {
      target.style.overflowWrap = "normal";
      target.removeAttribute("lang");
      const longWord = text.split(/\s+/).some((word) => [...word].length >= CREW_HYPHENATE_MINIMUM_WORD);
      const overflows = () => target.scrollWidth > target.clientWidth + 0.5;
      if (!longWord || !overflows()) return;
      const app = document.documentElement.lang || "en";
      for (const language of HYPHENATION_FALLBACKS.filter((candidate) => candidate !== app.split("-")[0])) {
        target.lang = language;
        if (!overflows()) return;
      }
      target.removeAttribute("lang");
      target.style.overflowWrap = "anywhere";
    };
    fit();
    if (typeof ResizeObserver === "undefined") return;
    let width = target.clientWidth;
    const observer = new ResizeObserver(() => {
      if (Math.abs(target.clientWidth - width) < 0.5) return;
      width = target.clientWidth;
      fit();
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, [text]);
  return element;
}

/** A crew name on up to two lines, hyphenated as `useCrewNameHyphenation` says. */
export function CrewName({ text, className, ...rest }: { text: string; className: string } & Omit<React.HTMLAttributes<HTMLSpanElement>, "children">) {
  const element = useCrewNameHyphenation<HTMLSpanElement>(text);
  return (
    <span ref={element} className={`crew-name ${className}`} {...rest}>
      {text}
    </span>
  );
}

/* MARK: Lists */

/** The height of an element, kept current through a ResizeObserver; 0 until measured. */
function useElementHeight<T extends HTMLElement>(): [React.RefObject<T | null>, number] {
  const element = useRef<T>(null);
  const [height, setHeight] = useState(0);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const measure = () => setHeight((previous) => (Math.abs(previous - target.clientHeight) < 0.5 ? previous : target.clientHeight));
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    return () => observer.disconnect();
  }, []);
  return [element, height];
}

/** How a whole-row list fits `available` px: the rows that show, and whether a "+N more" caption fits under them (else a hairline). */
export function crewRowListFit(available: number, count: number, pinned: boolean): { visible: number; more: "caption" | "line" | undefined } {
  const room = Math.max(0, available - (pinned ? CrewLayout.pinnedHeight : 0));
  const visible = Math.max(1, Math.floor(room / CrewLayout.rowHeight));
  if (count <= visible || pinned) return { visible: Math.min(visible, Math.max(count, 0)), more: undefined };
  return {
    visible,
    more: room - visible * CrewLayout.rowHeight >= CrewLayout.moreHeight ? "caption" : "line",
  };
}

/**
 * A list that shows whole rows only: its viewport is a multiple of the row
 * height, it scrolls by rows, and when rows are left over a "+N more"
 * caption (or a hairline where 14 px will not fit) says the list goes on. A
 * pinned row (my crew) sits under a hairline below it and replaces the
 * caption. `onNearEnd` asks for another page when the last rows show.
 */
export function CrewRowList({ count, row, pinned, onNearEnd, label }: { count: number; row: (index: number) => ReactNode; pinned?: ReactNode; onNearEnd?: () => void; label?: string }) {
  const [box, height] = useElementHeight<HTMLDivElement>();
  const fit = crewRowListFit(height, count, pinned !== undefined);
  const scrolls = height > 0 && count > fit.visible;
  const extra = count - fit.visible;
  return (
    <div ref={box} className="crew-row-list">
      <div
        className="crew-rows"
        role="list"
        aria-label={label}
        data-scrolls={scrolls || undefined}
        style={height > 0 ? { height: Math.min(count, fit.visible) * CrewLayout.rowHeight } : undefined}
        onScroll={(event) => {
          const element = event.currentTarget;
          if (onNearEnd !== undefined && element.scrollTop + element.clientHeight >= element.scrollHeight - CrewLayout.rowHeight) onNearEnd();
        }}
      >
        {Array.from(
          {
            length: height > 0 && !scrolls ? Math.min(count, fit.visible) : count,
          },
          (_, index) => (
            <div key={index} className="crew-rows-item" role="listitem">
              {row(index)}
            </div>
          ),
        )}
      </div>
      {height > 0 && extra > 0 && fit.more === "caption" && <div className="crew-more kit-caption">{tr("%lld more", extra)}</div>}
      {height > 0 && extra > 0 && fit.more === "line" && <div className="crew-more-line" />}
      {pinned !== undefined && (
        <>
          <div className="crew-list-separator" />
          {pinned}
        </>
      )}
    </div>
  );
}

/** A 32 px list row's surface: rounded, with a hover state, and for my crew or me the accent tint with a 2 px leading bar. */
export function CrewRow({
  mine = false,
  help,
  label,
  onClick,
  onContextMenu,
  className,
  children,
}: {
  mine?: boolean;
  help?: string;
  label?: string;
  onClick?: () => void;
  onContextMenu?: (event: React.MouseEvent<HTMLElement>) => void;
  className?: string;
  children: ReactNode;
}) {
  const row = (
    <div
      className={["crew-row", className].filter(Boolean).join(" ")}
      data-mine={mine || undefined}
      data-clickable={onClick !== undefined || undefined}
      role={onClick === undefined ? undefined : "button"}
      tabIndex={onClick === undefined ? undefined : 0}
      aria-label={label}
      onClick={onClick}
      onContextMenu={onContextMenu}
      onKeyDown={(event) => {
        if (onClick !== undefined && (event.key === "Enter" || event.key === " ")) {
          event.preventDefault();
          onClick();
        }
      }}
    >
      {children}
    </div>
  );
  return help === undefined ? row : <Tooltip text={help}>{row}</Tooltip>;
}

/** A name in a row: one line with its caption under it while it fits, else two lines (hyphenated) and no caption, so the name always wins. */
export function CrewRowName({ name, caption, captionAccent = false }: { name: string; caption?: string | undefined; captionAccent?: boolean }) {
  /* Hyphenation runs first (its layout effect is declared first), so the line count is measured on the final breaks. */
  const element = useCrewNameHyphenation<HTMLSpanElement>(name);
  const [twoLines, setTwoLines] = useState(false);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const measure = () => {
      const line = Number.parseFloat(getComputedStyle(target).lineHeight) || 14;
      setTwoLines(target.scrollHeight > line * 1.5);
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    return () => observer.disconnect();
  }, [element, name]);
  return (
    <span className="crew-row-name">
      <span ref={element} className="crew-name crew-row-title kit-body-emphasis kit-user-text">
        {name}
      </span>
      {caption !== undefined && !twoLines && (
        <span className="crew-row-caption kit-caption" data-accent={captionAccent || undefined}>
          {caption}
        </span>
      )}
    </span>
  );
}

/**
 * How many of a column's fallbacks it needs so nothing spills out of it:
 * 0 while everything fits, then one more step for each layout pass in which
 * the element's content is taller than its box, up to `steps`. A resize, or
 * a change in `key`, starts over from 0. The passes run before paint.
 */
export function useFitStep<T extends HTMLElement>(steps: number, key: string): [React.RefObject<T | null>, number] {
  const element = useRef<T>(null);
  const [fit, setFit] = useState({ key, step: 0 });
  const [epoch, setEpoch] = useState(0);
  const [measured, setMeasured] = useState({ key, epoch });
  if (measured.key !== key || measured.epoch !== epoch) {
    setMeasured({ key, epoch });
    setFit({ key, step: 0 });
  }
  useLayoutEffect(() => {
    const target = element.current;
    if (!target || target.clientHeight === 0) return;
    if (target.scrollHeight > target.clientHeight + 0.5 && fit.step < steps) setFit({ key, step: fit.step + 1 });
  }, [fit, steps, key, epoch]);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target || typeof ResizeObserver === "undefined") return;
    let last = target.clientHeight;
    const observer = new ResizeObserver(() => {
      if (Math.abs(target.clientHeight - last) < 0.5) return;
      last = target.clientHeight;
      setEpoch((value) => value + 1);
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, []);
  return [element, fit.step];
}

/* MARK: States */

/** A friendly whole-screen state: a pet (or a glyph in an accent badge), a title, one line and up to two actions. */
export function CrewStatus({ pet, symbol, title, detail, actions }: { pet?: { pet: CrewPet | undefined; asleep: boolean }; symbol?: string; title: string; detail?: string; actions?: ReactNode }) {
  return (
    <div className="crew-status" role="status">
      {pet !== undefined ? (
        <CrewPetView pet={pet.pet} asleep={pet.asleep} pixelSize={1.5} />
      ) : symbol !== undefined ? (
        <span className="crew-status-badge">
          <Icon id={symbol} size={18} />
        </span>
      ) : null}
      <div className="crew-status-words">
        <div className="kit-title">{title}</div>
        {detail !== undefined && <div className="kit-body kit-secondary crew-status-detail">{detail}</div>}
      </div>
      {actions !== undefined && <div className="crew-status-actions">{actions}</div>}
    </div>
  );
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
