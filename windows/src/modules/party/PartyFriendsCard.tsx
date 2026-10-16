/*
 * Port of PartyFriendsCard: the right column: my friend code to share,
 * friend requests waiting for me on top, friends with their pets and what
 * they're doing, the requests I sent at the bottom, and a field to ask
 * someone by code.
 */

import { useCallback } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { partyErrorMessage } from "../../core/party/partyError";
import { canJoin, isFoundingMember, PartyCode, type PartyFriend, type PartyFriendRequest } from "../../core/party/partyModels";
import { compactStatusLine, rosterDuration, rosterStatus } from "../../core/party/partyRoster";
import { Card } from "../../ui/kit/Card";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { FoundingBadge } from "../../ui/kit/FoundingBadge";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useElementWidth } from "../../ui/kit/useElementWidth";
import { PartyCodeField, PartyCopyCode, PartyPet, PartyPillButton, PartyShareInvite, statusColor } from "./PartyComponents";
import { useModerationMenu } from "./PartyModeration";
import type { PartyStore } from "./partyStore";

export function PartyFriendsCard({ store, onFieldFocus }: { store: PartyStore; onFieldFocus: (focused: boolean) => void }) {
  const state = useStore(store);
  const party = state.party;
  const [header, headerWidth] = useElementWidth<HTMLDivElement>();
  const showsLabel = headerWidth === 0 || headerWidth >= 200;
  return (
    <Card padding={8} className="party-friends">
      <div ref={header} className="party-friends-header">
        <span className="kit-caption kit-tertiary party-nowrap">{tr("Friends")}</span>
        {party.staleError !== undefined && (
          <IconButton
            symbol="wifi.exclamationmark"
            size={16}
            tint="var(--warning)"
            className="party-stale"
            help={tr("%@ Showing the last known status. Click to retry.", partyErrorMessage(party.staleError))}
            onClick={() => store.retry()}
          />
        )}
        <span className="party-spacer" />
        {party.friendCode !== undefined && (
          <div className="party-share-code">
            <PartyCopyCode code={party.friendCode} showsLabel={showsLabel} help={tr("Your friend code. Copy it and send it to a friend.")} />
            <PartyShareInvite invite={{ kind: "addFriend", code: party.friendCode }} help={tr("Share an invite link. A friend who opens it can add you in one click.")} />
          </div>
        )}
      </div>
      <div className="party-friends-list">
        {!party.friendsLoaded ? null : !party.hasPeople ? (
          <div className="party-friends-empty">
            <Icon id="person.2" size={16} style={{ color: "var(--accent)" }} />
            <span className="kit-body-emphasis">{tr("No friends yet")}</span>
            <span className="kit-caption kit-secondary">{tr("Share your code above, or add theirs below.")}</span>
          </div>
        ) : (
          <EdgeFade edge="bottom" length={12} className="party-friends-scroll">
            <div className="party-friends-rows">
              {party.incomingRequests.map((request) => (
                <PartyRequestRow key={request.profile.code} request={request} isIncoming store={store} />
              ))}
              {party.friends.map((friend) => (
                <PartyFriendRow key={friend.profile.code} friend={friend} store={store} now={state.now} />
              ))}
              {party.outgoingRequests.map((request) => (
                <PartyRequestRow key={request.profile.code} request={request} isIncoming={false} store={store} />
              ))}
            </div>
          </EdgeFade>
        )}
      </div>
      <PartyCodeField
        placeholder={tr("Friend's code")}
        symbol="person.badge.plus"
        length={PartyCode.friendCodeLength}
        help={tr("Type or paste a friend's %lld-character code and press Return", PartyCode.friendCodeLength)}
        onSubmit={(text) => store.addFriend(text)}
        onFocusChange={onFieldFocus}
      />
    </Card>
  );
}

