/*
 * Port of CrewsPanel: the Party tab's Crew section: the main card on the
 * left (my crew, a crew page, Find, the New crew form, or an invite to
 * confirm) and the weekly top 3 on the right, where the friends column is
 * on the Party side, so switching keeps the panel's shape. The form swaps
 * the top 3 for a live preview with Create.
 */

import { useCallback, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { CREW_LIMITS, crewIcons } from "../../core/crews/crewCatalog";
import { CREW_ICON_COMPACT_PIXEL_SIZE } from "../../core/crews/crewIconArt";
import { crewHours, crewMembers, crewRank } from "../../core/crews/crewFormat";
import { CrewCode, crewIsFull, crewMe, type CrewDetail, type CrewMember, type CrewSummary } from "../../core/crews/crewModels";
import { crewErrorMessage, inCrew } from "../../core/crews/crewsState";
import { tr } from "../../core/localization/tr";
import { Card } from "../../ui/kit/Card";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { Icon } from "../../ui/kit/Icon";
import { TextThatFits } from "../../ui/kit/TextThatFits";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useContextMenu, type ContextMenuItem } from "../../ui/kit/ContextMenu";
import { CrewBoardCard, CrewFormView, CrewPreviewCard } from "./CrewBoardCard";
import { CrewIconButton, CrewIconView, CrewInviteButton, CrewMemberPet, CrewSummaryIcon, CrewTextField, FirstThatFits, PartySectionSwitch, rankColor } from "./CrewComponents";
import { FRIENDS_WIDTH } from "./PartyFriendsCard";
import { PartyCodeField, PartyPillButton, PartyTextButton } from "./PartyComponents";
import type { CrewsStore } from "./crewsStore";
import "./crews.css";

export function CrewsPanel({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (s) => s.crews);
  const isForm = state.viewing === undefined && state.invite === undefined && (state.section === "create" || state.editing);
  let main: ReactNode;
  if (state.invite !== undefined) main = <CrewInviteView crews={crews} code={state.invite} />;
  else if (state.viewing !== undefined) main = <CrewPageView crews={crews} crew={state.viewing} />;
  else if (isForm) main = <CrewFormView crews={crews} />;
  else if (state.section === "find") main = <CrewFindView crews={crews} />;
  else if (state.mine !== undefined) main = <CrewPageView crews={crews} crew={state.mine} />;
  else if (state.mineLoaded) main = <CrewEmptyView crews={crews} />;
  else main = <CrewLoadingView crews={crews} />;
  return (
    <div className="party-columns crews-panel">
      <Card className="crew-main">{main}</Card>
      <div style={{ width: FRIENDS_WIDTH, flex: "none", display: "flex" }}>{isForm ? <CrewPreviewCard crews={crews} /> : <CrewBoardCard crews={crews} />}</div>
    </div>
  );
}

/**
 * The header row every main view starts with: the Party or Crew switch,
 * then the view's own title and actions. Without `switchTitles` the switch
 * spells out its words while the whole row fits, and shows its icons
 * otherwise.
 */
export function CrewHeader({ crews, back, switchTitles, children }: { crews: CrewsStore; back?: () => void; switchTitles?: boolean; children?: ReactNode }) {
  const row = (titles: boolean) => (
    <div className="crew-header">
      <PartySectionSwitch crews={crews} showsTitles={titles} />
      {back !== undefined && <CrewIconButton symbol="chevron.backward" help={tr("Back")} onClick={back} />}
      <span className="party-spacer" />
      {children}
    </div>
  );
  if (switchTitles !== undefined) return row(switchTitles);
  return <FirstThatFits candidates={[row(true), row(false)]} />;
}

/* MARK: A crew page */

/** My crew, or another crew opened from the top 3 or Find: its icon with this week's laurel, name, trophies, hours and rank, and the members' pets. */
function CrewPageView({ crews, crew }: { crews: CrewsStore; crew: CrewDetail }) {
  const isVisitor = !crew.mine;
  const header = (switchTitles: boolean, inviteTitle: boolean) => (
    <CrewHeader crews={crews} switchTitles={switchTitles} {...(isVisitor ? { back: () => crews.closeCrewPage() } : {})}>
      <CrewPageActions crews={crews} crew={crew} inviteTitle={inviteTitle} />
    </CrewHeader>
  );
  return (
    <div className="crew-page">
      {/* The switch keeps its words longest; Invite shortens to its icon first. */}
      <FirstThatFits candidates={[header(true, true), header(true, false), header(false, false)]} />
      <CrewIdentity crew={crew} />
      <CrewMembersStrip crews={crews} crew={crew} />
    </div>
  );
}

