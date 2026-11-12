/*
 * Port of ClosetWardrobe and ClosetItemTile: one shelf per theme, each a
 * grid of five tiles (the item alone on the pet, with its price, lock, or
 * On), scrolling with a fade at the bottom edge, and a footer that names
 * the hovered item or points to the next unlock. Hovering a tile tries the
 * item on the big pet. A snapshot run cannot scroll, so the grid is clipped
 * at the top rows (scrolled by a fraction for the scrolling shots).
 */

import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { PetCloset, type PetClosetItemState, type PetRadiantState, stateIsOwned } from "../../core/closet/petCloset";
import { PetEconomy } from "../../core/closet/petEconomy";
import { howToEarn, limitedEditionOf } from "../../core/closet/petLimited";
import { tr } from "../../core/localization/tr";
import { itemDisplayName, type PetItem } from "../../core/pets/petItem";
import { themeDisplayName, type PetItemTheme } from "../../core/pets/petItemTheme";
import { itemCost } from "../../core/pets/petUnlocks";
import { PetProfile } from "../../core/pets/petProfile";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { PetSprite } from "../../ui/kit/PetView";
import { Tooltip } from "../../ui/kit/Tooltip";
import { textWidth } from "../../ui/shell/measure";
import { ClosetFooterDetail, ClosetFooterLink } from "./ClosetPanel";
import type { ClosetStore } from "./closetStore";
import { useElementSize } from "./useElementSize";
import { ClosetRadiantGoalLine, ClosetRadiantSheet, ClosetRadiantTileButton } from "./ClosetRadiant";
import { useContextMenu } from "../../ui/kit/ContextMenu";

/** Thumbnails show each item alone on the pet, so the item reads clearly. */
export function thumbnailModel(profile: PetProfile): PetProfile {
  return new PetProfile(profile.name, profile.breed, { paletteOverrides: profile.paletteOverrides, ...(profile.furTint ? { furTint: profile.furTint } : {}) });
}

/** A tile's picture: the item alone on the pet, a Radiant one with the still of its effect, as set. */
function tileProfile(item: PetItem, model: PetProfile, radiant: PetRadiantState | undefined): PetProfile {
  if (radiant?.kind === "radiant" && radiant.intensity !== "off") return PetCloset.radiantPreview(item, radiant.intensity, model);
  return PetCloset.wearing(item, model);
}

export interface ScrollingGridProps {
  readonly store: ClosetStore;
  /** The tile to scroll into view and keep in the middle, then forget. */
  readonly scrollTo?: PetItem | undefined;
  readonly onScrolled?: () => void;
  readonly children: ReactNode;
}

/**
 * The wardrobe grows with every new item, so it scrolls, and the rows fade
 * out at the bottom edge to say so. A snapshot run draws it clipped at the
 * top rows, or scrolled by its fraction.
 */
export function ScrollingGrid({ store, scrollTo, onScrolled, children }: ScrollingGridProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const scrolled = useStore(store, (state) => state.snapshotScrolled);
  useLayoutEffect(() => {
    const element = scroller.current;
    if (!element || !store.isSnapshot) return;
    element.scrollTop = Math.round((element.scrollHeight - element.clientHeight) * (scrolled ?? 0));
  }, [store, scrolled, children]);
  useEffect(() => {
    const element = scroller.current;
    if (!element || scrollTo === undefined) return;
    const tile = element.querySelector<HTMLElement>(`[data-item="${scrollTo}"]`);
    tile?.scrollIntoView({ block: "center", behavior: store.isSnapshot ? "instant" : "smooth" });
    onScrolled?.();
  }, [scrollTo, onScrolled, store]);
  return (
    <EdgeFade edge="bottom" className="closet-grid-fade">
      <div ref={scroller} className="closet-grid-scroll" data-still={store.isSnapshot || undefined}>
        {children}
      </div>
    </EdgeFade>
  );
}

/** A shelf's theme name. Port of ClosetShelfTitle. */
export function ClosetShelfTitle({ theme }: { theme: PetItemTheme }) {
  return <div className="closet-shelf-title">{themeDisplayName(theme)}</div>;
}

