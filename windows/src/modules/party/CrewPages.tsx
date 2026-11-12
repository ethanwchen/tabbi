/*
 * Port of CrewPages: My crew (or, without one, the invite, the pending
 * request and the empty state) and another crew's page. Both share the hero
 * layout: a 168 px side column with the crest beside the members' pets, the
 * week's sentence and place, the medal tally and, on a crew page, the last
 * weeks; and the members, most hours first, with the owner's waiting
 * requests on top.
 */

import { useMemo } from "react";
import { useStore } from "../../app/useStore";
import { crewHours, crewMembersOf, crewOrdinal, crewWeekLabel } from "../../core/crews/crewFormat";
import { crewIsFull, crewPetOf, type CrewDetail, type CrewJoinRequest, type CrewMember, type CrewPet } from "../../core/crews/crewModels";
import { hasRequested, inCrew, type CrewSection } from "../../core/crews/crewsState";
import { tr } from "../../core/localization/tr";
import { useContextMenu, type ContextMenuItem } from "../../ui/kit/ContextMenu";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import {
  CrewButton,
  CrewIconButton,
  CrewMedalView,
  CrewPetGroup,
  CrewPetView,
  crewPlaceMetal,
  CrewRow,
  CrewRowList,
  CrewRowName,
  CrewStatus,
  CrewSummaryCrest,
  CrewTag,
  CrewTally,
  FirstThatFits,
  useCrewIsCompact,
  useFitStep,
} from "./CrewComponents";
import { CrewBackPill } from "./CrewsPanel";
import type { CrewsStore } from "./crewsStore";

/** My own pet as Crews shows it in the friendly states. */
export function useMyCrewPet(crews: CrewsStore): CrewPet {
  const pet = useStore(crews.party, (state) => state.pet);
  return useMemo(() => crewPetOf(pet), [pet]);
}

/* MARK: My crew */

export function CrewMineScreen({ crews }: { crews: CrewsStore }) {
  const store = useStore(crews);
  const myPet = useMyCrewPet(crews);
  const state = store.crews;
  const code = state.invite;
  if (code !== undefined) {
    return (
      <CrewStatus
        symbol="envelope.open.fill"
        title={tr("Join this crew?")}
        detail={inCrew(state) ? tr("You're already in a crew. Leave it first to join another.") : tr("Someone invited you to a study crew. Your focus minutes count for it from now on.")}
        actions={
          <>
            {!inCrew(state) && (
              <CrewButton
                title={tr("Join Crew")}
                style="prominent"
                height={24}
                busy={store.pending?.kind === "join"}
                help={tr("Join with invite code %@", code)}
                onClick={() => crews.joinInvite(code)}
              />
            )}
            <CrewButton title={tr("Not Now")} style="quiet" height={24} help={tr("Close without joining")} onClick={() => crews.dismissInvite()} />
          </>
        }
      />
    );
  }
  if (state.mine !== undefined) return <CrewHeroLayout crews={crews} crew={state.mine} mine />;
  const request = state.myRequest;
  if (request !== undefined) {
    return (
      <CrewStatus
        pet={{ pet: myPet, asleep: false }}
        title={tr("Waiting to join %@", request.crew.name)}
        detail={tr("Its owner lets you in. A request goes away after 7 days.")}
        actions={
          <>
            <CrewButton
              title={tr("Cancel request")}
              style="quiet"
              height={24}
              busy={store.pending?.kind === "cancelRequest"}
              help={tr("Withdraw your request to join %@", request.crew.name)}
              onClick={() => crews.cancelRequest()}
            />
            <CrewButton title={tr("Find crews")} height={24} help={tr("Browse public crews to join")} onClick={() => crews.show("find")} />
          </>
        }
      />
    );
  }
  if (state.mineLoaded) {
    return (
      <CrewStatus
        pet={{ pet: myPet, asleep: false }}
        title={tr("You're not in a crew yet")}
        detail={tr("Study with friends and climb the board together.")}
        actions={
          <>
            <CrewButton title={tr("Create a crew")} style="prominent" height={24} help={tr("Make a crew and invite friends")} onClick={() => crews.openEditor(false)} />
            <CrewButton title={tr("Find crews")} height={24} help={tr("Browse public crews to join")} onClick={() => crews.show("find")} />
          </>
        }
      />
    );
  }
  return <CrewStatus symbol="shield" title={tr("Loading your crew…")} />;
}

/* MARK: A crew page */

