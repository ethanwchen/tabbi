/*
 * Port of ClosetPanel: the study pet large and animated on the left, and on
 * the right a chart of the days studied, its wardrobe (wear, take off, or
 * unlock items with study points), its limited edition items, the study
 * streak with its freezes, its look (species, breed, fur color), or its past
 * weekly recaps. Every string is a catalog key the Mac has.
 */

import { useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { PetBond, bondUnlock } from "../../core/pets/petBond";
import { breedDisplayName } from "../../core/pets/petBreed";
import { itemDisplayName } from "../../core/pets/petItem";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { ProgressRing } from "../../ui/kit/Loading";
import { Marquee, MarqueeText } from "../../ui/kit/MarqueeText";
import { PetView } from "../../ui/kit/PetView";
import { Tooltip } from "../../ui/kit/Tooltip";
import { textWidth } from "../../ui/shell/measure";
import { ClosetHeatmapSection } from "./ClosetHeatmap";
import { ClosetLimited } from "./ClosetLimited";
import { ClosetLook } from "./ClosetLook";
import { ClosetStreak } from "./ClosetStreak";
import { ClosetWardrobe } from "./ClosetWardrobe";
import { CLOSET_SECTIONS, type ClosetSection, type ClosetStore } from "./closetStore";
import type { SurpriseGiftKeeper } from "./surpriseGiftKeeper";
import { RecapHistoryList } from "./recap/RecapHistoryList";
import type { RecapStore } from "./recap/recapStore";
import { useElementSize } from "./useElementSize";
import "./closet.css";

export interface ClosetPanelProps {
  readonly store: ClosetStore;
  /** The weekly recaps; their section hides while recaps are off. */
  readonly recaps: RecapStore;
  /** The surprise gifts, whose rare furs the Look section offers. */
  readonly gifts: SurpriseGiftKeeper;
}

export function sectionSymbol(section: ClosetSection): string {
  switch (section) {
    case "activity":
      return "square.grid.3x3.fill";
    case "wardrobe":
      return "tshirt.fill";
    case "limited":
      return "sparkles";
    case "streak":
      return "flame.fill";
    case "look":
      return "paintpalette.fill";
    case "weeks":
      return "calendar";
  }
}

export function sectionTitle(section: ClosetSection): string {
  switch (section) {
    case "activity":
      return tr("Activity");
    case "wardrobe":
      return tr("Wardrobe");
    case "limited":
      return tr("Limited");
    case "streak":
      return tr("Streak");
    case "look":
      return tr("Look");
    case "weeks":
      return tr("Weeks");
  }
}

function sectionHelp(section: ClosetSection): string {
  switch (section) {
    case "activity":
      return tr("Your study day by day, with the time studied on each");
    case "wardrobe":
      return tr("Outfits and accessories to unlock with study points");
    case "limited":
      return tr("Limited edition items, earned by studying, never sold");
    case "streak":
      return tr("Your study streak and the freezes that protect it");
    case "look":
      return tr("Species, breed and fur color");
    case "weeks":
      return tr("Your weekly recaps with your pet");
  }
}

export function ClosetPanel({ store, recaps, gifts }: ClosetPanelProps) {
  const state = useStore(store);
  const recapsEnabled = useStore(recaps, (value) => value.isEnabled);
  const sections = useMemo(() => CLOSET_SECTIONS.filter((section) => section !== "weeks" || recapsEnabled), [recapsEnabled]);
  const shown: ClosetSection = sections.includes(state.section) ? state.section : "activity";
  return (
    <div className="closet-panel">
      <ClosetPetCard store={store} />
      <Card className="closet-card">
        <ClosetHeader sections={sections} shown={shown} balance={state.closet.balance} onSelect={(section) => store.setSection(section)} />
        {shown === "activity" && <ClosetHeatmapSection store={store} />}
        {shown === "wardrobe" && <ClosetWardrobe store={store} />}
        {shown === "limited" && <ClosetLimited store={store} />}
        {shown === "streak" && <ClosetStreak store={store} />}
        {shown === "look" && <ClosetLook store={store} gifts={gifts} />}
        {shown === "weeks" && <RecapHistoryList store={recaps} />}
      </Card>
    </div>
  );
}

/* Header */

interface HeaderVariant {
  readonly showsUnit: boolean;
  readonly titlesAll: boolean;
  readonly isTight: boolean;
  readonly titlesOpen: boolean;
}

/* The Compact panel has no room for "pts" beside the pills, nor for the titles of the sections not open; a four-digit balance drops the open title too. */
const HEADER_VARIANTS: readonly HeaderVariant[] = [
  { showsUnit: true, titlesAll: true, isTight: false, titlesOpen: true },
  { showsUnit: false, titlesAll: true, isTight: false, titlesOpen: true },
  { showsUnit: false, titlesAll: false, isTight: false, titlesOpen: true },
  { showsUnit: false, titlesAll: false, isTight: true, titlesOpen: true },
  { showsUnit: false, titlesAll: false, isTight: true, titlesOpen: false },
];

const CAPTION = { size: 10.5, weight: 500 } as const;
const PILL_ICON = 10;

function pillPadding(showsTitle: boolean, isTight: boolean): number {
  if (showsTitle && !isTight) return 10;
  if (showsTitle || !isTight) return 8;
  return 6;
}

/** Whether the header variant fits `width`, measured in the caption type as the pills draw it. */
export function headerVariantWidth(variant: HeaderVariant, sections: readonly ClosetSection[], shown: ClosetSection, balance: number): number {
  const pills = sections.reduce((sum, section) => {
    const showsTitle = variant.titlesAll || (variant.titlesOpen && section === shown);
    const text = showsTitle ? 4 + Math.ceil(textWidth(sectionTitle(section), CAPTION.size, CAPTION.weight)) : 0;
    return sum + 2 * pillPadding(showsTitle, variant.isTight) + PILL_ICON + text;
  }, 0);
  const chip = 16 + 9 + 4 + Math.ceil(textWidth(String(balance), CAPTION.size, CAPTION.weight)) + (variant.showsUnit ? 4 + Math.ceil(textWidth(tr("pts"), CAPTION.size, CAPTION.weight)) : 0);
  return pills + 2 * (sections.length - 1) + (variant.isTight ? 4 : 8) + chip;
}

function ClosetHeader({ sections, shown, balance, onSelect }: { sections: readonly ClosetSection[]; shown: ClosetSection; balance: number; onSelect: (section: ClosetSection) => void }) {
  const row = useRef<HTMLDivElement>(null);
  const { width } = useElementSize(row);
  const variant = useMemo(() => {
    if (width === 0) return HEADER_VARIANTS[0] as HeaderVariant;
    return HEADER_VARIANTS.find((candidate) => headerVariantWidth(candidate, sections, shown, balance) <= width) ?? (HEADER_VARIANTS[HEADER_VARIANTS.length - 1] as HeaderVariant);
  }, [width, sections, shown, balance]);
  return (
    <div ref={row} className="closet-header" data-tight={variant.isTight || undefined}>
      <div className="closet-pills" role="tablist" aria-label={tr("Closet")}>
        {sections.map((section) => (
          <ClosetPill
            key={section}
            title={sectionTitle(section)}
            symbol={sectionSymbol(section)}
            showsTitle={variant.titlesAll || (variant.titlesOpen && section === shown)}
            isSelected={section === shown}
            isTight={variant.isTight}
            help={sectionHelp(section)}
            onClick={() => onSelect(section)}
          />
        ))}
      </div>
      <ClosetPointsChip balance={balance} showsUnit={variant.showsUnit} />
    </div>
  );
}

export interface ClosetPillProps {
  readonly title: string;
  readonly symbol: string;
  readonly showsTitle?: boolean;
  readonly isSelected: boolean;
  readonly isTight?: boolean;
  readonly help: string;
  readonly onClick: () => void;
}

/** A capsule toggle: accent-tinted when selected, with a hover state. Port of ClosetPill. */
export function ClosetPill({ title, symbol, showsTitle = true, isSelected, isTight = false, help, onClick }: ClosetPillProps) {
  return (
    <Tooltip text={showsTitle ? help : `${title}: ${help}`}>
      <button
        type="button"
        role="tab"
        aria-selected={isSelected}
        aria-label={title}
        className="closet-pill"
        data-selected={isSelected}
        style={{ paddingInline: pillPadding(showsTitle, isTight) }}
        onClick={onClick}
      >
        <Icon id={symbol} size={PILL_ICON} />
        {showsTitle && <span>{title}</span>}
      </button>
    </Tooltip>
  );
}

/** The study-points balance. Port of ClosetPointsChip. */
function ClosetPointsChip({ balance, showsUnit }: { balance: number; showsUnit: boolean }) {
  return (
    <Tooltip text={tr("Points: 1 for every focused minute, plus a bonus for finishing a session")}>
      <div className="closet-points" role="status">
        <Icon id="star.fill" size={9} className="closet-points-star" />
        <span className="closet-points-value">{balance}</span>
        {showsUnit && <span className="closet-points-unit">{tr("pts")}</span>}
      </div>
    </Tooltip>
  );
}

/* Pet */

/** The pet large and animated, its name (click to rename), and its breed or the item being tried on. Port of ClosetPetCard. */
function ClosetPetCard({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState("");
  const body = useRef<HTMLDivElement>(null);
  const profile = state.profile;
  const isUnnamed = profile.name === breedDisplayName(profile.breed);
  const latestAdventure = store.latestAdventure;
  const latestDetail = store.latestAdventureDetail;

  /*
   * Where there is room (Large), the pet's latest adventure (or its breed
   * before the first) and the bond both show; otherwise one line. The fuller
   * layout is tried first whenever its inputs change, and dropped once it
   * measures taller than the card.
   */
  const fit = `${latestAdventure ?? ""}|${state.tryingOn ?? ""}|${profile.name}`;
  const [fitted, setFitted] = useState({ key: fit, showsBreed: true });
  if (fitted.key !== fit) setFitted({ key: fit, showsBreed: true });
  const showsBreed = fitted.showsBreed;
  useLayoutEffect(() => {
    const element = body.current;
    if (!element || !showsBreed) return;
    if (element.scrollHeight > element.clientHeight + 1) setFitted({ key: fit, showsBreed: false });
  }, [fit, showsBreed]);

  const subtitle = (() => {
    if (state.tryingOn !== undefined) return tr("Trying on %@", itemDisplayName(state.tryingOn));
    /* A pet still called by its breed would show the breed twice. */
    if (isUnnamed) return profile.species === "cat" ? tr("Give your cat a name") : tr("Give your dog a name");
    return showsBreed ? (latestAdventure ?? breedDisplayName(profile.breed)) : undefined;
  })();
  const subtitleIsAdventure = subtitle !== undefined && subtitle === latestAdventure && state.tryingOn === undefined;

  const commit = () => {
    if (!renaming) return;
    store.rename(draft);
    setRenaming(false);
  };
  const onKey = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") commit();
    if (event.key === "Escape") setRenaming(false);
  };

  return (
    <Card padding={8} className="closet-pet-card">
      <div ref={body} className="closet-pet-body">
        <Tooltip text={latestDetail === undefined ? "" : tr("Latest adventure: %@", latestDetail)}>
          <div className="closet-pet-view">
            <PetView player={store.preview} pixelSize={3} />
          </div>
        </Tooltip>
        {renaming ? (
          <input
            className="closet-name-field kit-title kit-user-text"
            aria-label={tr("Name")}
            autoFocus
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={onKey}
            onBlur={commit}
          />
        ) : (
          <ClosetNameButton
            name={profile.name}
            onClick={() => {
              setDraft(profile.name);
              setRenaming(true);
            }}
          />
        )}
        {subtitle !== undefined && (
          <div className="closet-subtitle kit-caption" data-accent={state.tryingOn !== undefined || undefined}>
            {subtitleIsAdventure ? (
              <ClosetAdventureLine text={subtitle} help={tr("Latest adventure: %@", latestDetail ?? subtitle)} />
            ) : (
              <MarqueeText text={subtitle} />
            )}
          </div>
        )}
        {state.tryingOn === undefined && (showsBreed || !isUnnamed) && <ClosetBondRow bond={state.bond} />}
      </div>
    </Card>
  );
}

/** The pet's latest adventure: a sentence on up to two centered lines, or one line that scrolls when even two can't hold it. */
function ClosetAdventureLine({ text, help }: { text: string; help: string }) {
  const probe = useRef<HTMLSpanElement>(null);
  const [fits, setFits] = useState(true);
  useLayoutEffect(() => {
    const element = probe.current;
    if (!element) return;
    setFits(element.scrollHeight <= element.clientHeight + 1);
  }, [text]);
  return fits ? (
    <Tooltip text={help}>
      <span ref={probe} className="closet-adventure">
        {text}
      </span>
    </Tooltip>
  ) : (
    <MarqueeText text={text} help={help} />
  );
}

/** The pet's name with a pencil that appears on hover; click to rename. Port of ClosetNameButton. */
function ClosetNameButton({ name, onClick }: { name: string; onClick: () => void }) {
  return (
    <Tooltip text={tr("Rename your pet")}>
      <button type="button" className="closet-name" onClick={onClick}>
        <MarqueeText text={name} help={tr("Rename your pet")} className="closet-name-text kit-title" userText />
        <Icon id="pencil" size={9.5} className="closet-name-pencil" />
      </button>
    </Tooltip>
  );
}

/**
 * The bond level and its tier name beside a small ring that fills toward
 * the next level ("Bond 4 · Best friends"). The tooltip says what the next
 * level unlocks. Port of ClosetBondRow.
 */
function ClosetBondRow({ bond }: { bond: PetBond }) {
  const help = bondHelp(bond);
  const label = `${tr("Bond %lld", bond.level)} · ${bond.tierName}`;
  return (
    <Tooltip text={help}>
      <div className="closet-bond kit-caption">
        <ProgressRing progress={bond.progressInLevel} tint="var(--accent)" lineWidth={2} size={10} />
        <Marquee text={label} help={help}>
          <span className="kit-secondary">{tr("Bond %lld", bond.level)}</span>
          <span className="kit-tertiary">{` · ${bond.tierName}`}</span>
        </Marquee>
      </div>
    </Tooltip>
  );
}

function bondHelp(bond: PetBond): string {
  const level = bond.level;
  const top = PetBond.maxLevel;
  const missing = bond.pointsToNextLevel;
  if (missing === undefined) return tr("Bond %lld of %lld, as close as it gets. Every focused minute still counts.", level, top);
  const next = level + 1;
  const points = tr("%lld points", missing);
  const unlock = bondUnlock(next);
  if (unlock === undefined) {
    return tr("Bond %lld of %lld: %@ to Bond %lld. Every focused minute and every study day bring you closer.", level, top, points, next);
  }
  return tr("Bond %lld of %lld: %@ to Bond %lld, which brings the %@. Every focused minute and every study day bring you closer.", level, top, points, next, unlock);
}

/** A footer line that acts as a quiet link: it brightens on hover. Port of ClosetFooterLink. */
export function ClosetFooterLink({ help, onClick, children }: { help: string; onClick: () => void; children: ReactNode }) {
  return (
    <Tooltip text={help}>
      <button type="button" className="closet-footer-link" onClick={onClick}>
        {children}
      </button>
    </Tooltip>
  );
}

/** The footer line for the item on the pet: its name, then what clicking does or how to earn it; it scrolls to show the rest. Port of ClosetFooterDetail. */
export function ClosetFooterDetail({ name, detail }: { name: string; detail: string }) {
  return (
    <Marquee text={`${name} ${detail}`} className="closet-footer-detail">
      <span className="kit-secondary">{name}</span>
      <span className="kit-tertiary">{detail}</span>
    </Marquee>
  );
}
