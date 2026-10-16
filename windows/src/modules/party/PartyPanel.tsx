/*
 * Port of PartyPanel: the Party tab: the party (or a way into one) on the
 * left and friends on the right once connected; before that, a single calm
 * state for connecting, an unreachable server, the age check, or a server
 * setting that can't work. The report card covers it while open, a notice
 * sits at the bottom and the team celebration across the top.
 */

import { useEffect, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { PartyError, partyErrorMessage } from "../../core/party/partyError";
import { SupportContact } from "../../core/party/partyModeration";
import { partyPet } from "../../core/party/partyPetAppearance";
import type { PetProfile } from "../../core/pets/petProfile";
import { Icon } from "../../ui/kit/Icon";
import { StatusMessage } from "../../ui/kit/StatusMessage";
import { Tooltip } from "../../ui/kit/Tooltip";
import { PartyAgeCheckView } from "./PartyAgeCheckView";
import { PartyCelebrationBanner } from "./PartyCelebrationBanner";
import { PartyPillButton } from "./PartyComponents";
import { FRIENDS_WIDTH, PartyFriendsCard } from "./PartyFriendsCard";
import { PartyReportCard } from "./PartyReportCard";
import { PartyStage } from "./PartyStage";
import type { PartyStore } from "./partyStore";
import "./party.css";

export function PartyPanel({ store, onOpenURL }: { store: PartyStore; onOpenURL: (url: string) => void }) {
  const state = useStore(store);
  useEffect(() => {
    store.setVisible(true);
    return () => store.setVisible(false);
  }, [store]);
  const connection = state.party.connection;
  let content: ReactNode;
  switch (connection.kind) {
    case "connected":
      content = (
        <div className="party-columns">
          <PartyStage store={store} onFieldFocus={() => {}} />
          <div style={{ width: FRIENDS_WIDTH, flex: "none", display: "flex" }}>
            <PartyFriendsCard store={store} onFieldFocus={() => {}} />
          </div>
        </div>
      );
      break;
    case "ageCheck":
      content = <PartyAgeCheckView store={store} tooYoungUntil={connection.tooYoungUntil} />;
      break;
    case "connecting":
      content = <StatusMessage symbol={null} pet={state.pet} title={tr("Joining the party server…")} message={tr("Signing you in so friends can find you.")} />;
      break;
    case "unreachable":
      content =
        connection.error.kind === "banned" ? (
          <StatusMessage
            symbol="hand.raised.fill"
            title={tr("Party isn't available")}
            message={tr("This account can no longer use Party. If you think that's a mistake, write to %@.", SupportContact.email)}
            actions={<PartyPillButton title={tr("Email Support")} symbol="envelope" help={tr("Copy the support address, %@", SupportContact.email)} onClick={() => onOpenURL(SupportContact.mailURL)} />}
          />
        ) : (
          <StatusMessage
            symbol="wifi.slash"
            title={tr("Can't reach the party server")}
            message={unreachableDetail(connection.error)}
            actions={<PartyPillButton title={tr("Try again")} symbol="arrow.clockwise" help={tr("Connect to the party server now")} onClick={() => store.retry()} />}
          />
        );
      break;
    case "invalidServer":
      content = (
        <StatusMessage
          symbol="exclamationmark.triangle"
          title={tr("Check the party server")}
          message={tr("%@ Fix it in Settings > Tabs > Party > Options, or clear it to use the Tabbi server.", connection.message)}
        />
      );
      break;
  }
  return (
    <div className="party-panel">
      {content}
      {state.reporting !== undefined && connection.kind === "connected" && (
        <div className="party-overlay">
          <PartyReportCard key={state.reporting.code} profile={state.reporting} store={store} />
        </div>
      )}
      {state.notice !== undefined && (
        <Tooltip text={tr("Click to dismiss")}>
          <button type="button" className="party-notice kit-caption" onClick={() => store.clearNotice()}>
            <Icon id={state.noticeConfirms ? "checkmark.circle.fill" : "exclamationmark.circle.fill"} size={11} style={{ color: state.noticeConfirms ? "var(--success)" : "var(--warning)" }} />
            <span className="party-notice-text kit-user-text">{state.notice}</span>
          </button>
        </Tooltip>
      )}
      {state.celebration !== undefined && (
        <div className="party-celebration-slot">
          <PartyCelebrationBanner celebration={state.celebration} pets={celebratingPets(store)} onDismiss={() => store.clearCelebration()} />
        </div>
      )}
    </div>
  );
}

/** The title already says the server can't be reached; this says why (when it's more than the network) and what happens next. */
function unreachableDetail(error: PartyError): string {
  switch (error.kind) {
    case "unreachable":
    case "timedOut":
    case "transport":
      return tr("Check your internet connection. Friends and parties show up once it's back.");
    default:
      return error.isTransient ? tr("%@ Trying again in the background.", partyErrorMessage(error)) : partyErrorMessage(error);
  }
}

/** The members' pets as friends see them, mine first; just mine when the party is gone. */
function celebratingPets(store: PartyStore): PetProfile[] {
  const state = store.state;
  const members = state.party.party?.members ?? [];
  const mine = members.filter((member) => member.profile.code === state.party.friendCode);
  const others = members.filter((member) => member.profile.code !== state.party.friendCode);
  const pets = [...mine, ...others].map((member) => partyPet(member.profile));
  return pets.length === 0 ? [state.pet] : pets;
}
