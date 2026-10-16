/*
 * Port of PartyInviteViews: what an invite link opens: the whole island
 * asks "Add a friend?" or "Join this party?" (turning Party on first if
 * it's off) and says how it went. `PartyInviteFlow` decides the step and
 * its words; this draws them.
 */

import type { CSSProperties } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import type { PartyInviteFlow } from "../../core/party/partyInviteFlow";
import type { ModuleAccent } from "../../core/themes/themeColor";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { Spinner } from "../../ui/kit/Loading";
import { useTheme } from "../../ui/kit/context";
import { accentVariables } from "../../ui/kit/tokens";
import { PartyPet, PartyPillButton, PartyTextButton } from "./PartyComponents";
import type { PartyStore } from "./partyStore";

export interface PartyInviteActions {
  readonly turnOnParty: () => void;
  /** Closing after a friend was added or a party joined goes on to the Party tab, where they now show. */
  readonly showPartyTab: () => void;
}

/** "Party invite" where the tab bar usually sits. */
export function PartyInviteTitle({ symbol, accent }: { symbol: string; accent: ModuleAccent }) {
  const theme = useTheme();
  return (
    <span className="takeover-step" style={accentVariables(theme, accent) as CSSProperties}>
      <Icon id={symbol} size={14} style={{ color: "var(--accent)" }} />
      <span>{tr("Party invite")}</span>
    </span>
  );
}

/** One card: a pet or symbol on the left, the question or answer beside it, and its buttons underneath. */
export function PartyInviteBody({ store, accent, symbol, actions }: { store: PartyStore; accent: ModuleAccent; symbol: string; actions: PartyInviteActions }) {
  const theme = useTheme();
  const invite = useStore(store, (state) => state.invite);
  const flow = invite?.flow;
  if (flow === undefined) return null;
  const stage = flow.stage;
  const working = stage.kind === "connecting" || stage.kind === "working";
  const primary = () => {
    switch (stage.kind) {
      case "needsParty":
        actions.turnOnParty();
        break;
      case "unavailable":
        store.retryInviteConnection();
        break;
      case "ageCheck":
        store.dismissInvite();
        actions.showPartyTab();
        break;
      default:
        store.confirmInvite();
    }
  };
  const close = () => {
    const finished = stage.kind === "finished";
    store.dismissInvite();
    if (finished) actions.showPartyTab();
  };
  const primaryTitle = flow.primaryTitle;
  return (
    <Card padding={24} className="party-invite" style={accentVariables(theme, accent) as CSSProperties}>
      <div className="party-invite-art">
        <InviteArtwork flow={flow} store={store} symbol={symbol} />
      </div>
      <div className="party-invite-text">
        <div className="party-invite-words">
          <span className="kit-title party-nowrap">{flow.title}</span>
          <span className="kit-body kit-secondary party-invite-message">{flow.message}</span>
        </div>
        <div className="party-invite-buttons">
          {primaryTitle !== undefined && <PartyPillButton title={primaryTitle} prominent busy={stage.kind === "working"} help={primaryHelp(flow)} onClick={primary} />}
          {primaryTitle === undefined ? (
            <PartyPillButton title={flow.dismissTitle} prominent help={tr("Close the invite")} onClick={close} />
          ) : (
            <PartyTextButton title={flow.dismissTitle} help={tr("Close the invite without doing anything")} onClick={close} />
          )}
          {working && <Spinner tint="var(--accent)" size={12} />}
        </div>
      </div>
    </Card>
  );
}

function InviteArtwork({ flow, store, symbol }: { flow: PartyInviteFlow; store: PartyStore; symbol: string }) {
  const pet = useStore(store, (state) => state.pet);
  const person = flow.person;
  if (person !== undefined) return <PartyPet profile={person} pixelSize={2} />;
  const badge = (id: string) => (
    <span className="party-invite-badge">
      <Icon id={id} size={22} />
    </span>
  );
  const stage = flow.stage;
  switch (stage.kind) {
    case "needsParty":
    case "connecting":
      return <PartyPet pet={pet} pixelSize={2} />;
    case "unavailable":
      return badge("wifi.slash");
    case "ageCheck":
      return badge(stage.tooYoungUntil === undefined ? "question" : "hand.raised.fill");
    case "refused":
      return badge("exclamationmark.circle.fill");
    case "finished":
      return badge("check");
    case "confirming":
    case "working":
      return badge(flow.invite.kind === "addFriend" ? "person.badge.plus" : symbol);
  }
}

function primaryHelp(flow: PartyInviteFlow): string {
  switch (flow.stage.kind) {
    case "needsParty":
      return tr("Add the Party tab and connect to the party server");
    case "unavailable":
    case "refused":
      return tr("Try again now");
    case "ageCheck":
      return tr("Open the Party tab to answer");
    default:
      return flow.invite.kind === "addFriend" ? tr("Send a friend request with this code") : tr("Join this party now");
  }
}