export interface ClosetItemTileProps {
  readonly item: PetItem;
  readonly state: PetClosetItemState;
  /** Fresh in the catalog and not unlocked yet. */
  readonly isNew: boolean;
  readonly model: PetProfile;
  /** Where the item stands for a Radiant upgrade: the tile's pip. The limited shelves leave it out. */
  readonly radiant?: PetRadiantState;
  readonly onClick: () => void;
  readonly onHover: (inside: boolean) => void;
  /** Opens the item's Radiant sheet. */
  readonly onRadiant?: () => void;
}

/** Icon and title close together, for tiny tile labels. Port of ClosetTightLabelStyle. */
export function TightLabel({ symbol, children, className }: { symbol?: string; children: ReactNode; className?: string }) {
  return (
    <span className={["closet-tight-label", className].filter(Boolean).join(" ")}>
      {symbol !== undefined && <Icon id={symbol} size={8} />}
      <span>{children}</span>
    </span>
  );
}

function tileLabel(item: PetItem, state: PetClosetItemState): ReactNode {
  switch (state.kind) {
    case "wearing":
      return (
        <TightLabel symbol="checkmark" className="closet-tile-on">
          {tr("On")}
        </TightLabel>
      );
    case "owned":
      return <span className="kit-tertiary">{tr("Owned")}</span>;
    case "affordable":
      return (
        <TightLabel symbol="star.fill" className="closet-tile-affordable">
          {tr("%lld", itemCost(item))}
        </TightLabel>
      );
    case "locked":
      return (
        <TightLabel symbol="lock.fill" className="kit-tertiary">
          {tr("%lld", itemCost(item))}
        </TightLabel>
      );
    case "unearned":
      return (
        <TightLabel symbol="lock.fill" className="kit-tertiary">
          {tr("Limited")}
        </TightLabel>
      );
  }
}

/** What a click does on an owned tile that has a Radiant upgrade, or undefined for the plain wording. */
function radiantDetail(state: PetClosetItemState, radiant: PetRadiantState | undefined): string | undefined {
  if (radiant === undefined || (state.kind !== "wearing" && state.kind !== "owned")) return undefined;
  const wearing = state.kind === "wearing";
  switch (radiant.kind) {
    case "radiant":
      return wearing ? tr("Radiant. Click to take off, or the star to set its effect") : tr("Radiant. Click to wear, or the star to set its effect");
    case "affordable":
    case "locked":
      return wearing ? tr("Click to take off, or the star to make it Radiant") : tr("Click to wear, or the star to make it Radiant");
    default:
      return undefined;
  }
}

function tileHelp(item: PetItem, state: PetClosetItemState, isNew: boolean, radiant?: PetRadiantState): string {
  const name = itemDisplayName(item);
  const fresh = isNew ? `${tr("New")}: ` : "";
  const upgrade = radiantDetail(state, radiant);
  if (upgrade !== undefined) return `${name}: ${upgrade}`;
  switch (state.kind) {
    case "wearing":
      return `${name}: ${tr("Click to take off")}`;
    case "owned":
      return `${name}: ${tr("Click to wear")}`;
    case "affordable":
      return `${fresh}${name}: ${tr("Unlock for %lld pts", itemCost(item))}`;
    case "locked":
      return `${fresh}${name}: ${tr("%lld pts, %@ to go", itemCost(item), PetEconomy.studyToEarn(state.missing))}`;
    case "unearned": {
      const edition = limitedEditionOf(item);
      return tr("%@, limited edition: %@", name, edition === undefined ? tr("Limited edition") : howToEarn(edition));
    }
  }
}

