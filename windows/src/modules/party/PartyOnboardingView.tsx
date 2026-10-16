/*
 * Port of PartyOnboardingView: onboarding's party step: the profile friends
 * will see (my pet and a name to edit in place), going invisible in one
 * tap, and beside it my friend code to share and a field to add a friend's.
 * While the server hasn't answered yet it says so, with a retry when it
 * can't be reached.
 */

import { useEffect, useRef, useState, type CSSProperties, type KeyboardEvent } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { PartyCode } from "../../core/party/partyModels";
import { SupportContact, refusalMessage } from "../../core/party/partyModeration";
import { cleanedPartyName, PARTY_MAX_NAME_LENGTH, partySettings, refusedNames } from "../../core/party/partySettings";
import type { ModuleAccent } from "../../core/themes/themeColor";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useTheme } from "../../ui/kit/context";
import { accentVariables } from "../../ui/kit/tokens";
import { PartyAgeCheckView } from "./PartyAgeCheckView";
import { PartyCodeField, PartyCopyCode, PartyPet, PartyPillButton } from "./PartyComponents";
import type { PartyStore } from "./partyStore";

export function PartyOnboardingView({ store, accent }: { store: PartyStore; accent: ModuleAccent }) {
  const state = useStore(store);
  const theme = useTheme();
  useEffect(() => {
    /* Visible like the panel, so friends load and a failed connect retries. */
    store.setVisible(true);
    return () => store.setVisible(false);
  }, [store]);
  const connection = state.party.connection;
  const style = accentVariables(theme, accent) as CSSProperties;
  if (connection.kind === "ageCheck") {
    return (
      <div className="party-setup" style={style}>
        <PartyAgeCheckView store={store} tooYoungUntil={connection.tooYoungUntil} />
      </div>
    );
  }
  return (
    <div className="party-setup party-setup-columns" style={style}>
      <div style={{ width: 252, flex: "none", display: "flex" }}>
        <PartySetupProfileCard store={store} />
      </div>
      <PartySetupFriendsCard store={store} />
    </div>
  );
}

/** My pet, the name friends see (click to rename) and the connection status, what is shared, and the invisible switch. */
function PartySetupProfileCard({ store }: { store: PartyStore }) {
  const state = useStore(store);
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState("");
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (renaming) input.current?.focus();
  }, [renaming]);
  const name = cleanedPartyName(state.settings) ?? state.party.profile?.name;
  const refused = (() => {
    let current = store.refusedNames;
    if (renaming) current = { ...current, name: refusedNames(partySettings({ name: draft }), state.pet).name };
    return refusalMessage(current);
  })();
  const commit = () => {
    if (!renaming) return;
    store.update({ ...state.settings, name: [...draft].slice(0, PARTY_MAX_NAME_LENGTH * 2).join("") });
    setRenaming(false);
  };
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") commit();
    if (event.key === "Escape") setRenaming(false);
  };
  const status = (() => {
    switch (state.party.connection.kind) {
      case "connected":
        return state.settings.invisible ? { text: tr("Invisible to friends"), color: "var(--tertiary-text)" } : { text: tr("Online"), color: "var(--success)" };
      case "ageCheck":
        return { text: tr("Not joined yet"), color: "var(--tertiary-text)" };
      case "connecting":
        return { text: tr("Joining the party server"), color: "var(--tertiary-text)" };
      case "unreachable":
        return state.party.connection.error.kind === "banned" ? { text: tr("Not available"), color: "var(--tertiary-text)" } : { text: tr("Offline"), color: "var(--warning)" };
      case "invalidServer":
        return { text: tr("Offline"), color: "var(--warning)" };
    }
  })();
  const invisible = state.settings.invisible;
  return (
    <Card className="party-setup-profile">
      <div className="party-setup-head">
        <div className="party-setup-pet">
          <PartyPet pet={state.pet} pixelSize={1.5} />
        </div>
        <div className="party-setup-name-column">
          {renaming ? (
            <input
              ref={input}
              className="party-setup-name-input kit-body-emphasis kit-user-text"
              aria-label={tr("Name")}
              value={draft}
              maxLength={PARTY_MAX_NAME_LENGTH * 2}
              onChange={(event) => setDraft(event.target.value)}
              onBlur={commit}
              onKeyDown={onKeyDown}
            />
          ) : (
            <Tooltip text={tr("The name friends see, up to %lld characters. Click to change it.", PARTY_MAX_NAME_LENGTH)}>
              <button
                type="button"
                className="party-setup-name"
                onClick={() => {
                  setDraft(name ?? "");
                  setRenaming(true);
                }}
              >
                <MarqueeText text={name ?? tr("Add your name")} userText={name !== undefined} className={name === undefined ? "kit-body-emphasis kit-secondary" : "kit-body-emphasis"} />
                <Icon id="pencil" size={9} className="party-setup-pencil" />
              </button>
            </Tooltip>
          )}
          <div className="party-setup-status kit-caption kit-tertiary">
            <span className="party-dot" style={{ background: status.color }} />
            <MarqueeText text={status.text} />
          </div>
        </div>
      </div>
      {refused !== undefined ? (
        <span className="kit-caption party-setup-issue">
          <Icon id="exclamationmark.triangle.fill" size={10} />
          <span>{refused}</span>
        </span>
      ) : (
        <span className="kit-caption kit-secondary party-setup-note">{tr("Friends see your name, your pet and when you're studying. Nothing about your cards or decks leaves your PC.")}</span>
      )}
      <span className="party-spacer" />
      <Tooltip text={invisible ? tr("Show friends when you study again") : tr("Go invisible. Your study minutes still count.")}>
        <button type="button" className="party-visibility kit-caption" onClick={() => store.update({ ...state.settings, invisible: !invisible })}>
          <Icon id={invisible ? "eye.slash.fill" : "eye.fill"} size={10} style={{ color: invisible ? "var(--secondary-text)" : "var(--accent)" }} />
          <MarqueeText text={invisible ? tr("Invisible: friends see you as away") : tr("Visible: friends see when you study")} />
        </button>
      </Tooltip>
    </Card>
  );
}