/** One friend: their pet, name, what they're doing, and Join when they're in a party I'm not in. Right-click to remove, report or block. */
function PartyFriendRow({ friend, store, now }: { friend: PartyFriend; store: PartyStore; now: number }) {
  const myParty = useStore(store, (state) => state.party.party?.code);
  const status = rosterStatus(friend.presence, friend.online);
  const parts = [tr("%@ with %@", friend.profile.name, friend.profile.petName)];
  if (isFoundingMember(friend.profile)) parts.push(tr("Founding Member"));
  if (friend.presence !== undefined && friend.online && friend.presence.todayMinutes > 0) parts.push(tr("%@ studied today", rosterDuration(friend.presence.todayMinutes)));
  if (friend.presence !== undefined && friend.presence.streakDays > 1) parts.push(tr("%lld-day streak", friend.presence.streakDays));
  const help = parts.join(" · ") + ". " + tr("Right-click to remove, report or block.");
  const leading = useCallback(
    () => [{ title: tr("Remove %@", friend.profile.name), symbol: "minus.circle.fill", destructive: true, onSelect: () => store.removeFriend(friend.profile.code) }],
    [store, friend.profile],
  );
  const menu = useModerationMenu(store, friend.profile, leading);
  return (
    <Tooltip text={help}>
      <div className="party-row" onContextMenu={menu.open}>
        <PartyPet profile={friend.profile} asleep={status === "offline"} />
        <div className="party-row-text">
          <div className="party-row-name">
            <MarqueeText text={friend.profile.name} userText className={status === "offline" ? "kit-body-emphasis kit-secondary" : "kit-body-emphasis"} />
            {isFoundingMember(friend.profile) && <FoundingBadge isMe={false} />}
          </div>
          <div className="party-row-status kit-caption kit-tertiary">
            <span className="party-dot" style={{ background: statusColor(status) }} />
            <MarqueeText text={compactStatusLine(friend.presence, friend.online, now)} />
          </div>
        </div>
        {friend.party !== undefined && friend.party.code === myParty ? (
          <Tooltip text={tr("%@ is in your party", friend.profile.name)}>
            <span className="party-row-in-party">
              <Icon id="person.2.fill" size={10} />
            </span>
          </Tooltip>
        ) : canJoin(friend) ? (
          <PartyPillButton
            title={tr("Join")}
            height={20}
            busy={store.isPending({ kind: "joinFriend", code: friend.profile.code })}
            help={tr("Join %@'s party", friend.profile.name)}
            onClick={() => store.joinFriend(friend.profile.code)}
          />
        ) : null}
        {menu.element}
      </div>
    </Tooltip>
  );
}

/** A friend request: someone who wants to be friends, with Accept and Decline, or someone I asked, with a way to cancel. */
function PartyRequestRow({ request, isIncoming, store }: { request: PartyFriendRequest; isIncoming: boolean; store: PartyStore }) {
  const profile = request.profile;
  const busy = store.isPending({ kind: "acceptFriend", code: profile.code }) || store.isPending({ kind: "removeFriend", code: profile.code });
  const [row, width] = useElementWidth<HTMLDivElement>();
  /* The whole sentence and a spelled-out Accept while they fit, then a check mark for Accept and a shorter word: nothing is cut. */
  const roomy = width === 0 || width >= 236;
  const help =
    (isIncoming ? tr("%@ with %@ wants to be friends.", profile.name, profile.petName) : tr("You asked %@ to be friends. You'll see each other once they accept.", profile.name)) +
    " " +
    tr("Right-click to report or block.");
  const leading = useCallback(
    () =>
      isIncoming
        ? [
            { title: tr("Accept"), symbol: "check", onSelect: () => store.acceptFriend(request) },
            { title: tr("Decline"), symbol: "close", onSelect: () => store.removeFriend(profile.code) },
          ]
        : [{ title: tr("Cancel Request"), symbol: "close", onSelect: () => store.removeFriend(profile.code) }],
    [store, request, profile.code, isIncoming],
  );
  const menu = useModerationMenu(store, profile, leading);
  const status = isIncoming ? (roomy ? tr("Wants to be friends") : tr("Request")) : roomy ? tr("Request sent") : tr("Sent");
  return (
    <Tooltip text={help}>
      <div ref={row} className="party-row" data-incoming={isIncoming || undefined} onContextMenu={menu.open}>
        <PartyPet profile={profile} />
        <div className="party-row-text">
          <div className="party-row-name">
            <MarqueeText text={profile.name} userText className="kit-body-emphasis" />
            {isFoundingMember(profile) && <FoundingBadge isMe={false} />}
          </div>
          <MarqueeText text={status} className="kit-caption" style={{ color: isIncoming ? "var(--accent)" : "var(--tertiary-text)" }} />
        </div>
        <div className="party-row-actions" data-busy={busy || undefined}>
          {isIncoming ? (
            <>
              {roomy ? (
                <PartyPillButton title={tr("Accept")} prominent height={20} busy={busy} help={tr("Accept %@'s friend request", profile.name)} onClick={() => store.acceptFriend(request)} />
              ) : (
                <IconButton symbol="check" size={20} help={tr("Accept %@'s friend request", profile.name)} className="party-accept" disabled={busy} onClick={() => store.acceptFriend(request)} />
              )}
              <IconButton symbol="close" size={20} help={tr("Decline %@'s request. They won't be told.", profile.name)} disabled={busy} onClick={() => store.removeFriend(profile.code)} />
            </>
          ) : (
            <IconButton symbol="close" size={20} help={tr("Cancel your request to %@", profile.name)} disabled={busy} onClick={() => store.removeFriend(profile.code)} />
          )}
        </div>
        {menu.element}
      </div>
    </Tooltip>
  );
}
