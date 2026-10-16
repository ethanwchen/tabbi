/*
 * Port of PartyCelebrationBanner: "Great job, team!" across the top of the
 * Party panel when a shared session runs to its end: the members' pets hop,
 * with the points earned beside them. Under Reduce Motion the pets stay put.
 */

import { tr } from "../../core/localization/tr";
import type { PartyTeamCelebration } from "../../core/party/partyTeamCelebration";
import type { PetProfile } from "../../core/pets/petProfile";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { HoppingPet } from "./PartyComponents";

const MAX_PETS = 4;

export function PartyCelebrationBanner({ celebration, pets, onDismiss }: { celebration: PartyTeamCelebration; pets: readonly PetProfile[]; onDismiss: () => void }) {
  return (
    <Tooltip text={tr("The shared session is done. Click to dismiss.")}>
      <button type="button" className="party-banner" onClick={onDismiss}>
        <span className="party-banner-pets">
          {pets.slice(0, MAX_PETS).map((pet, index) => (
            <HoppingPet key={index} pet={pet} delay={index * 0.15} />
          ))}
        </span>
        <span className="party-banner-text">
          <MarqueeText text={celebration.title} className="kit-title" />
          <MarqueeText text={celebration.detail} userText className="kit-caption party-banner-detail" />
        </span>
        <Icon id="close" size={9} className="party-banner-close" />
      </button>
    </Tooltip>
  );
}