const SHOWN_PETS = 6;

/** My friend code to share and a field to add a friend's, once the server answers; until then, what is happening with the connection. */
function PartySetupFriendsCard({ store }: { store: PartyStore }) {
  const state = useStore(store);
  const party = state.party;
  const connection = party.connection;
  const friendsTitle = !party.friendsLoaded || party.friends.length === 0 ? tr("No friends yet") : party.friends.length === 1 ? tr("1 friend") : tr("%lld friends", party.friends.length);
  const message = (symbol: string, title: string, detail: string | undefined, isNotice = false) => (
    <div className="party-setup-message">
      <div className="party-setup-message-head">
        <Icon id={symbol} size={11} style={{ color: "var(--accent)" }} />
        <MarqueeText text={title} className="kit-body-emphasis" />
      </div>
      {detail !== undefined && <span className="kit-caption party-setup-detail" style={{ color: isNotice ? "var(--warning)" : "var(--secondary-text)" }}>{detail}</span>}
    </div>
  );
  let content;
  switch (connection.kind) {
    case "connected":
      content = (
        <>
          {message("person.2.fill", friendsTitle, state.notice ?? (party.friends.length === 0 ? tr("Share your code, or add theirs below. Start a party from the Party tab.") : undefined), state.notice !== undefined)}
          {party.friends.length > 0 && (
            <div className="party-setup-pets">
              {party.friends.slice(0, SHOWN_PETS).map((friend) => (
                <Tooltip key={friend.profile.code} text={friend.online ? friend.profile.name : tr("%@ is away", friend.profile.name)}>
                  <span>
                    <PartyPet profile={friend.profile} asleep={!friend.online} />
                  </span>
                </Tooltip>
              ))}
              {party.friends.length > SHOWN_PETS && <span className="kit-caption kit-tertiary">{`+${party.friends.length - SHOWN_PETS}`}</span>}
            </div>
          )}
        </>
      );
      break;
    case "connecting":
    case "ageCheck":
      content = message("antenna.radiowaves.left.and.right", tr("Joining the party server"), tr("Signing you in so friends can find you. Your code shows here in a moment."));
      break;
    case "unreachable":
      content =
        connection.error.kind === "banned" ? (
          message("hand.raised.fill", tr("Party isn't available"), tr("This account can no longer use Party. Write to %@ if that's a mistake.", SupportContact.email))
        ) : (
          <div className="party-setup-unreachable">
            {message("wifi.slash", tr("Can't reach the party server"), tr("Check your internet connection. You can also set up Party later in its tab."))}
            <PartyPillButton title={tr("Try Again")} symbol="arrow.clockwise" help={tr("Connect to the party server now")} onClick={() => store.retry()} />
          </div>
        );
      break;
    case "invalidServer":
      content = message("exclamationmark.triangle.fill", tr("Check the party server"), tr("%@ Fix it in Settings > Tabs > Party > Options.", connection.message));
      break;
  }
  return (
    <Card padding={8} className="party-setup-friends">
      <div className="party-setup-friends-header">
        <span className="kit-caption kit-tertiary">{tr("Your code")}</span>
        <span className="party-spacer" />
        {party.friendCode !== undefined && <PartyCopyCode code={party.friendCode} showsLabel help={tr("Your friend code. Copy it and send it to a friend.")} />}
      </div>
      <div className="party-setup-friends-body">{content}</div>
      {connection.kind === "connected" && (
        <PartyCodeField
          placeholder={tr("Friend's code")}
          symbol="person.badge.plus"
          length={PartyCode.friendCodeLength}
          help={tr("Type or paste a friend's %lld-character code and press Return", PartyCode.friendCodeLength)}
          onSubmit={(text) => store.addFriend(text)}
        />
      )}
    </Card>
  );
}