export function CrewPageScreen({ crews, crew, from }: { crews: CrewsStore; crew: CrewDetail; from: CrewSection }) {
  const store = useStore(crews);
  const state = store.crews;
  const summary = crew.summary;
  let trailing;
  if (crew.mine) trailing = <CrewTag title={tr("Your crew")} accent />;
  else if (summary.visibility === "private") trailing = <CrewTag title={tr("Private")} symbol="lock.fill" help={tr("Private, invite only")} />;
  else if (hasRequested(state, summary.id)) trailing = <CrewTag title={tr("Requested")} symbol="checkmark" help={tr("Its owner lets you in.")} />;
  else if (!inCrew(state) && !crewIsFull(summary))
    trailing = <CrewButton title={tr("Join")} busy={store.pending?.kind === "join"} help={tr("Ask to join %@. Its owner lets you in.", summary.name)} onClick={() => crews.requestToJoin(summary)} />;
  return (
    <>
      <div className="crews-head">
        <CrewBackPill crews={crews} from={from} />
        <MarqueeText text={summary.name} help={summary.description === "" ? summary.name : summary.description} userText className="kit-title crews-head-title" />
        <span className="crews-head-trail">
          {trailing}
          {!crew.mine && <CrewIconButton symbol="flag" help={tr("Report this crew")} onClick={() => crews.beginReport({ crew: summary, member: undefined })} />}
        </span>
      </div>
      <div className="crews-body">
        <CrewHeroLayout crews={crews} crew={crew} mine={crew.mine} />
      </div>
    </>
  );
}

/* MARK: The hero layout */

function CrewHeroLayout({ crews, crew, mine }: { crews: CrewsStore; crew: CrewDetail; mine: boolean }) {
  const compact = useCrewIsCompact();
  const pushed = useStore(crews, (store) => store.crews.pushed);
  const onMyCrew = mine && pushed === undefined;
  const summary = crew.summary;
  const minutes = summary.weekMinutes;
  const hours = crewHours(minutes);
  const privacy = summary.visibility === "public" ? tr("Public") : tr("Private, invite only");
  const place = minutes > 0 && crew.rank !== undefined && crew.crewCount > 0 ? tr("%@ of %lld crews · %@", crewOrdinal(crew.rank), crew.crewCount, privacy) : privacy;
  const noMedals = crew.medals.gold === 0 && crew.medals.silver === 0 && crew.medals.bronze === 0;
  const pets = crew.members.flatMap((member) => (member.pet === undefined ? [] : [member.pet])).slice(0, 4);
  const historyRows = onMyCrew ? 0 : Math.min(crew.history.length, compact ? 2 : 3);
  /*
   * Nothing in the column is cut: when it runs out of room, "No medals yet"
   * goes first, then my crew's sentence takes its short form, then the
   * history shows one week fewer at a time.
   */
  const [side, step] = useFitStep<HTMLDivElement>(2 + historyRows, `${summary.id}|${compact}|${onMyCrew}|${minutes}`);
  const showsNoMedals = noMedals && !compact && step < 1;
  const sentence = minutes <= 0 ? tr("No hours yet this week") : mine && step < 2 ? tr("Your crew studied %@ this week", hours) : tr("%@ this week", hours);
  const shownHistory = Math.max(0, historyRows - Math.max(0, step - 2));
  return (
    <div className="crew-hero-layout">
      <div ref={side} className="crew-hero">
        <div className="crew-hero-top">
          <CrewSummaryCrest crew={summary} hero />
          <span className="crew-hero-pets">
            <CrewPetGroup pets={pets} overlap={9} />
          </span>
        </div>
        {onMyCrew && <div className="crew-hero-name kit-title kit-user-text">{summary.name}</div>}
        <div className="crew-hero-words">
          <div className="kit-body-emphasis crew-hero-sentence">{sentence}</div>
          <div className="kit-caption kit-tertiary">{place}</div>
        </div>
        <CrewTally medals={crew.medals} />
        {showsNoMedals && <div className="kit-caption kit-tertiary">{tr("No medals yet")}</div>}
        {shownHistory > 0 && <CrewHistory crew={crew} rows={shownHistory} />}
      </div>
      <CrewMembersColumn crews={crews} crew={crew} />
    </div>
  );
}

/** The last finished weeks: week, medal if any, place, hours. */
function CrewHistory({ crew, rows }: { crew: CrewDetail; rows: number }) {
  return (
    <Tooltip text={tr("Last weeks")}>
      <div className="crew-history kit-caption" role="list" aria-label={tr("Last weeks")}>
        {crew.history.slice(0, rows).map((week) => (
          <div key={week.week.id} className="crew-history-row crew-number" role="listitem">
            <span className="crew-history-week kit-tertiary">{crewWeekLabel(week.week)}</span>
            {week.medal !== undefined ? <CrewMedalView metal={week.medal} /> : <span className="crew-history-blank" />}
            <span className="crew-history-place" data-metal={week.place === undefined ? "none" : crewPlaceMetal(week.place)}>
              {week.place === undefined ? "-" : crewOrdinal(week.place)}
            </span>
            <span className="kit-tertiary">{crewHours(week.minutes)}</span>
          </div>
        ))}
      </div>
    </Tooltip>
  );
}

