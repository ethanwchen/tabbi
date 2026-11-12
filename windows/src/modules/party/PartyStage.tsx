/*
 * Port of PartyStage: the panel's primary area: the party's pets side by
 * side with the shared session below, or, outside a party, ways to start
 * or join one.
 */

import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { PartyCode, type Party, type PartyMember, type PartySession } from "../../core/party/partyModels";
import { minutesLeft, rosterDuration, rosterStatus, rosterTimeLeft, statusLine } from "../../core/party/partyRoster";
import { isFoundingMember } from "../../core/party/partyModels";
import { Card } from "../../ui/kit/Card";
import { FoundingBadge } from "../../ui/kit/FoundingBadge";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useElementWidth } from "../../ui/kit/useElementWidth";
import { textWidth } from "../../ui/shell/measure";
import { ViewsThatFit } from "../../ui/kit/ViewsThatFit";
import { PartyCodeField, PartyCopyCode, PartyPet, PartyPillButton, PartyShareInvite, PartyTextButton, statusColor } from "./PartyComponents";
import { useModerationMenu } from "./PartyModeration";
import type { PartyStore } from "./partyStore";

export function PartyStage({ store, onFieldFocus }: { store: PartyStore; onFieldFocus: (focused: boolean) => void }) {
  const party = useStore(store, (state) => state.party.party);
  return <Card className="party-stage">{party === undefined ? <PartyLobby store={store} onFieldFocus={onFieldFocus} /> : <PartyRoom party={party} store={store} />}</Card>;
}

/* MARK: In a party */

const ROOMY_WIDTH = 72;

/** The member status row's caption type, dot and gap (party.css), for measuring what fits. */
const CAPTION_SIZE = 10.5;
const CAPTION_WEIGHT = 500;
const STATUS_DOT = 5;
const STATUS_GAP = 4;

/** The room header's layouts, roomiest first (the Mac's PartyRoom.header). */
const HEADER_VARIANTS: readonly { title: boolean; count: "long" | "short" | "none" }[] = [
  { title: true, count: "long" },
  { title: false, count: "long" },
  { title: false, count: "short" },
  { title: false, count: "none" },
];
const LAST_HEADER_VARIANT = { title: false, count: "none" } as const;

/** The party I'm in: its code, everyone's pets, and the shared session. */
function PartyRoom({ party, store }: { party: Party; store: PartyStore }) {
  const state = useStore(store);
  const [members, width] = useElementWidth<HTMLDivElement>();
  const count = Math.max(party.members.length, 1);
  const column = width === 0 ? ROOMY_WIDTH : Math.min(ROOMY_WIDTH, Math.floor((width - 4 * (count - 1)) / count));
  const isHost = state.party.isHost;
  return (
    <div className="party-room">
      <div className="party-room-header">
        {/*
         * As on the Mac: on a narrow panel the title goes first (the code
         * says it's a party), then the count shortens, then goes, so no word
         * is squeezed, wrapped or covered by Leave in any language.
         */}
        <ViewsThatFit
          count={HEADER_VARIANTS.length}
          fitKey={`${party.code}|${party.members.length}|${party.maxMembers}`}
          className="party-room-labels"
          render={(index) => {
            const variant = HEADER_VARIANTS[index] ?? LAST_HEADER_VARIANT;
            const count =
              variant.count === "long"
                ? tr("%lld of %lld", party.members.length, party.maxMembers)
                : variant.count === "short"
                  ? `${party.members.length}/${party.maxMembers}`
                  : undefined;
            return (
              <>
                {variant.title && <span className="kit-title party-room-title">{tr("Party")}</span>}
                <PartyCopyCode code={party.code} help={tr("The party code. Click to copy it, then send it to friends.")} />
                <PartyShareInvite invite={{ kind: "joinParty", code: party.code }} help={tr("Share an invite link. Friends who open it can join this party in one click.")} />
                {count !== undefined && (
                  <Tooltip text={tr("Members in this party")}>
                    <span className="kit-caption kit-tertiary party-room-count">{count}</span>
                  </Tooltip>
                )}
              </>
            );
          }}
        />
        <PartyTextButton
          title={tr("Leave")}
          busy={store.isPending({ kind: "leaveParty" })}
          help={isHost && party.members.length > 1 ? tr("Leave the party; the next member becomes host") : tr("Leave the party")}
          onClick={() => store.leaveParty()}
        />
      </div>
      <div ref={members} className="party-members">
        {party.members.map((member) => (
          <PartyMemberView key={member.profile.code} member={member} isMe={member.profile.code === state.party.friendCode} width={column} store={store} now={state.now} />
        ))}
      </div>
      <PartySessionBar party={party} store={store} />
    </div>
  );
}

