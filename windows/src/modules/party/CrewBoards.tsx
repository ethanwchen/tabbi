/*
 * Port of CrewBoards: This week and the Hall of Fame. The top 3 stand as
 * featured tiles beside the rest as a list (Regular and Large), or as the
 * first rows of one list carrying the place chip and two pets (Compact),
 * with my crew pinned under the list when it is not already in view.
 */

import { useStore } from "../../app/useStore";
import { crewHours } from "../../core/crews/crewFormat";
import type { CrewBoardEntry, CrewHallEntry, CrewMedals, CrewPet, CrewSummary } from "../../core/crews/crewModels";
import { isQuietWeek, myHallEntry, weekEntries } from "../../core/crews/crewsState";
import { tr } from "../../core/localization/tr";
import { Shimmer, SkeletonLine } from "../../ui/kit/Loading";
import { Tooltip } from "../../ui/kit/Tooltip";
import { CrewLayout, CrewPetGroup, CrewPlaceChip, CrewRow, CrewRowList, CrewRowName, CrewStatus, CrewSummaryCrest, CrewTally, crewTallyLabel, useCrewIsCompact } from "./CrewComponents";
import type { CrewsStore } from "./crewsStore";
import { useMyCrewPet } from "./CrewPages";

/** One place on a board, whichever board: the weekly hours or the Hall of Fame's medals. */
export interface CrewBoardItem {
  readonly rank: number;
  readonly crew: CrewSummary;
  readonly value: { readonly kind: "minutes"; readonly minutes: number } | { readonly kind: "medals"; readonly medals: CrewMedals };
  readonly pets: readonly CrewPet[];
  readonly tiedWith: readonly string[];
}

function weekItem(entry: CrewBoardEntry): CrewBoardItem {
  return {
    rank: entry.rank,
    crew: entry.crew,
    value: { kind: "minutes", minutes: entry.minutes },
    pets: entry.pets,
    tiedWith: entry.tiedWith,
  };
}

function hallItem(entry: CrewHallEntry): CrewBoardItem {
  return {
    rank: entry.rank,
    crew: entry.crew,
    value: { kind: "medals", medals: entry.medals },
    pets: entry.pets,
    tiedWith: [],
  };
}

/* MARK: This week */

export function CrewWeekScreen({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (store) => store.crews);
  const myPet = useMyCrewPet(crews);
  const board = state.board;
  if (board === undefined) return <CrewBoardSkeleton />;
  if (isQuietWeek(state)) {
    return (
      <CrewStatus
        pet={{ pet: myPet, asleep: true }}
        title={tr("A quiet start to the week")}
        detail={tr("Hours show up after the first focus session. Last week's top 3 keep their laurels until Sunday.")}
      />
    );
  }
  const mine = state.mine;
  return (
    <CrewBoardBody
      crews={crews}
      items={weekEntries(state).map(weekItem)}
      mine={mine?.summary}
      mineValue={
        mine === undefined
          ? undefined
          : {
              kind: "minutes",
              minutes: board.mine?.minutes ?? mine.summary.weekMinutes,
            }
      }
      mineRank={board.mine?.rank}
      onNearEnd={() => crews.loadMoreBoard()}
    />
  );
}

/* MARK: Hall of Fame */

export function CrewHallScreen({ crews }: { crews: CrewsStore }) {
  const state = useStore(crews, (store) => store.crews);
  const hall = state.hall;
  if (hall === undefined) return <CrewBoardSkeleton />;
  if (hall.length === 0) return <CrewStatus symbol="medal" title={tr("No medals yet")} detail={tr("Every Sunday's top 3 earn a medal")} />;
  const mine = state.mine;
  const standing = state.hallMine ?? myHallEntry(state);
  return (
    <CrewBoardBody
      crews={crews}
      items={hall.map(hallItem)}
      mine={mine?.summary}
      mineValue={mine === undefined ? undefined : { kind: "medals", medals: standing?.medals ?? mine.medals }}
      mineRank={standing?.rank}
      onNearEnd={() => crews.loadMoreHall()}
    />
  );
}

/* MARK: The board's layout */