/* MARK: Members */

type MemberItem = { readonly kind: "request"; readonly request: CrewJoinRequest } | { readonly kind: "member"; readonly member: CrewMember };

/** The members, most hours first, with their pets and Study Level; for the owner, the people asking to join sit on top with approve and decline. */
function CrewMembersColumn({ crews, crew }: { crews: CrewsStore; crew: CrewDetail }) {
  const items: MemberItem[] = [
    ...(crew.owner
      ? crew.requests.map((request): MemberItem => ({
          kind: "request",
          request,
        }))
      : []),
    ...[...crew.members].sort((a, b) => b.weekMinutes - a.weekMinutes).map((member): MemberItem => ({ kind: "member", member })),
  ];
  const waiting = crew.owner ? crew.requests.length : 0;
  const head = (showsWaiting: boolean, showsWeek: boolean) => (
    <div className="crew-members-head kit-caption kit-tertiary">
      <span>{crewMembersOf(crew.summary.memberCount, crew.summary.maxMembers)}</span>
      {showsWaiting && waiting > 0 && <span className="crew-members-waiting">{tr("· %lld want to join", waiting)}</span>}
      <span className="crews-head-spacer" />
      {showsWeek && <span>{tr("this week")}</span>}
    </div>
  );
  return (
    <div className="crew-members">
      {/* One caption line: when it runs out of room "this week" goes first, then the waiting count (the tab's dot and the rows still show it). */}
      <FirstThatFits className="crew-members-head-fits" candidates={[head(true, true), head(true, false), head(false, false)]} />
      <CrewRowList
        count={items.length}
        row={(index) => {
          const item = items[index] as MemberItem;
          return item.kind === "request" ? <CrewRequestRow crews={crews} request={item.request} /> : <CrewMemberRow crews={crews} crew={crew} member={item.member} />;
        }}
      />
    </div>
  );
}

function CrewMemberRow({ crews, crew, member }: { crews: CrewsStore; crew: CrewDetail; member: CrewMember }) {
  const you = tr("You");
  const menu = useContextMenu((): ContextMenuItem[] => {
    if (member.me) {
      return [
        {
          title: member.pet === undefined ? tr("Show My Pet on Crew Pages") : tr("Hide My Pet on Crew Pages"),
          onSelect: () => crews.setShowsPet(member.pet === undefined),
        },
      ];
    }
    const items: ContextMenuItem[] = [];
    if (crew.owner && crew.mine)
      items.push({
        title: tr("Remove %@ from Crew", member.name),
        destructive: true,
        onSelect: () => crews.remove(member),
      });
    items.push({
      title: tr("Report %@…", member.name),
      separator: items.length > 0,
      onSelect: () => crews.beginReport({ crew: crew.summary, member }),
    });
    items.push({
      title: tr("Block %@", member.name),
      destructive: true,
      onSelect: () => crews.block(member, crew),
    });
    return items;
  }, member.name);
  const hours = crewHours(member.weekMinutes);
  return (
    <CrewRow mine={member.me} label={tr("%@ with %@, %@ this week", member.pet?.petName ?? member.name, member.me ? you : member.name, hours)} onContextMenu={menu.open}>
      <span className="crew-member-pet">
        <CrewPetView pet={member.pet} name={member.name} />
      </span>
      <CrewRowName name={member.pet?.petName ?? member.name} caption={member.me ? you : member.pet === undefined ? undefined : member.name} captionAccent={member.me} />
      {member.studyLevel !== undefined && (
        <Tooltip text={tr("Study Level %lld", member.studyLevel)}>
          <span className="crew-member-level kit-caption kit-secondary crew-number">{tr("Lv %lld", member.studyLevel)}</span>
        </Tooltip>
      )}
      <span className="crew-value crew-member-hours crew-number">{hours}</span>
      {menu.element}
    </CrewRow>
  );
}

/** Someone asking to join my crew: their pet and name, with approve and decline. */
function CrewRequestRow({ crews, request }: { crews: CrewsStore; request: CrewJoinRequest }) {
  const pending = useStore(crews, (store) => store.pending);
  return (
    <div className="crew-row crew-request-row">
      <span className="crew-member-pet">
        <CrewPetView pet={request.pet} name={request.name} />
      </span>
      <CrewRowName name={request.name} caption={tr("Wants to join")} captionAccent />
      <CrewIconButton
        symbol="checkmark"
        filled
        busy={pending?.kind === "approve" && pending.id === request.ref}
        help={tr("Let %@ into the crew", request.name)}
        onClick={() => crews.approve(request)}
      />
      <CrewIconButton symbol="xmark" busy={pending?.kind === "decline" && pending.id === request.ref} help={tr("Decline. %@ isn't told.", request.name)} onClick={() => crews.decline(request)} />
    </div>
  );
}
