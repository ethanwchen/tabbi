/*
 * Port of ClosetLook and ClosetSwatch: species, breed and fur color. The
 * labels take the width of the longest one in the language; the Compact
 * panel has no room for them beside every fur swatch, so there the rows go
 * without (the controls say what they are, and the rare furs keep a
 * sparkle), and the swatches and rows sit closer, before anything could be
 * cut off or pushed out of the panel.
 */

import { useMemo, useRef, type CSSProperties, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { PetCloset } from "../../core/closet/petCloset";
import { tr } from "../../core/localization/tr";
import { breedDisplayName, speciesDisplayName } from "../../core/pets/petBreed";
import { PET_SPECIES } from "../../core/pets/petKinds";
import { colorHex, colorsEqual, type PetColor } from "../../core/pets/petPalette";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { textWidth } from "../../ui/shell/measure";
import { ClosetPill } from "./ClosetPanel";
import type { ClosetStore } from "./closetStore";
import type { SurpriseGiftKeeper } from "./surpriseGiftKeeper";
import { useElementSize } from "./useElementSize";

interface LookVariant {
  readonly labeled: boolean;
  readonly rowSpacing: number;
  readonly swatchSpacing: number;
}

const LOOK_VARIANTS: readonly LookVariant[] = [
  { labeled: true, rowSpacing: 12, swatchSpacing: 6 },
  { labeled: true, rowSpacing: 8, swatchSpacing: 6 },
  { labeled: true, rowSpacing: 8, swatchSpacing: 4 },
  { labeled: false, rowSpacing: 8, swatchSpacing: 6 },
  { labeled: false, rowSpacing: 8, swatchSpacing: 2 },
];

const SWATCH = 22;
const ROW = 22;

export function ClosetLook({ store, gifts }: { store: ClosetStore; gifts: SurpriseGiftKeeper }) {
  const state = useStore(store);
  const rareFurs = useStore(gifts, (value) => value.rareFurs);
  const frame = useRef<HTMLDivElement>(null);
  const size = useElementSize(frame);
  const profile = state.profile;
  const furTint = state.closet.furTint;
  const rows = 3 + (rareFurs.length > 0 ? 1 : 0);

  const variant = useMemo(() => {
    if (size.width === 0) return LOOK_VARIANTS[0] as LookVariant;
    const labels = [tr("Pet"), tr("Breed"), tr("Fur"), tr("Rare")];
    const labelWidth = Math.max(...labels.map((label) => textWidth(label, 10.5, 500)));
    const fits = (candidate: LookVariant) => {
      const swatches = (1 + PetCloset.furSwatches.length) * SWATCH + PetCloset.furSwatches.length * candidate.swatchSpacing;
      const rare = (candidate.labeled ? 0 : SWATCH + candidate.swatchSpacing) + rareFurs.length * SWATCH + Math.max(0, rareFurs.length - 1) * candidate.swatchSpacing;
      const widest = Math.max(swatches, rare, 22 + 8 + 120 + 8 + 22);
      const width = (candidate.labeled ? labelWidth + 8 : 0) + widest;
      const height = rows * ROW + (rows - 1) * candidate.rowSpacing;
      return width <= size.width && height <= size.height;
    };
    return LOOK_VARIANTS.find(fits) ?? (LOOK_VARIANTS[LOOK_VARIANTS.length - 1] as LookVariant);
  }, [size, rareFurs.length, rows]);

  const row = (title: string, content: ReactNode) => (
    <div className="closet-look-row" style={{ height: ROW }}>
      {variant.labeled && <span className="closet-look-label kit-caption kit-tertiary">{title}</span>}
      <div className="closet-look-content">{content}</div>
    </div>
  );

  return (
    <div ref={frame} className="closet-section closet-look">
      <div className="closet-look-rows" style={{ gap: variant.rowSpacing }}>
        {row(
          tr("Pet"),
          <div className="closet-species">
            {PET_SPECIES.map((species) => (
              <ClosetPill
                key={species}
                title={speciesDisplayName(species)}
                symbol={species === "cat" ? "cat.fill" : "dog.fill"}
                isSelected={profile.species === species}
                help={tr("Make your pet a %@", speciesDisplayName(species).toLowerCase())}
                onClick={() => store.setSpecies(species)}
              />
            ))}
          </div>,
        )}
        {row(
          tr("Breed"),
          <div className="closet-breed">
            <IconButton symbol="chevron.backward" size={22} help={tr("Previous breed")} onClick={() => store.cycleBreed(-1)} />
            <MarqueeText text={breedDisplayName(profile.breed)} className="kit-body-emphasis closet-breed-name" />
            <IconButton symbol="chevron.forward" size={22} help={tr("Next breed")} onClick={() => store.cycleBreed(1)} />
          </div>,
        )}
        {row(
          tr("Fur"),
          <div className="closet-swatches" style={{ gap: variant.swatchSpacing }}>
            <ClosetSwatch color={undefined} isSelected={furTint === undefined} onClick={() => store.tintFur(undefined)} />
            {PetCloset.furSwatches.map((color) => (
              <ClosetSwatch key={colorHex(color)} color={color} isSelected={furTint !== undefined && colorsEqual(furTint, color)} onClick={() => store.tintFur(color)} />
            ))}
          </div>,
        )}
        {/* Rare furs come only as surprise gifts, so the row shows once one is found. */}
        {rareFurs.length > 0 &&
          row(
            tr("Rare"),
            <div className="closet-swatches" style={{ gap: variant.swatchSpacing }}>
              {!variant.labeled && (
                <Tooltip text={tr("Rare")}>
                  <span className="closet-rare-mark">
                    <Icon id="sparkles" size={10} />
                  </span>
                </Tooltip>
              )}
              {rareFurs.map((fur) => (
                <ClosetSwatch key={fur.id} color={fur.color} isSelected={furTint !== undefined && colorsEqual(furTint, fur.color)} onClick={() => store.tintFur(fur.color)} />
              ))}
            </div>,
          )}
      </div>
    </div>
  );
}

/** A round fur-color swatch; undefined is the breed's own colors. Onboarding's pet step shows the same swatches. Port of ClosetSwatch. */
export function ClosetSwatch({ color, isSelected, onClick }: { color: PetColor | undefined; isSelected: boolean; onClick: () => void }) {
  const help = color === undefined ? tr("Breed colors") : (PetCloset.swatchName(color) ?? tr("Fur color %@", colorHex(color)));
  const fill = color === undefined ? "var(--surface-hover)" : `rgb(${color.red} ${color.green} ${color.blue})`;
  return (
    <Tooltip text={help}>
      <button type="button" className="closet-swatch" data-selected={isSelected} aria-label={help} aria-pressed={isSelected} onClick={onClick}>
        <span className="closet-swatch-color" style={{ background: fill } as CSSProperties}>
          {color === undefined && <Icon id="arrow.counterclockwise" size={8} fixedDirection />}
        </span>
      </button>
    </Tooltip>
  );
}