export function ClosetItemTile({ item, state, isNew, model, radiant, onClick, onHover, onRadiant }: ClosetItemTileProps) {
  const isLocked = state.kind === "locked";
  const owned = stateIsOwned(state);
  const [hovering, setHovering] = useState(false);
  const menu = useContextMenu(() => {
    if (radiant === undefined || onRadiant === undefined) return [];
    switch (radiant.kind) {
      case "radiant":
        return [{ title: tr("Radiant Effect"), symbol: "sparkles", onSelect: onRadiant }];
      case "affordable":
      case "locked":
        return [{ title: tr("Make Radiant"), symbol: "sparkles", onSelect: onRadiant }];
      default:
        return [];
    }
  });
  const hover = (inside: boolean) => {
    setHovering(inside);
    onHover(inside);
  };
  const tile = (
    <Tooltip text={tileHelp(item, state, isNew, radiant)}>
      <button
        type="button"
        className="closet-tile"
        data-item={item}
        data-wearing={state.kind === "wearing" || undefined}
        aria-label={itemDisplayName(item)}
        onClick={onClick}
        onContextMenu={menu.open}
        onPointerEnter={() => hover(true)}
        onPointerLeave={() => hover(false)}
      >
        <span className="closet-tile-sprite" style={{ opacity: owned ? 1 : isLocked ? 0.35 : 0.6, filter: isLocked ? "saturate(0.2)" : undefined }}>
          <PetSprite profile={tileProfile(item, model, radiant)} pixelSize={1} />
        </span>
        <span className="closet-tile-label">{tileLabel(item, state)}</span>
        {isNew && <span className="closet-tile-new" aria-hidden="true" />}
      </button>
    </Tooltip>
  );
  if (radiant === undefined || onRadiant === undefined) return tile;
  /* The pip sits over the tile's button, so it takes its own clicks. */
  return (
    <div className="closet-tile-holder" onPointerEnter={() => setHovering(true)} onPointerLeave={() => setHovering(false)}>
      {tile}
      <ClosetRadiantTileButton item={item} state={radiant} tileHovered={hovering} onClick={onRadiant} />
      {menu.element}
    </div>
  );
}

const SHELVES = PetCloset.shelves;