/** One member: their pet with name and status underneath. Narrow columns (a crowded party) get the smaller pet and only the countdown. */
function PartyMemberView({ member, isMe, width, store, now }: { member: PartyMember; isMe: boolean; width: number; store: PartyStore; now: number }) {
  const status = rosterStatus(member.presence, member.online);
  const roomy = width >= 60;
  const left = rosterTimeLeft(member.presence, member.online, now);
  const countdown = left === undefined ? undefined : tr("%lldm", Math.ceil(left / 60));
  const shortStatus = !roomy
    ? countdown
    : status === "studying"
      ? (left === undefined ? tr("Studying") : minutesLeft(left))
      : status === "onBreak"
        ? tr("Break")
        : status === "idle"
          ? tr("Online")
          : tr("Offline");
  // A status too long for the column in the user's language ("noch 19 Min.")
  // falls back to the short countdown ("19m"), as the Mac's ViewThatFits does.
  // In the narrowest columns of a full party, where even "19m" does not
  // fit, the colored dot alone says what they're doing.
  // The row draws tabular digits, each as wide as a zero, so they are measured as zeros.
  const fits = (text: string, dot: boolean) =>
    (dot ? STATUS_DOT + STATUS_GAP : 0) + textWidth(text.replace(/\d/g, "0"), CAPTION_SIZE, CAPTION_WEIGHT) <= width;
  const shownStatus =
    shortStatus === undefined || fits(shortStatus, roomy)
      ? shortStatus
      : countdown !== undefined && countdown !== shortStatus && fits(countdown, roomy)
        ? countdown
        : undefined;
  const name = isMe ? tr("You") : member.profile.name;
  const parts = [tr("%@ with %@", name, member.profile.petName)];
  if (isFoundingMember(member.profile)) parts.push(tr("Founding Member"));
  parts.push(statusLine(member.presence, member.online, now));
  if (member.presence !== undefined && member.presence.todayMinutes > 0) parts.push(tr("%@ today", rosterDuration(member.presence.todayMinutes)));
  const help = parts.join(" · ") + (isMe ? "" : ". " + tr("Right-click to report or block."));
  const menu = useModerationMenu(store, isMe ? undefined : member.profile);
  const crown = <Icon id="crown.fill" size={8} className="party-crown" />;
  return (
    <Tooltip text={help}>
      <div className="party-member" style={{ width }} onContextMenu={menu.open}>
        <div className="party-member-pet">
          <PartyPet profile={member.profile} asleep={status === "offline"} pixelSize={roomy ? 1.5 : 1} />
          {member.host && !roomy && <span className="party-member-crown-overlay">{crown}</span>}
        </div>
        <div className="party-member-name kit-caption">
          {member.host && roomy && crown}
          <MarqueeText text={name} userText={!isMe} />
          {isFoundingMember(member.profile) && roomy && <FoundingBadge isMe={isMe} />}
        </div>
        <div className="party-member-status kit-caption" style={{ color: roomy ? "var(--tertiary-text)" : statusColor(status) }}>
          {(roomy || shownStatus === undefined) && <span className="party-dot" style={{ background: statusColor(status) }} />}
          {shownStatus !== undefined && <span className="party-nowrap">{shownStatus}</span>}
        </div>
        {menu.element}
      </div>
    </Tooltip>
  );
}

/** Shared focus lengths the host can start with one click. */
const LENGTHS = [25, 50];