function CrewPageActions({ crews, crew, inviteTitle }: { crews: CrewsStore; crew: CrewDetail; inviteTitle: boolean }) {
  const state = useStore(crews);
  const menuItems = useCallback((): ContextMenuItem[] => {
    const items: ContextMenuItem[] = [];
    if (crew.owner) items.push({ title: tr("Edit Crew…"), symbol: "pencil", onSelect: () => crews.beginEdit() });
    const me = crewMe(crew);
    if (me !== undefined) {
      items.push(
        me.pet === undefined
          ? { title: tr("Show My Pet on Crew Pages"), symbol: "eye", onSelect: () => crews.setShowsPet(true) }
          : { title: tr("Hide My Pet on Crew Pages"), symbol: "eye.slash.fill", onSelect: () => crews.setShowsPet(false) },
      );
    }
    items.push({ title: tr("Leave Crew"), destructive: true, separator: true, onSelect: () => crews.leave() });
    return items;
  }, [crews, crew]);
  const menu = useContextMenu(menuItems, tr("More crew options"));
  if (crew.mine) {
    return (
      <>
        {crew.inviteCode !== undefined && CrewCode.invite(crew.inviteCode) !== undefined && <CrewInviteButton code={crew.inviteCode} showsTitle={inviteTitle} />}
        <CrewIconButton symbol="magnifyingglass" help={tr("Find crews")} onClick={() => crews.show("find")} />
        <span className="crew-more" onClick={menu.open} onContextMenu={menu.open}>
          <CrewIconButton symbol="ellipsis" help={tr("More crew options")} onClick={() => undefined} />
          {menu.element}
        </span>
      </>
    );
  }
  return (
    <>
      {crew.summary.visibility === "public" && !inCrew(state.crews) && !crewIsFull(crew.summary) && (
        <PartyPillButton
          title={tr("Join")}
          prominent
          height={20}
          busy={crews.isPending("join")}
          help={tr("Join %@. Your focus minutes count for it from now on.", crew.summary.name)}
          onClick={() => crews.joinCrew(crew.summary.id)}
        />
      )}
      <CrewIconButton symbol="flag" help={tr("Report this crew")} onClick={() => crews.beginReport({ crew: crew.summary, member: undefined })} />
    </>
  );
}

function CrewIdentity({ crew }: { crew: CrewDetail }) {
  const summary = crew.summary;
  const rankText = crew.rank === undefined ? tr("this week") : tr("%@ this week", crewRank(crew.rank));
  return (
    <div className="crew-identity">
      <CrewSummaryIcon crew={summary} />
      <div className="crew-identity-words">
        <Tooltip text={summary.description === "" ? summary.name : summary.description}>
          <span className="kit-title crew-name kit-user-text">{summary.name}</span>
        </Tooltip>
        <Tooltip text={tr("Focus hours this week. The board freezes Sunday 23:59 UTC.")}>
          <span className="crew-hours-line">
            <span className="kit-body-emphasis crew-number">{crewHours(summary.weekMinutes)}</span>
            <span className="kit-caption kit-secondary crew-number">{rankText}</span>
          </span>
        </Tooltip>
        <FirstThatFits candidates={[<CrewMeta key="words" crew={crew} words />, <CrewMeta key="icons" crew={crew} words={false} />]} />
      </div>
    </div>
  );
}

/** Visibility, members and trophies; `words` spells them out, otherwise icons and numbers carry them (the tooltips say the rest). */
function CrewMeta({ crew, words }: { crew: CrewDetail; words: boolean }) {
  const summary = crew.summary;
  const isPublic = summary.visibility === "public";
  return (
    <span className="crew-meta kit-caption kit-secondary">
      <Tooltip text={isPublic ? tr("Public: anyone can find and join it.") : tr("Private: only people with the invite can join.")}>
        <span className="crew-meta-item">
          <Icon id={isPublic ? "globe" : "lock.fill"} size={9} />
          {words && <span>{isPublic ? tr("Public") : tr("Private")}</span>}
        </span>
      </Tooltip>
      <Tooltip text={tr("Members")}>
        <span className="crew-meta-item crew-number">
          <Icon id="person.2.fill" size={9} />
          <span>{words ? crewMembers(summary.memberCount, summary.maxMembers) : `${summary.memberCount}/${summary.maxMembers}`}</span>
        </span>
      </Tooltip>
      {summary.trophies > 0 && (
        <Tooltip text={tr("Top 3 finishes: %lld gold, %lld silver, %lld bronze", crew.medals.gold, crew.medals.silver, crew.medals.bronze)}>
          <span className="crew-meta-item crew-number">
            <Icon id="trophy.fill" size={9} style={{ color: rankColor(1) }} />
            <span>{summary.trophies}</span>
          </span>
        </Tooltip>
      )}
      {crew.hidden && (
        <Tooltip text={tr("The Tabbi team hid this crew from the board and Find.")}>
          <span className="crew-meta-item">
            <Icon id="eye.slash.fill" size={9} />
            {words && <span>{tr("Hidden")}</span>}
          </span>
        </Tooltip>
      )}
    </span>
  );
}

