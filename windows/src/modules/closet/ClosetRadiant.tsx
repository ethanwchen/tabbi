/*
 * Port of ClosetRadiant: the Closet's Radiant upgrades. An owned showpiece
 * bought a second time, for 5x its price, keeps its look and gains an
 * animated effect. The wardrobe tile wears a star pip once an item is
 * Radiant; the pip (shown faded on hover for an item that can be upgraded)
 * opens the Radiant sheet in place of the grid, where the upgrade is
 * bought, pinned as a goal, or its effect set to Bold, Subtle or Off. A
 * pinned goal shows its progress in the wardrobe's footer. Every string is
 * a catalog key the Mac has.
 */

import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { useStore } from "../../app/useStore";
import { PetEconomy } from "../../core/closet/petEconomy";
import { radiantGoalFraction, radiantGoalIsReady, type PetRadiantGoal, type PetRadiantState } from "../../core/closet/petCloset";
import { currentLanguage, numberLocale, tr } from "../../core/localization/tr";
import { itemDisplayName, type PetItem } from "../../core/pets/petItem";
import type { PetRadiantIntensity } from "../../core/pets/radiant/radiantArt";
import { radiantMarkerBitmap, radiantMarkerSize } from "../../core/pets/radiant/radiantMarkerArt";
import { radiantEffectName, radiantPrice } from "../../core/pets/radiant/radiantResolver";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { TextThatFits } from "../../ui/kit/TextThatFits";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { ClosetStore } from "./closetStore";

/** A whole number in the user's language ("9,750"), as Swift's `formatted()` writes it. */
export function formattedCount(value: number): string {
  return new Intl.NumberFormat(numberLocale(currentLanguage())).format(value);
}

/** The effect's name in the user's language; the names stay English in `radiant.json` and are catalog keys. */
export function localizedEffectName(item: PetItem, intensity: PetRadiantIntensity): string {
  const name = radiantEffectName(item, intensity);
  return name === undefined ? "" : tr(name);
}

/**
 * The step down a container takes, like the Mac's `ViewThatFits`: 0 shows
 * the fullest variant, and while the content overflows the container (on
 * `axis`) the next shorter one, up to `last`. A new size starts over.
 */