function CrewBoardBody({
  crews,
  items,
  mine,
  mineValue,
  mineRank,
  onNearEnd,
}: {
  crews: CrewsStore;
  items: readonly CrewBoardItem[];
  mine: CrewSummary | undefined;
  mineValue: CrewBoardItem["value"] | undefined;
  mineRank: number | undefined;
  onNearEnd: () => void;
}) {
  const compact = useCrewIsCompact();
  const myIndex = mine === undefined ? -1 : items.findIndex((item) => item.crew.id === mine.id);
  /* My crew under the list: its place, or a dash before it has one. */
  const pinnedItem: CrewBoardItem | undefined =
    mine === undefined || mineValue === undefined
      ? undefined
      : myIndex >= 0
        ? (items[myIndex] as CrewBoardItem)
        : {
            rank: mineRank ?? 0,
            crew: mine,
            value: mineValue,
            pets: [],
            tiedWith: [],
          };
  const pinnedRow = (shown: boolean) => (shown && pinnedItem !== undefined ? <CrewBoardRow crews={crews} item={pinnedItem} mine /> : undefined);
  if (compact) {
    const pinned = mine !== undefined && (myIndex < 0 || myIndex >= 2);
    return (
      <CrewRowList
        count={items.length}
        row={(index) => {
          const item = items[index] as CrewBoardItem;
          const isMine = item.crew.id === mine?.id;
          return index < 3 && item.rank <= 3 ? <CrewFeaturedRow crews={crews} item={item} mine={isMine} /> : <CrewBoardRow crews={crews} item={item} mine={isMine} />;
        }}
        pinned={pinnedRow(pinned)}
        onNearEnd={onNearEnd}
      />
    );
  }
  const top: CrewBoardItem[] = [];
  for (const item of items) {
    if (item.rank > 3 || top.length === 3) break;
    top.push(item);
  }
  const rest = items.slice(top.length);
  const pinned = mine !== undefined && (myIndex < 0 || myIndex >= top.length + 2);
  return (
    <div className="crew-board">
      <div className="crew-tiles" role="list">
        {top.map((item) => (
          <CrewFeaturedTile key={item.crew.id} crews={crews} item={item} mine={item.crew.id === mine?.id} />
        ))}
      </div>
      <CrewRowList
        count={rest.length}
        row={(index) => {
          const item = rest[index] as CrewBoardItem;
          return <CrewBoardRow crews={crews} item={item} mine={item.crew.id === mine?.id} />;
        }}
        pinned={pinnedRow(pinned)}
        onNearEnd={onNearEnd}
      />
    </div>
  );
}

/** A featured tile: the place chip and crest, the crew's most active pets, the name on up to two lines, and the value. */
function CrewFeaturedTile({ crews, item, mine }: { crews: CrewsStore; item: CrewBoardItem; mine: boolean }) {
  return (
    <Tooltip text={crewLead(item)}>
      <div
        className="crew-tile"
        role="listitem"
        tabIndex={0}
        data-first={item.rank === 1 || undefined}
        data-mine={mine || undefined}
        aria-label={crewBoardLabel(item)}
        onClick={() => crews.openCrew(item.crew.id)}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            crews.openCrew(item.crew.id);
          }
        }}
      >
        <span className="crew-tile-top">
          <CrewPlaceChip place={item.rank} />
          <CrewSummaryCrest crew={item.crew} />
        </span>
        <span className="crew-tile-pets">
          <CrewPetGroup pets={item.pets.slice(0, 3)} overlap={13} />
        </span>
        <span className="crew-tile-name kit-caption kit-user-text">{item.crew.name}</span>
        <CrewBoardValue value={item.value} />
      </div>
    </Tooltip>
  );
}

/** A Compact board's first rows: the tile's content in a row. */
function CrewFeaturedRow({ crews, item, mine }: { crews: CrewsStore; item: CrewBoardItem; mine: boolean }) {
  return (
    <CrewRow mine={mine} help={crewLead(item)} label={crewBoardLabel(item)} onClick={() => crews.openCrew(item.crew.id)}>
      <span className="crew-rank-column">
        <CrewPlaceChip place={item.rank} />
      </span>
      <CrewSummaryCrest crew={item.crew} />
      <CrewRowName name={item.crew.name} caption={mine ? tr("Your crew") : tr("%lld members", item.crew.memberCount)} captionAccent={mine} />
      <span className="crew-row-pets">
        <CrewPetGroup pets={item.pets.slice(0, 2)} overlap={12} />
      </span>
      <CrewBoardValue value={item.value} />
    </CrewRow>
  );
}