/** The members' pets side by side, owner first, with name and hours; it scrolls sideways once they no longer fit. */
function CrewMembersStrip({ crews, crew }: { crews: CrewsStore; crew: CrewDetail }) {
  return (
    <EdgeFade edge="end" length={12} className="crew-members">
      <div className="crew-members-row">
        {crew.members.map((member) => (
          <CrewMemberColumn key={member.ref} crews={crews} crew={crew} member={member} />
        ))}
      </div>
    </EdgeFade>
  );
}

function CrewMemberColumn({ crews, crew, member }: { crews: CrewsStore; crew: CrewDetail; member: CrewMember }) {
  const items = useCallback((): ContextMenuItem[] => {
    if (member.me) {
      return [
        member.pet === undefined
          ? { title: tr("Show My Pet on Crew Pages"), symbol: "eye", onSelect: () => crews.setShowsPet(true) }
          : { title: tr("Hide My Pet on Crew Pages"), symbol: "eye.slash.fill", onSelect: () => crews.setShowsPet(false) },
      ];
    }
    const list: ContextMenuItem[] = [];
    if (crew.owner && crew.mine) list.push({ title: tr("Remove %@ from Crew", member.name), symbol: "minus.circle.fill", onSelect: () => crews.remove(member) });
    list.push(
      { title: tr("Report %@…", member.name), symbol: "exclamationmark.triangle", separator: list.length > 0, onSelect: () => crews.beginReport({ crew: crew.summary, member }) },
      { title: tr("Block %@", member.name), symbol: "hand.raised.fill", destructive: true, onSelect: () => crews.block(member, crew) },
    );
    return list;
  }, [crews, crew, member]);
  const menu = useContextMenu(items, member.name);
  return (
    <div className="crew-member" onContextMenu={menu.open}>
      <div className="crew-member-pet">
        <CrewMemberPet member={member} />
      </div>
      <Tooltip text={member.name}>
        <span className="crew-member-name kit-caption">
          {member.owner && (
            <Tooltip text={tr("Crew owner")}>
              <Icon id="crown.fill" size={8} className="party-crown" />
            </Tooltip>
          )}
          <span className={member.me ? "crew-truncate" : "crew-truncate kit-user-text"}>{member.me ? tr("You") : member.name}</span>
        </span>
      </Tooltip>
      <span className="crew-member-hours kit-caption kit-secondary">
        <span className="crew-number">{crewHours(member.weekMinutes)}</span>
        {member.studyLevel !== undefined && (
          <Tooltip text={tr("Study Level %lld", member.studyLevel)}>
            <span className="kit-tertiary crew-number">{tr("Lv %lld", member.studyLevel)}</span>
          </Tooltip>
        )}
      </span>
      {menu.element}
    </div>
  );
}

/* MARK: No crew yet */

function CrewEmptyView({ crews }: { crews: CrewsStore }) {
  const intro = (showsIcon: boolean, showsLine: boolean) => (
    <div className="crew-intro">
      {showsIcon && <CrewIconView icon={crewIcons()[0] ?? ""} color="coral" laurel="gold" />}
      <div className="crew-intro-words">
        <span className="kit-title">{tr("Join a study crew")}</span>
        {showsLine && <span className="kit-body kit-secondary">{tr("Study with a crew and climb the weekly top 3.")}</span>}
      </div>
    </div>
  );
  const buttons = (titles: boolean) => (
    <div className="crew-row">
      <PartyPillButton title={titles ? tr("New crew") : ""} symbol="plus" prominent help={tr("Make a crew and invite friends")} onClick={() => crews.show("create")} />
      <PartyPillButton title={titles ? tr("Find crews") : ""} symbol="magnifyingglass" help={tr("Browse public crews to join")} onClick={() => crews.show("find")} />
    </div>
  );
  return (
    <div className="crew-empty">
      <CrewHeader crews={crews} />
      {/* The intro gives way first on a short panel: the icon, then the line under the title, so the ways in always show whole. */}
      <FirstThatFits axis="vertical" className="crew-intro-fits" candidates={[intro(true, true), intro(false, true), intro(false, false)]} />
      <FirstThatFits candidates={[buttons(true), buttons(false)]} />
      <PartyCodeField
        placeholder={tr("Invite code")}
        symbol="link"
        length={CrewCode.inviteLength}
        help={tr("Have an invite? Type the %lld-character code and press Return to join", CrewCode.inviteLength)}
        onSubmit={(text) => crews.joinInvite(text)}
      />
    </div>
  );
}

