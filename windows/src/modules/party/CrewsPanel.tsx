/*
 * Port of CrewsPanel: the Party tab's Crews mode (the Crews UI spec): one
 * card with a pill row (the Party glyph, then My crew, This week, Hall of
 * Fame and Find) and the screen under it, or a pushed crew page or crest
 * editor with a back pill. Compact folds the featured tiles into the lists.
 */

import { useEffect, useRef } from "react";
import { useStore } from "../../app/useStore";
import { crewCountdown, crewWeekEnd } from "../../core/crews/crewFormat";
import { CREW_SECTIONS, inCrew, type CrewSection } from "../../core/crews/crewsState";
import { tr } from "../../core/localization/tr";
import { Card } from "../../ui/kit/Card";
import { useKit } from "../../ui/kit/context";
import { Icon } from "../../ui/kit/Icon";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useElementWidth } from "../../ui/kit/useElementWidth";
import { CrewHallScreen, CrewWeekScreen } from "./CrewBoards";
import { CREW_COMPACT_WIDTH, CrewButton, CrewCompactContext, CrewIconButton, CrewInviteButton, CrewPill, CrewStatus, FirstThatFits } from "./CrewComponents";
import { CrewEditorScreen, CrewFindScreen } from "./CrewEditorAndFind";
import { CrewMineScreen, CrewPageScreen } from "./CrewPages";
import type { CrewsStore } from "./crewsStore";
import "./crews.css";

export function CrewsPanel({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (store) => store.crews);
  const { reduceMotion, still } = useKit();
  const [card, width] = useElementWidth<HTMLDivElement>();
  /* The card's inner width (less its 8 px padding on each side) picks the Compact form. */
  const compact = width > 0 && width - 16 < CREW_COMPACT_WIDTH;
  const pushed = state.pushed;
  const screenID = pushed === undefined ? state.section : pushed.kind === "crew" ? `crew-${pushed.crew.summary.id}` : pushed.editing ? "edit" : "create";
  return (
    <CrewCompactContext.Provider value={compact}>
      <div ref={card} className="crews-frame">
        <Card padding={8} className="crews-card" data-compact={compact || undefined} data-motion={still ? "none" : reduceMotion ? "reduced" : undefined}>
          <div key={screenID} className="crews-screen">
            {pushed?.kind === "crew" ? (
              <CrewPageScreen crews={crews} crew={pushed.crew} from={pushed.from} />
            ) : pushed?.kind === "editor" ? (
              <CrewEditorScreen crews={crews} editing={pushed.editing} from={pushed.from} />
            ) : (
              <>
                <CrewPillRow crews={crews} />
                <div className="crews-body">
                  <CrewSectionBody crews={crews} />
                </div>
              </>
            )}
          </div>
          <CrewMoreMenu crews={crews} />
        </Card>
      </div>
    </CrewCompactContext.Provider>
  );
}

function CrewSectionBody({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (store) => store.crews);
  const hasContent =
    state.section === "mine" ? state.mineLoaded : state.section === "week" ? state.board !== undefined : state.section === "hall" ? state.hall !== undefined : state.results !== undefined;
  if (state.loadError !== undefined && state.loadError.isTransient && !hasContent) {
    return (
      <CrewStatus
        symbol="wifi.slash"
        title={tr("Can't reach the party server")}
        detail={tr("Check your internet connection. Crews show up once it's back.")}
        actions={<CrewButton title={tr("Try again")} height={24} help={tr("Connect to the party server now")} onClick={() => crews.retry()} />}
      />
    );
  }
  switch (state.section) {
    case "mine":
      return <CrewMineScreen crews={crews} />;
    case "week":
      return <CrewWeekScreen crews={crews} />;
    case "hall":
      return <CrewHallScreen crews={crews} />;
    case "find":
      return <CrewFindScreen crews={crews} />;
  }
}

/* MARK: The pill row */

export function crewSectionTitle(section: CrewSection): string {
  switch (section) {
    case "mine":
      return tr("My crew");
    case "week":
      return tr("This week");
    case "hall":
      return tr("Hall of Fame");
    case "find":
      return tr("Find");
  }
}

function sectionSymbol(section: CrewSection): string {
  switch (section) {
    case "mine":
      return "shield";
    case "week":
      return "calendar";
    case "hall":
      return "medal";
    case "find":
      return "magnifyingglass";
  }
}

function sectionHelp(section: CrewSection): string {
  switch (section) {
    case "mine":
      return tr("Your crew and its members");
    case "week":
      return tr("This week's leaderboard");
    case "hall":
      return tr("Medals from every week's top 3");
    case "find":
      return tr("Find crews");
  }
}

/**
 * The section pills and the open section's trailing items. Titles show on
 * every pill while the row fits, then only on the open pill, then on none
 * (the Closet's rule); the trailing caption gives way last.
 */