function useFitLevel(ref: RefObject<HTMLElement | null>, last: number, axis: "x" | "y", key: string): number {
  const [fit, setFit] = useState({ key, size: "", level: 0 });
  const level = fit.key === key ? fit.level : 0;
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const size = () => `${element.clientWidth}x${element.clientHeight}`;
    const measure = () => {
      const now = size();
      setFit((current) => {
        /* A new size or new words start over from the fullest variant. */
        const base = current.key === key && current.size === now ? current.level : 0;
        const over = axis === "x" ? element.scrollWidth > element.clientWidth + 0.5 : element.scrollHeight > element.clientHeight + 0.5;
        const next = over && base === level ? Math.min(last, base + 1) : base;
        return current.key === key && current.size === now && current.level === next ? current : { key, size: now, level: next };
      });
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(() => {
      if (size() !== fit.size) measure();
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref, last, axis, key, level, fit.size]);
  return level;
}

/**
 * The Radiant marker, a 9 by 9 pixel star drawn like the Goals badges (1.5
 * CSS px per pixel by default) at a whole number of device pixels per
 * sprite pixel, never smoothed. Port of ClosetRadiantPip.
 */
export function ClosetRadiantPip({ pixelSize = 1.5 }: { pixelSize?: number }) {
  const element = useRef<HTMLCanvasElement>(null);
  const [ratio, setRatio] = useState(() => (typeof window === "undefined" ? 1 : window.devicePixelRatio || 1));
  useLayoutEffect(() => {
    if (typeof window === "undefined") return;
    const query = window.matchMedia(`(resolution: ${ratio}dppx)`);
    const update = () => setRatio(window.devicePixelRatio || 1);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, [ratio]);
  useLayoutEffect(() => {
    const canvas = element.current;
    if (!canvas) return;
    /* The large panel scales its content as a whole (--panel-scale); divide it out so the pip lands on whole device pixels. */
    const panelScale = Number.parseFloat(getComputedStyle(canvas).getPropertyValue("--panel-scale")) || 1;
    /* The nearest whole number of device pixels per sprite pixel to what the panel shows. */
    const scale = Math.max(1, Math.round(pixelSize * panelScale * ratio));
    const side = radiantMarkerSize();
    const css = (side * scale) / ratio / panelScale;
    canvas.width = side * scale;
    canvas.height = side * scale;
    canvas.style.width = `${css}px`;
    canvas.style.height = `${css}px`;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.imageSmoothingEnabled = false;
    const bitmap = radiantMarkerBitmap(scale);
    const image = context.createImageData(bitmap.width, bitmap.height);
    image.data.set(bitmap.data);
    context.putImageData(image, 0, 0);
  }, [pixelSize, ratio]);
  /* The canvas, sized in a layout effect before the first paint, sizes the pip. */
  return (
    <span className="closet-radiant-pip" aria-hidden="true">
      <canvas ref={element} />
    </span>
  );
}

/** Whether a tile shows its pip: always on a Radiant item, on hover for an owned item that can be upgraded. */
export function tileShowsPip(state: PetRadiantState, tileHovered: boolean): boolean {
  switch (state.kind) {
    case "radiant":
      return true;
    case "affordable":
    case "locked":
      return tileHovered;
    case "notEligible":
    case "needsItem":
      return false;
  }
}

export function radiantTileHelp(item: PetItem, state: PetRadiantState): string {
  return state.kind === "radiant" ? tr("Radiant %@: set its effect", itemDisplayName(item)) : tr("Make %@ Radiant", itemDisplayName(item));
}

/** The pip on a wardrobe tile; it opens the Radiant sheet. Port of ClosetRadiantTileButton. */
export function ClosetRadiantTileButton({ item, state, tileHovered, onClick }: { item: PetItem; state: PetRadiantState; tileHovered: boolean; onClick: () => void }) {
  if (!tileShowsPip(state, tileHovered)) return null;
  const help = radiantTileHelp(item, state);
  return (
    <Tooltip text={help}>
      <button type="button" className="closet-radiant-tile-pip" data-radiant={state.kind === "radiant" || undefined} aria-label={help} onClick={onClick}>
        <ClosetRadiantPip />
      </button>
    </Tooltip>
  );
}

export function intensityTitle(intensity: PetRadiantIntensity): string {
  switch (intensity) {
    case "bold":
      return tr("Bold");
    case "subtle":
      return tr("Subtle");
    case "off":
      return tr("Off");
  }
}

function intensityHelp(intensity: PetRadiantIntensity, isRadiant: boolean): string {
  if (intensity === "off") return tr("Keep the upgrade but show the item as before");
  if (isRadiant) return intensity === "bold" ? tr("Show the full effect") : tr("Show a quieter effect");
  return intensity === "bold" ? tr("Preview the Bold effect") : tr("Preview the Subtle effect");
}

/** A capsule choice in the Radiant sheet, accent-tinted when selected. Port of ClosetRadiantChoice. */
function RadiantChoice({ title, isSelected, help, onClick }: { title: string; isSelected: boolean; help: string; onClick: () => void }) {
  return (
    <Tooltip text={help}>
      <button type="button" className="closet-radiant-choice" data-selected={isSelected} aria-pressed={isSelected} onClick={onClick}>
        {title}
      </button>
    </Tooltip>
  );
}

/** A capsule button in the Radiant sheet's footer. Port of ClosetRadiantButton. */
function RadiantButton({ title, isPrimary, disabled = false, help, onClick }: { title: string; isPrimary: boolean; disabled?: boolean; help: string; onClick?: () => void }) {
  return (
    <Tooltip text={help}>
      <button type="button" className="closet-radiant-button" data-primary={isPrimary || undefined} disabled={disabled} aria-disabled={disabled} onClick={onClick}>
        {title}
      </button>
    </Tooltip>
  );
}

/**
 * The Radiant sheet, in the wardrobe's place: the effect, previewed on the
 * big pet, and either the upgrade (with its price and a pin as goal) or,
 * once upgraded, how strongly it shows. A short panel keeps the effect's
 * name, or only the choices, rather than clip. Port of ClosetRadiantSheet.
 */
export function ClosetRadiantSheet({ store, item }: { store: ClosetStore; item: PetItem }) {
  const state = useStore(store);
  const closet = state.closet;
  const radiant = closet.radiantState(item);
  const isRadiant = radiant.kind === "radiant";
  const sheet = useRef<HTMLDivElement>(null);
  const effect = localizedEffectName(item, state.radiantPreview === "subtle" ? "subtle" : "bold");
  const description = isRadiant
    ? tr("%@. Pick how strongly it shows; Reduce Motion keeps it still.", effect)
    : tr("%@. Keeps its look and adds a loop of light.", effect);
  const detail = useFitLevel(sheet, 2, "y", `${item}|${radiant.kind}|${effect}|${currentLanguage()}`);
  const options: PetRadiantIntensity[] = isRadiant ? ["bold", "subtle", "off"] : ["bold", "subtle"];
  const selected = radiant.kind === "radiant" ? radiant.intensity : state.radiantPreview;
  const name = itemDisplayName(item);
  const back = tr("Back to the wardrobe");
  return (
    <div ref={sheet} className="closet-radiant-sheet" data-detail={detail}>
      <div className="closet-radiant-title-row">
        <ClosetRadiantPip />
        <TextThatFits candidates={[tr("Radiant %@", name), name]} className="closet-radiant-title" />
        <IconButton symbol="xmark" size={22} help={back} onClick={() => store.showRadiant(undefined)} />
      </div>
      {detail === 0 && <p className="closet-radiant-description kit-caption kit-secondary">{description}</p>}
      {detail === 1 && <p className="closet-radiant-effect kit-caption kit-secondary">{effect}</p>}
      <div className="closet-radiant-choices" role="group" aria-label={tr("Radiant %@", name)}>
        {options.map((intensity) => (
          <RadiantChoice
            key={intensity}
            title={intensityTitle(intensity)}
            isSelected={selected === intensity}
            help={intensityHelp(intensity, isRadiant)}
            onClick={() => (isRadiant ? store.setRadiance(intensity, item) : store.previewRadiance(intensity))}
          />
        ))}
      </div>
      <div className="closet-radiant-spacer" />
      <RadiantFooter store={store} item={item} radiant={radiant} pinned={closet.save.radiantGoal === item} />
    </div>
  );
}

function RadiantFooter({ store, item, radiant, pinned }: { store: ClosetStore; item: PetItem; radiant: PetRadiantState; pinned: boolean }) {
  const row = useRef<HTMLDivElement>(null);
  const level = useFitLevel(row, 2, "x", `${item}|${radiant.kind}|${pinned}|${currentLanguage()}`);
  const price = radiantPrice(item);
  let content: ReactNode = null;
  switch (radiant.kind) {
    case "radiant": {
      /* The note shortens rather than clip in narrow panels. */
      const note = level === 0 ? tr("Upgraded. Friends on Party see it too.") : level === 1 ? tr("Upgraded") : undefined;
      content = (
        <>
          {note !== undefined && <span className="kit-tertiary closet-radiant-note">{note}</span>}
          <span className="closet-radiant-spacer" />
          <RadiantButton title={tr("Done")} isPrimary help={tr("Back to the wardrobe")} onClick={() => store.showRadiant(undefined)} />
        </>
      );
      break;
    }
    case "affordable":
    case "locked":
      content = (
        <>
          {/* The narrowest panels in the longest languages leave the price to the Upgrade button's tooltip rather than clip a button. */}
          {level < 2 && (
            <span className="closet-radiant-price">
              <Icon id="star.fill" size={8} className="closet-radiant-price-star" />
              <span className="closet-radiant-price-value">{formattedCount(price)}</span>
              {level === 0 && <span className="kit-tertiary">{tr("pts, 5x its price")}</span>}
            </span>
          )}
          <span className="closet-radiant-spacer" />
          <RadiantButton
            title={pinned ? tr("Unpin") : tr("Pin as goal")}
            isPrimary={false}
            help={pinned ? tr("Stop showing this goal in the wardrobe") : tr("Show your progress toward this upgrade in the wardrobe")}
            onClick={() => store.pinRadiantGoal(pinned ? undefined : item)}
          />
          {radiant.kind === "locked" ? (
            <RadiantButton
              title={tr("%@ to go", formattedCount(radiant.missing))}
              isPrimary
              disabled
              help={tr("%@ more points: %@ at a typical study pace", formattedCount(radiant.missing), PetEconomy.studyToEarn(radiant.missing))}
            />
          ) : (
            <RadiantButton title={tr("Upgrade")} isPrimary help={tr("Upgrade for %@ points", formattedCount(price))} onClick={() => store.upgradeToRadiant(item)} />
          )}
        </>
      );
      break;
    case "needsItem":
    case "notEligible":
      break;
  }
  return (
    <div ref={row} className="closet-radiant-footer kit-caption">
      {content}
    </div>
  );
}

/**
 * The wardrobe footer's pinned goal: "Radiant Wizard Hat 4,210 of 5,750"
 * with a thin bar; it opens the Radiant sheet. Narrower panels and longer
 * names drop "Radiant" (the pip says it), then the bar, then the name,
 * never cutting a word. Port of ClosetRadiantGoalLine.
 */
export function ClosetRadiantGoalLine({ goal, onClick }: { goal: PetRadiantGoal; onClick: () => void }) {
  const line = useRef<HTMLButtonElement>(null);
  const name = itemDisplayName(goal.item);
  const level = useFitLevel(line, 3, "x", `${goal.item}|${goal.have}|${currentLanguage()}`);
  const shownName = level === 0 ? tr("Radiant %@", name) : level <= 2 ? name : undefined;
  const bar = level !== 2;
  const ready = radiantGoalIsReady(goal);
  const help = tr("Your pinned goal: Radiant %@ for %@ points", name, formattedCount(goal.price));
  return (
    <Tooltip text={help}>
      <button ref={line} type="button" className="closet-radiant-goal" aria-label={help} onClick={onClick}>
        <ClosetRadiantPip pixelSize={1} />
        {shownName !== undefined && <span className="kit-secondary closet-radiant-goal-name">{shownName}</span>}
        <span className="closet-radiant-goal-count" data-ready={ready || undefined}>
          {ready ? tr("ready to upgrade") : tr("%@ of %@", formattedCount(goal.have), formattedCount(goal.price))}
        </span>
        {bar && (
          <span className="closet-radiant-goal-bar">
            <span style={{ width: Math.max(4, 44 * radiantGoalFraction(goal)) }} />
          </span>
        )}
      </button>
    </Tooltip>
  );
}