/** Before the first answer about my crew. */
function CrewLoadingView({ crews }: { crews: CrewsStore }) {
  const error = useStore(crews, (state) => state.crews.loadError);
  return (
    <div className="crew-empty">
      <CrewHeader crews={crews} />
      <div className="crew-loading kit-body kit-secondary">{error === undefined ? tr("Loading your crew…") : crewErrorMessage(error)}</div>
    </div>
  );
}

/* MARK: An invite link */

function CrewInviteView({ crews, code }: { crews: CrewsStore; code: string }) {
  const state = useStore(crews);
  const member = inCrew(state.crews);
  return (
    <div className="crew-empty">
      <CrewHeader crews={crews} />
      <div className="crew-intro-words">
        <span className="kit-title">{tr("Join this crew?")}</span>
        <span className="kit-body kit-secondary">
          {member ? tr("You're already in a crew. Leave it first to join another.") : tr("Someone invited you to a study crew. Your focus minutes count for it from now on.")}
        </span>
      </div>
      <span className="party-spacer" />
      <div className="crew-row">
        {!member && (
          <PartyPillButton title={tr("Join Crew")} symbol="checkmark" prominent busy={crews.isPending("join")} help={tr("Join with invite code %@", code)} onClick={() => crews.joinInvite(code)} />
        )}
        <PartyTextButton title={tr("Not Now")} help={tr("Close without joining")} onClick={() => crews.dismissInvite()} />
      </div>
    </div>
  );
}

/* MARK: Find */

function CrewFindView({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (s) => s.crews);
  const results = state.results;
  let list: ReactNode;
  if (results === undefined) list = <div className="crew-loading" />;
  else if (results.length === 0)
    list = <div className="crew-loading kit-body kit-secondary">{state.query === "" ? tr("No public crews yet. Make the first one.") : tr("No public crews match.")}</div>;
  else
    list = (
      <EdgeFade edge="bottom" length={12} className="crew-find-list">
        {results.map((crew) => (
          <CrewFindRow key={crew.id} crews={crews} crew={crew} />
        ))}
      </EdgeFade>
    );
  return (
    <div className="crew-find">
      <CrewHeader crews={crews} back={() => crews.show("mine")}>
        <span className="kit-body-emphasis crew-nowrap">{tr("Find crews")}</span>
      </CrewHeader>
      <CrewTextField
        placeholder={tr("Search public crews")}
        value={state.query}
        limit={CREW_LIMITS.nameMaxLength}
        symbol="magnifyingglass"
        help={tr("Search public crews by name")}
        onChange={(query) => crews.search(query)}
      />
      {list}
    </div>
  );
}

function CrewFindRow({ crews, crew }: { crews: CrewsStore; crew: CrewSummary }) {
  const member = useStore(crews, (state) => inCrew(state.crews));
  return (
    <Tooltip text={tr("Open %@", crew.name)}>
      <div className="crew-find-row" role="button" tabIndex={0} onClick={() => crews.openCrew(crew.id)}>
        <CrewSummaryIcon crew={crew} pixelSize={CREW_ICON_COMPACT_PIXEL_SIZE} />
        <div className="crew-find-words">
          <Tooltip text={crew.description === "" ? crew.name : crew.description}>
            <span className="kit-body-emphasis crew-truncate kit-user-text">{crew.name}</span>
          </Tooltip>
          {/* A narrow row keeps the hours and drops the member count first, so nothing is cut. */}
          <TextThatFits
            className="kit-caption kit-secondary crew-number"
            candidates={[tr("%@ · %@ this week", crewMembers(crew.memberCount, crew.maxMembers), crewHours(crew.weekMinutes)), crewHours(crew.weekMinutes)]}
          />
        </div>
        {crewIsFull(crew) ? (
          <span className="kit-caption kit-tertiary crew-nowrap">{tr("Full")}</span>
        ) : (
          !member && (
            <span onClick={(event) => event.stopPropagation()}>
              <PartyPillButton
                title={tr("Join")}
                height={20}
                busy={crews.isPending("join")}
                help={tr("Join %@. Your focus minutes count for it from now on.", crew.name)}
                onClick={() => crews.joinCrew(crew.id)}
              />
            </span>
          )
        )}
      </div>
    </Tooltip>
  );
}
