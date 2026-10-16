/*
 * Port of ClosetSetupView: onboarding's pet step: cat or dog, a breed and
 * a name, each one tap (or a few keystrokes) on the shared pet, so the
 * Closet, the coach and the closed island start with the pet picked here.
 * Edits apply right away; the footer's Continue just moves on.
 */

import { useEffect, useRef, useState, type CSSProperties, type KeyboardEvent } from "react";
import { useStore } from "../../app/useStore";
import { PetCloset } from "../../core/closet/petCloset";
import { tr } from "../../core/localization/tr";
import { breedDisplayName, breedsOf, speciesDisplayName } from "../../core/pets/petBreed";
import { PET_SPECIES, type PetBreed } from "../../core/pets/petKinds";
import { colorHex, colorsEqual } from "../../core/pets/petPalette";
import type { PetProfile } from "../../core/pets/petProfile";
import { Card } from "../../ui/kit/Card";
import { useTheme } from "../../ui/kit/context";
import { accentVariables } from "../../ui/kit/tokens";
import { CLOSET_ACCENT } from "./closetDescriptor";
import { Icon } from "../../ui/kit/Icon";
import { PetSprite, PetView } from "../../ui/kit/PetView";
import { Tooltip } from "../../ui/kit/Tooltip";
import { ClosetSwatch } from "./ClosetLook";
import type { ClosetStore } from "./closetStore";
import "./closet.css";

export function ClosetSetupView({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const theme = useTheme();
  const profile = state.profile;
  const furTint = state.closet.furTint;
  /* The pet as it would look as `breed`, with its fur color and outfit. */
  const preview = (breed: PetBreed): PetProfile => {
    const closet = new PetCloset(state.closet.save.copy());
    closet.setBreed(breed);
    return closet.profile;
  };
  return (
    /* The step draws in the takeover, outside any module's panel, so it carries the Closet's accent itself. */
    <div className="closet-setup" style={accentVariables(theme, CLOSET_ACCENT) as CSSProperties}>
      <ClosetSetupPetCard store={store} />
      <Card className="closet-setup-card">
        <div className="closet-setup-top">
          {PET_SPECIES.map((species) => (
            <ClosetSetupSpeciesPill key={species} title={speciesDisplayName(species)} symbol={species === "cat" ? "cat.fill" : "dog.fill"} isSelected={profile.species === species} onClick={() => store.setSpecies(species)} />
          ))}
          <span className="closet-spacer" />
          <span className="kit-caption kit-secondary closet-setup-breed">{breedDisplayName(profile.breed)}</span>
        </div>
        <div className="closet-setup-breeds">
          {breedsOf(profile.species).map((breed) => (
            <Tooltip key={breed} text={breedDisplayName(breed)}>
              <button type="button" className="closet-setup-breed-tile" data-selected={breed === profile.breed} aria-label={breedDisplayName(breed)} onClick={() => store.setBreed(breed)}>
                <PetSprite profile={preview(breed)} pixelSize={1} />
              </button>
            </Tooltip>
          ))}
        </div>
        <div className="closet-setup-fur">
          <span className="kit-caption kit-tertiary closet-setup-fur-label">{tr("Fur")}</span>
          <ClosetSwatch color={undefined} isSelected={furTint === undefined} onClick={() => store.tintFur(undefined)} />
          {PetCloset.furSwatches.map((color) => (
            <ClosetSwatch key={colorHex(color)} color={color} isSelected={furTint !== undefined && colorsEqual(furTint, color)} onClick={() => store.tintFur(color)} />
          ))}
        </div>
      </Card>
    </div>
  );
}

/** The pet, animated, above its name in a field-like button; a click edits it in place, as in the Closet. */
function ClosetSetupPetCard({ store }: { store: ClosetStore }) {
  const name = useStore(store, (state) => state.profile.name);
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState("");
  const latest = useRef({ renaming, draft });
  useEffect(() => {
    latest.current = { renaming, draft };
  }, [renaming, draft]);
  /* Continue moves on without a Return, so keep what was typed. */
  useEffect(
    () => () => {
      if (latest.current.renaming) store.rename(latest.current.draft);
    },
    [store],
  );
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
    <Card padding={8} className="closet-setup-pet">
      <div className="closet-setup-pet-view">
        <PetView player={store.preview} pixelSize={2} />
      </div>
      {renaming ? (
        <input className="closet-setup-name closet-setup-name-field kit-body-emphasis kit-user-text" aria-label={tr("Name")} autoFocus value={draft} onChange={(event) => setDraft(event.target.value)} onKeyDown={onKey} onBlur={commit} />
      ) : (
        <Tooltip text={tr("Name your pet")}>
          <button
            type="button"
            className="closet-setup-name"
            onClick={() => {
              setDraft(name);
              setRenaming(true);
            }}
          >
            <span className="kit-body-emphasis closet-setup-name-text kit-user-text">{name}</span>
            <Icon id="pencil" size={9.5} className="closet-name-pencil" />
          </button>
        </Tooltip>
      )}
    </Card>
  );
}

/** Cat or Dog, accent-tinted when picked. */
function ClosetSetupSpeciesPill({ title, symbol, isSelected, onClick }: { title: string; symbol: string; isSelected: boolean; onClick: () => void }) {
  return (
    <Tooltip text={tr("Pick %@", title)}>
      <button type="button" className="closet-setup-species" data-selected={isSelected} aria-pressed={isSelected} onClick={onClick}>
        <Icon id={symbol} size={10} />
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}