function CrewPillRow({ crews }: { crews: CrewsStore }) {
  const store = useStore(crews);
  const row = (titles: "all" | "open" | "none", trailing: boolean) => (
    <div className="crews-head">
      <div className="crew-pills" role="tablist">
        <CrewPill title={tr("Party")} symbol="person.3.fill" showsTitle={false} help={tr("Back to your party and friends")} onClick={() => crews.setShowsCrews(false)} />
        <span className="crew-pill-separator" />
        {CREW_SECTIONS.map((section) => {
          const open = store.crews.section === section;
          return (
            <CrewPill
              key={section}
              title={crewSectionTitle(section)}
              symbol={sectionSymbol(section)}
              showsTitle={titles === "all" || (titles === "open" && open)}
              selected={open}
              help={sectionHelp(section)}
              dot={section === "mine" && store.waitingRequests > 0 && !open}
              onClick={() => crews.show(section)}
            />
          );
        })}
      </div>
      <span className="crews-head-spacer" />
      {trailing && <CrewPillRowTrailing crews={crews} />}
    </div>
  );
  return <FirstThatFits className="crews-head-fits" candidates={[row("all", true), row("open", true), row("none", true), row("none", false)]} />;
}

/** What the open section shows at the end of the pill row. */
function CrewPillRowTrailing({ crews }: { crews: CrewsStore }) {
  const store = useStore(crews);
  const state = store.crews;
  switch (state.section) {
    case "week":
      return (
        <Tooltip text={tr("The week runs Monday to Sunday (UTC). Ends %@. The top 3 wear a laurel next week.", crewWeekEnd(state.week))}>
          <span className="kit-caption kit-tertiary crew-number crews-head-caption">{crewCountdown(state.week, store.now)}</span>
        </Tooltip>
      );
    case "hall":
      return (
        <Tooltip text={tr("Ranked by golds, then silvers, then bronzes, then whoever reached the tally first.")}>
          <span className="kit-caption kit-tertiary crews-head-caption">{tr("Every Sunday's top 3 earn a medal")}</span>
        </Tooltip>
      );
    case "find":
      return (
        <CrewButton
          title={tr("Create a crew")}
          symbol="plus"
          enabled={!inCrew(state)}
          help={inCrew(state) ? tr("Leave your crew to start a new one") : tr("Make a crew and invite friends")}
          onClick={() => crews.openEditor(false)}
        />
      );
    case "mine": {
      const mine = state.mine;
      if (mine === undefined) return null;
      return (
        <span className="crews-head-trail">
          {mine.inviteCode !== undefined && <CrewInviteButton code={mine.inviteCode} />}
          <CrewIconButton symbol="ellipsis" help={tr("More")} expanded={store.showsMoreMenu} onClick={() => crews.setShowsMoreMenu(!store.showsMoreMenu)} />
        </span>
      );
    }
  }
}

/** My crew's small in-panel menu, under its More button; a click outside or Esc closes it. */
function CrewMoreMenu({ crews }: { crews: CrewsStore }) {
  const store = useStore(crews);
  const menu = useRef<HTMLDivElement>(null);
  const state = store.crews;
  const mine = state.mine;
  const shows = store.showsMoreMenu && state.pushed === undefined && state.section === "mine" && mine !== undefined;
  useEffect(() => {
    if (!shows) return;
    const close = (event: PointerEvent) => {
      const target = event.target as Element | null;
      if (menu.current?.contains(target) || target?.closest(".crew-icon-button[aria-haspopup]")) return;
      crews.setShowsMoreMenu(false);
    };
    const escape = (event: globalThis.KeyboardEvent) => {
      if (event.key === "Escape") crews.setShowsMoreMenu(false);
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", escape);
    };
  }, [shows, crews]);
  if (!shows) return null;
  const me = mine.members.find((member) => member.me);
  return (
    <div ref={menu} className="crew-menu" role="menu">
      {mine.owner && <CrewMenuItem title={tr("Edit crew")} symbol="pencil" onClick={() => crews.openEditor(true)} />}
      {me !== undefined && (
        <CrewMenuItem
          title={me.pet === undefined ? tr("Show My Pet on Crew Pages") : tr("Hide My Pet on Crew Pages")}
          symbol={me.pet === undefined ? "eye" : "eye.slash"}
          onClick={() => crews.setShowsPet(me.pet === undefined)}
        />
      )}
      <CrewMenuItem title={tr("Leave crew")} symbol="xmark" danger onClick={() => crews.leave()} />
    </div>
  );
}

function CrewMenuItem({ title, symbol, danger = false, onClick }: { title: string; symbol: string; danger?: boolean; onClick: () => void }) {
  return (
    <button type="button" role="menuitem" className="crew-menu-item kit-body" data-danger={danger || undefined} onClick={onClick}>
      <Icon id={symbol} size={10} />
      <span>{title}</span>
    </button>
  );
}

/** The back pill of a pushed screen, naming the section it returns to. */
export function CrewBackPill({ crews, from }: { crews: CrewsStore; from: CrewSection }) {
  const title = from === "find" ? tr("Find crews") : crewSectionTitle(from);
  return (
    <Tooltip text={tr("Back")}>
      <button type="button" className="crew-back-pill kit-caption" aria-label={`${tr("Back")}: ${title}`} onClick={() => crews.pop()}>
        <Icon id="chevron.backward" size={8} />
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}