export function ClosetWardrobe({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const [hovered, setHovered] = useState<PetItem | undefined>(undefined);
  const [shown, setShown] = useState<PetItem | undefined>(undefined);
  const model = thumbnailModel(state.profile);
  const closet = state.closet;

  const hover = (item: PetItem, inside: boolean) => {
    const next = inside ? item : hovered === item ? undefined : hovered;
    setHovered(next);
    store.tryOn(next);
  };
  const leave = () => {
    if (hovered === undefined) return;
    setHovered(undefined);
    store.tryOn(undefined);
  };
  const show = (item: PetItem) => {
    setHovered(item);
    store.tryOn(item);
    setShown(item);
  };

  const openRadiant = (item: PetItem) => {
    setHovered(undefined);
    store.tryOn(undefined);
    store.showRadiant(item);
  };

  if (state.radiantSheet !== undefined) {
    return (
      <div className="closet-section closet-wardrobe">
        <ClosetRadiantSheet store={store} item={state.radiantSheet} />
      </div>
    );
  }

  return (
    <div className="closet-section closet-wardrobe" onPointerLeave={leave}>
      <ScrollingGrid store={store} scrollTo={shown} onScrolled={() => setShown(undefined)}>
        <div className="closet-shelves">
          {SHELVES.map((shelf) => (
            <div key={shelf.theme} className="closet-shelf">
              <ClosetShelfTitle theme={shelf.theme} />
              <div className="closet-grid">
                {shelf.items.map((item) => (
                  <ClosetItemTile
                    key={item}
                    item={item}
                    state={closet.state(item)}
                    isNew={closet.isNew(item)}
                    model={model}
                    radiant={closet.radiantState(item)}
                    onClick={() => store.tap(item)}
                    onHover={(inside) => hover(item, inside)}
                    onRadiant={() => openRadiant(item)}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      </ScrollingGrid>
      <WardrobeFooter store={store} tryingOn={state.tryingOn} onShow={show} />
    </div>
  );
}

function detail(store: ClosetStore, item: PetItem): string {
  const state = store.closet.state(item);
  const upgrade = radiantDetail(state, store.closet.radiantState(item));
  if (upgrade !== undefined) return upgrade;
  switch (state.kind) {
    case "wearing":
      return tr("Click to take off");
    case "owned":
      return tr("Click to wear");
    case "affordable":
      return tr("Unlock for %lld pts", itemCost(item));
    case "locked":
      return tr("%lld pts, %@ to go", itemCost(item), PetEconomy.studyToEarn(state.missing));
    case "unearned": {
      const edition = limitedEditionOf(item);
      return edition === undefined ? tr("Limited edition") : howToEarn(edition);
    }
  }
}

/** Names the hovered item, or points to the next unlock. */
function WardrobeFooter({ store, tryingOn, onShow }: { store: ClosetStore; tryingOn: PetItem | undefined; onShow: (item: PetItem) => void }) {
  const row = useRef<HTMLDivElement>(null);
  const { width } = useElementSize(row);
  const closet = store.closet;
  const next = closet.nextUnlock;
  let content: ReactNode;
  const goal = closet.radiantGoalProgress;
  if (tryingOn !== undefined) {
    content = <ClosetFooterDetail name={itemDisplayName(tryingOn)} detail={detail(store, tryingOn)} />;
  } else if (goal !== undefined) {
    /* A pinned Radiant goal takes the next unlock's place. */
    content = <ClosetRadiantGoalLine goal={goal} onClick={() => store.showRadiant(goal.item)} />;
  } else if (next !== undefined && closet.save.ledger.earned === 0) {
    /* A brand-new pet: explain where points come from. */
    const name = itemDisplayName(next.item);
    const long = tr("%@ unlocks after %@", name, PetEconomy.studyToEarn(itemCost(next.item)));
    const shortText = tr("%@ unlocks at %lld", name, itemCost(next.item));
    const lead = tr("Focus to earn points");
    const fitsLong = width === 0 || textWidth(lead, 10.5, 500) + 4 + textWidth(long, 10.5, 500) <= width;
    content = (
      <>
        <span className="kit-secondary">{lead}</span>
        <ClosetFooterLink help={tr("Show %@ and try it on", name)} onClick={() => onShow(next.item)}>
          <span className="kit-tertiary">{fitsLong ? long : shortText}</span>
        </ClosetFooterLink>
      </>
    );
  } else if (next !== undefined) {
    content = (
      <ClosetFooterLink help={tr("Show %@ and try it on", itemDisplayName(next.item))} onClick={() => onShow(next.item)}>
        <NextUnlock item={next.item} missing={next.missing} width={width} />
      </ClosetFooterLink>
    );
  } else {
    content = <MarqueeText text={tr("Everything unlocked. Dress up as you like.")} className="kit-tertiary" />;
  }
  return (
    <div ref={row} className="closet-footer kit-caption">
      {content}
    </div>
  );
}

/** Says what the next item asks of you: the points still missing and, when there is room, the study that earns them at a typical pace. */
function NextUnlock({ item, missing, width }: { item: PetItem; missing: number; width: number }) {
  const name = itemDisplayName(item);
  const label = tr("Next unlock");
  const study = PetEconomy.studyToEarn(missing);
  const status = missing === 0 ? tr("ready to unlock") : tr("%lld pts, %@ to go", missing, study);
  const shortStatus = missing === 0 ? status : tr("%lld pts to go", missing);
  const measure = (parts: string[]) => parts.reduce((sum, part) => sum + textWidth(part, 10.5, 500), 0) + 4 * (parts.length - 1);
  const variant = width === 0 || measure([label, name, status]) <= width ? { labeled: true, text: status } : measure([name, status]) <= width ? { labeled: false, text: status } : { labeled: false, text: shortStatus };
  const help = missing === 0 ? tr("%@ is ready to unlock", name) : tr("%lld more points: %@ at a typical study pace", missing, study);
  return (
    <Tooltip text={help}>
      <span className="closet-next-unlock">
        {variant.labeled && <span className="kit-tertiary">{label}</span>}
        <span className="kit-secondary">{name}</span>
        <span style={{ color: missing === 0 ? "var(--accent)" : "var(--tertiary-text)" } as CSSProperties}>{variant.text}</span>
      </span>
    </Tooltip>
  );
}