/** A board row: place, crest, name over the members, value. */
function CrewBoardRow({ crews, item, mine }: { crews: CrewsStore; item: CrewBoardItem; mine: boolean }) {
  const tied = item.tiedWith.length > 0;
  return (
    <CrewRow mine={mine} help={tied ? `${item.crew.name} · ${crewTie(item)}` : item.crew.name} label={crewBoardLabel(item)} onClick={() => crews.openCrew(item.crew.id)}>
      <span className="crew-rank crew-number" dir="ltr">
        {item.rank > 0 ? item.rank.toLocaleString("en-US") : "-"}
        {tied && <span className="crew-rank-tie">=</span>}
      </span>
      <CrewSummaryCrest crew={item.crew} />
      <CrewRowName name={item.crew.name} caption={mine ? tr("Your crew") : tr("%lld members", item.crew.memberCount)} captionAccent={mine} />
      <CrewBoardValue value={item.value} />
    </CrewRow>
  );
}

/** Hours, or the medal tally. */
function CrewBoardValue({ value }: { value: CrewBoardItem["value"] }) {
  return value.kind === "minutes" ? <span className="crew-value crew-number">{crewHours(value.minutes)}</span> : <CrewTally medals={value.medals} />;
}

/** "Night Owls leads the week" and friends, the tile's tooltip. */
function crewLead(item: CrewBoardItem): string {
  if (item.value.kind === "medals") return crewBoardLabel(item);
  switch (item.rank) {
    case 1:
      return tr("%@ leads the week", item.crew.name);
    case 2:
      return tr("%@ is second this week", item.crew.name);
    case 3:
      return tr("%@ is third this week", item.crew.name);
    default:
      return item.crew.name;
  }
}

function crewTie(item: CrewBoardItem): string {
  if (item.value.kind !== "minutes") return "";
  const names = new Intl.ListFormat(document.documentElement.lang || "en", {
    type: "conjunction",
  }).format(item.tiedWith);
  return tr("Tied with %@ at %@", names, crewHours(item.value.minutes));
}

function crewBoardLabel(item: CrewBoardItem): string {
  if (item.value.kind === "medals") return tr("Rank %lld, %@, %@", item.rank, item.crew.name, crewTallyLabel(item.value.medals));
  const base = tr("Rank %lld, %@, %@ this week, %@", item.rank, item.crew.name, crewHours(item.value.minutes), tr("%lld members", item.crew.memberCount));
  return item.tiedWith.length === 0 ? base : `${base}, ${crewTie(item)}`;
}

/** The board while it loads: the tiles and rows as placeholder shapes. */
export function CrewBoardSkeleton() {
  const compact = useCrewIsCompact();
  return (
    <Shimmer className="crew-skeleton">
      <div className="crew-board" aria-busy="true" role="img" aria-label={tr("Loading the board")}>
        {!compact && (
          <div className="crew-tiles">
            {[0, 1, 2].map((index) => (
              <div key={index} className="crew-tile crew-skeleton-tile">
                <span className="crew-tile-top">
                  <SkeletonLine width={24} height={14} />
                  <SkeletonLine width={32} height={32} />
                </span>
                <SkeletonLine width={66} height={26} />
                <SkeletonLine width={56} height={10} />
                <SkeletonLine width={36} height={12} />
              </div>
            ))}
          </div>
        )}
        <div className="crew-skeleton-rows">
          {[0, 1, 2].map((index) => (
            <div key={index} className="crew-row" style={{ height: CrewLayout.rowHeight }}>
              <SkeletonLine width={12} height={12} />
              <SkeletonLine width={32} height={32} />
              <span className="crew-row-name crew-skeleton-name">
                <SkeletonLine width={90} height={10} />
                <SkeletonLine width={50} height={8} />
              </span>
              <SkeletonLine width={34} height={12} />
            </div>
          ))}
        </div>
      </div>
    </Shimmer>
  );
}