/** The shared session: its countdown, with End for the host; or, with none running, Start buttons for the host and a waiting line for everyone else. */
function PartySessionBar({ party, store }: { party: Party; store: PartyStore }) {
  const state = useStore(store);
  const [bar, width] = useElementWidth<HTMLDivElement>();
  const labeled = width === 0 || width >= 300;
  const session = party.session;
  const isHost = state.party.isHost;
  const hostName = party.members.find((member) => member.host)?.profile.name ?? tr("the host");
  let content;
  if (session !== undefined && session.phaseEndsAt > state.now) {
    content = <RunningSession session={session} store={store} labeled={labeled} />;
  } else if (isHost) {
    content = (
      <>
        {labeled && <span className="kit-body-emphasis kit-secondary party-nowrap">{session === undefined ? tr("Focus together") : tr("Focus again")}</span>}
        <span className="party-spacer" />
        {LENGTHS.map((minutes, index) => (
          <PartyPillButton
            key={minutes}
            title={tr("%lld min", minutes)}
            symbol={index === 0 ? "play.fill" : undefined}
            prominent={index === 0}
            busy={store.isPending({ kind: "session" })}
            help={tr("Start a %lld-minute focus session for everyone in the party", minutes)}
            onClick={() => store.startSession(minutes)}
          />
        ))}
      </>
    );
  } else {
    content = (
      <>
        <Icon id="hourglass" size={11} className="kit-tertiary" />
        <MarqueeText text={labeled ? tr("Waiting for %@ to start a session", hostName) : tr("Waiting for %@", hostName)} className="kit-body kit-secondary party-grow" />
      </>
    );
  }
  return (
    <div ref={bar} className="party-session-bar">
      {content}
    </div>
  );
}

/** "18:20" for a phase's remaining time. */
function clock(seconds: number): string {
  const whole = Math.ceil(seconds);
  return `${Math.trunc(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

function RunningSession({ session, store, labeled }: { session: PartySession; store: PartyStore; labeled: boolean }) {
  const state = useStore(store);
  const total = Math.max(session.phaseEndsAt - session.startedAt, 1);
  const left = Math.max(session.phaseEndsAt - state.now, 0);
  const isHost = state.party.isHost;
  return (
    <>
      <Icon id="timer" size={11} style={{ color: "var(--accent)" }} />
      <span className="kit-metric-small party-clock">{clock(left)}</span>
      {labeled && <span className="kit-caption kit-tertiary party-nowrap">{tr("shared focus")}</span>}
      <Tooltip text={tr("%@ in the party's shared session", minutesLeft(left))}>
        <div className="party-progress" dir="ltr">
          <div className="party-progress-fill" style={{ width: `${(1 - left / total) * 100}%` }} />
        </div>
      </Tooltip>
      {isHost ? (
        <PartyTextButton title={tr("End")} busy={store.isPending({ kind: "session" })} help={tr("End the shared session for everyone")} onClick={() => store.endSession()} />
      ) : state.party.hasLeftSession(state.now) ? (
        <PartyTextButton title={tr("Rejoin")} help={tr("Count this session for you again")} onClick={() => store.rejoinSession()} />
      ) : (
        <PartyTextButton title={tr("Step out")} help={tr("Step out of this session; it goes on for the others")} onClick={() => store.leaveSession()} />
      )}
    </>
  );
}

/* MARK: Not in a party */

/** Outside a party: my pet with an invitation to start one or join by code. */
function PartyLobby({ store, onFieldFocus }: { store: PartyStore; onFieldFocus: (focused: boolean) => void }) {
  const state = useStore(store);

  return (
    <div className="party-lobby">
      <div className="party-lobby-intro">
        {state.party.profile !== undefined && <PartyPet profile={state.party.profile} pixelSize={1.5} />}
        <div className="party-lobby-words">
          <span className="kit-title">{tr("Study together")}</span>
          <span className="kit-body kit-secondary party-lobby-line">{tr("Start a party and share its code, or join a friend's. Your pets sit side by side while you focus.")}</span>
        </div>
      </div>
      {/*
       * Start keeps its words while the row also holds the code field whole
       * (the field never gets narrower than its placeholder needs);
       * otherwise it shrinks to its plus, as on the Mac.
       */}
      <ViewsThatFit
        count={2}
        fitKey={tr("Start a party")}
        className="party-lobby-actions"
        render={(index) => {
          const shortStart = index > 0;
          return (
            <>
              <PartyPillButton
                title={shortStart ? "" : tr("Start a party")}
                symbol="plus"
                prominent
                busy={store.isPending({ kind: "createParty" })}
                help={tr("Create a party and get a code to share")}
                onClick={() => store.createParty()}
              />
              <PartyCodeField
                placeholder={tr("Party code")}
                symbol="number"
                length={PartyCode.partyCodeLength}
                help={tr("Have a code? Type the %lld-character party code and press Return to join", PartyCode.partyCodeLength)}
                onSubmit={(text) => store.joinParty(text)}
                onFocusChange={onFieldFocus}
              />
            </>
          );
        }}
      />
    </div>
  );
}
