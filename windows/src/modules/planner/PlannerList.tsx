/*
 * Port of PlannerList.swift: today's items, after any rows other modules
 * share. Scrolls only once they outgrow the canvas, ending on a whole row
 * with a fade so the list reads as "more below". Checklist rows reorder by
 * dragging: the others slide aside live and the move is saved on release.
 */

import { useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type PointerEvent } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { RowReorderDrag } from "../../core/modules/rowReorderDrag";
import { rowViewportHeight } from "../../core/modules/rowViewport";
import type { PlannerItem } from "../../core/planner/plannerDay";
import type { SharedTodayItem } from "../../core/providers/sharedTodayItem";
import { CheckGlyph } from "../../ui/kit/CheckGlyph";
import { useTheme } from "../../ui/kit/context";
import { EdgeFade } from "../../ui/kit/EdgeFade";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { accentCss, Spacing } from "../../ui/kit/tokens";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { FocusCardActions } from "./focusCardActions";
import { PlannerGlyphButton } from "./plannerControls";
import type { PlannerStore } from "./plannerStore";

/** The checklist row height, which the list scrolls and reorders by. */
export const PLANNER_ROW_HEIGHT = 22;
const FADE_HEIGHT = Spacing.m;
/** How far the pointer moves before a press becomes a drag. */
const DRAG_THRESHOLD = 4;

export interface PlannerListProps {
  readonly context: ModuleContext;
  readonly store: PlannerStore;
  /** Other modules' goals and tasks, shown first and not editable here. */
  readonly shared: readonly SharedTodayItem[];
  readonly focus: FocusCardActions;
  readonly openModule: (id: SharedTodayItem["source"], action: SharedTodayItem["action"]) => void;
}

interface Drag {
  readonly id: string;
  readonly drag: RowReorderDrag;
  /** The pointer's y when the press began. */
  readonly originY: number;
  /** True once the pointer moved past the threshold. */
  readonly lifted: boolean;
}

export function PlannerList({ context, store, shared, focus, openModule }: PlannerListProps) {
  const state = useStore(store);
  const items = store.items;
  const leftovers = new Set(state.viewing === "yesterday" ? store.leftovers.map((item) => item.id) : []);
  const container = useRef<HTMLDivElement>(null);
  const [available, setAvailable] = useState<number | undefined>(undefined);
  const [drag, setDrag] = useState<Drag | undefined>(undefined);
  const [renaming, setRenaming] = useState<string | undefined>(undefined);

  useLayoutEffect(() => {
    const element = container.current;
    if (!element) return;
    const measure = () => setAvailable(element.clientHeight);
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const total = (shared.length + items.length) * PLANNER_ROW_HEIGHT;
  const scrolls = available !== undefined && total > available + 0.5;
  const viewport = available === undefined ? undefined : rowViewportHeight(available, PLANNER_ROW_HEIGHT);

  const offset = (index: number): number => {
    if (drag === undefined || !drag.lifted) return 0;
    return drag.drag.offset(index);
  };

  const rows = (
    <div className="planner-rows" style={scrolls ? { paddingBottom: FADE_HEIGHT } : undefined}>
      {shared.map((item) => (
        <PlannerSharedRow key={item.id} item={item} context={context} open={() => openModule(item.source, item.action)} />
      ))}
      {items.map((item, index) => (
        <PlannerRow
          key={item.id}
          item={item}
          store={store}
          focus={focus}
          isLifted={drag?.id === item.id && drag.lifted}
          isLeftover={leftovers.has(item.id)}
          isRenaming={renaming === item.id}
          beginRename={() => {
            if (store.canEdit) setRenaming(item.id);
          }}
          endRename={() => setRenaming(undefined)}
          offset={offset(index)}
          animates={drag === undefined || drag.id !== item.id}
          onPointerDown={(event) => {
            if (!store.canEdit || renaming === item.id || event.button !== 0) return;
            if (event.target instanceof HTMLElement && event.target.closest("button, input")) return;
            setDrag({ id: item.id, drag: new RowReorderDrag(index, items.length, PLANNER_ROW_HEIGHT), originY: event.clientY, lifted: false });
            event.currentTarget.setPointerCapture(event.pointerId);
          }}
          onPointerMove={(event) => {
            if (drag === undefined || drag.id !== item.id) return;
            const translation = event.clientY - drag.originY;
            if (!drag.lifted && Math.abs(translation) < DRAG_THRESHOLD) return;
            const next = new RowReorderDrag(drag.drag.from, drag.drag.count, drag.drag.rowHeight, translation);
            setDrag({ ...drag, drag: next, lifted: true });
          }}
          onPointerUp={() => {
            if (drag === undefined || drag.id !== item.id) return;
            /* Clear the offsets and apply the move together so rows settle in one motion. */
            setDrag(undefined);
            if (drag.lifted && drag.drag.movesRow) store.move(drag.id, drag.drag.target);
          }}
        />
      ))}
    </div>
  );

  return (
    <div ref={container} className="planner-list" data-scrolls={scrolls}>
      {scrolls ? (
        <EdgeFade edge="bottom" length={FADE_HEIGHT} style={{ height: viewport }}>
          <div className="planner-scroll" data-still={context.isSnapshot}>
            {rows}
          </div>
        </EdgeFade>
      ) : (
        rows
      )}
    </div>
  );
}

interface PlannerRowProps {
  readonly item: PlannerItem;
  readonly store: PlannerStore;
  readonly focus: FocusCardActions;
  readonly isLifted: boolean;
  readonly isLeftover: boolean;
  readonly isRenaming: boolean;
  readonly beginRename: () => void;
  readonly endRename: () => void;
  readonly offset: number;
  readonly animates: boolean;
  readonly onPointerDown: (event: PointerEvent<HTMLDivElement>) => void;
  readonly onPointerMove: (event: PointerEvent<HTMLDivElement>) => void;
  readonly onPointerUp: (event: PointerEvent<HTMLDivElement>) => void;
}

/** One checklist row: checkbox, title (double-click to rename), and focus and delete buttons that appear on hover. */
function PlannerRow({ item, store, focus, isLifted, isLeftover, isRenaming, beginRename, endRename, offset, animates, onPointerDown, onPointerMove, onPointerUp }: PlannerRowProps) {
  const [hovering, setHovering] = useState(false);
  const [draft, setDraft] = useState(item.title);
  const { timer } = useStore(focus.service);
  const viewing = store.state.viewing;
  const canEdit = store.canEdit;
  const isLinked = timer.linkedItemID === item.id;
  const commit = () => {
    endRename();
    store.rename(item.id, draft);
  };
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    /* The island's own Escape closes the panel; inside the field it only restores the title. */
    event.stopPropagation();
    if (event.key === "Enter") {
      event.preventDefault();
      commit();
    } else if (event.key === "Escape") {
      event.preventDefault();
      setDraft(item.title);
      endRename();
    }
  };
  const showsFocus = !isRenaming && store.state.focusClockOwner === undefined && viewing === "today";
  return (
    <div
      className="planner-row"
      data-lifted={isLifted}
      data-hover={hovering || isRenaming}
      style={{ transform: offset === 0 ? undefined : `translateY(${offset}px)`, transition: animates ? undefined : "none", zIndex: isLifted ? 1 : undefined } as CSSProperties}
      onPointerEnter={() => setHovering(true)}
      onPointerLeave={() => setHovering(false)}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      <PlannerCheckbox title={item.title} isOn={item.isDone} disabled={!canEdit} onToggle={() => store.toggle(item.id)} />
      {isRenaming ? (
        <input
          className="planner-rename kit-user-text"
          autoFocus
          value={draft}
          aria-label={item.title}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={onKeyDown}
          onBlur={commit}
        />
      ) : (
        <div
          className="planner-row-title"
          data-done={item.isDone}
          onDoubleClick={() => {
            setDraft(item.title);
            beginRename();
          }}
        >
          <MarqueeText text={item.title} userText />
        </div>
      )}
      {viewing === "yesterday" && !item.isDone && (
        isLeftover ? (
          <PlannerGlyphButton
            symbol="arrow.uturn.forward"
            glyphSize={9}
            help={tr("Move to today")}
            className="planner-row-button"
            style={{ opacity: hovering ? 1 : 0 }}
            onClick={() => store.moveToToday(new Set([item.id]))}
          />
        ) : (
          <Tooltip text={tr("This task is on today's list")}>
            <span className="planner-row-note">{tr("On today")}</span>
          </Tooltip>
        )
      )}
      {showsFocus && (
        isLinked ? (
          hovering && canEdit ? (
            <PlannerGlyphButton symbol="scope" isTinted help={tr("Stop focusing on this task")} className="planner-row-button" onClick={() => focus.link(undefined)} />
          ) : (
            <Tooltip text={tr("The focus timer is on this task")}>
              <span className="planner-row-scope">
                <Icon id="scope" size={10} />
              </span>
            </Tooltip>
          )
        ) : (
          hovering && canEdit && !item.isDone && (
            <PlannerGlyphButton symbol="scope" help={tr("Focus on this task")} className="planner-row-button" onClick={() => focus.link(item.id)} />
          )
        )
      )}
      {hovering && !isRenaming && canEdit && (
        <PlannerGlyphButton symbol="xmark" tint="var(--danger)" glyphSize={9} help={tr("Delete task")} className="planner-row-button" onClick={() => store.delete(item.id)} />
      )}
    </div>
  );
}

/** Round checkbox whose check draws on with a small bounce, filled with the module accent. */
function PlannerCheckbox({ title, isOn, disabled, onToggle }: { title: string; isOn: boolean; disabled: boolean; onToggle: () => void }) {
  const [hovering, setHovering] = useState(false);
  const help = isOn ? tr("Mark as not done") : tr("Mark as done");
  return (
    <Tooltip text={help}>
      <button
        type="button"
        role="checkbox"
        aria-checked={isOn}
        aria-label={title}
        className="planner-checkbox"
        disabled={disabled}
        onPointerEnter={() => setHovering(true)}
        onPointerLeave={() => setHovering(false)}
        onClick={onToggle}
      >
        <CheckGlyph isOn={isOn} ring={hovering && !disabled ? "var(--accent)" : "var(--tertiary-text)"} size={16} />
      </button>
    </Tooltip>
  );
}

/**
 * A goal or task another module shares, pinned above the checklist, e.g.
 * "Anki reviews, 320 cards left". Its checkbox is a ring that fills in the
 * source module's accent as the work gets done and checks itself at zero.
 * Clicking opens that module's tab and runs the item's one-click action.
 */
function PlannerSharedRow({ item, context, open }: { item: SharedTodayItem; context: ModuleContext; open: () => void }) {
  const theme = useTheme();
  const [hovering, setHovering] = useState(false);
  const descriptor = context.settings.catalog.descriptor(item.source);
  const accent = accentCss(theme, descriptor.accent);
  const action = item.action;
  const help =
    action !== undefined
      ? tr("%@ in %@", action.title, descriptor.title)
      : item.isDone
        ? tr("%@ done for today. Open %@", item.title, descriptor.title)
        : tr("Checks itself when done. Open %@", descriptor.title);
  return (
    <Tooltip text={help}>
      <button type="button" className="planner-row planner-shared-row" data-hover={hovering} onPointerEnter={() => setHovering(true)} onPointerLeave={() => setHovering(false)} onClick={open}>
        <span className="planner-shared-check" style={{ "--row-accent": accent } as CSSProperties}>
          <ProgressRingSmall fraction={item.fraction ?? 0} accent={accent} />
          {!item.isDone && (
            <span className="planner-shared-symbol">
              <Icon id={descriptor.symbol} size={7} />
            </span>
          )}
          {item.isDone && (
            <span className="planner-shared-done">
              <CheckGlyph isOn tint={accent} ring={null} size={16} />
            </span>
          )}
        </span>
        <div className="planner-row-title" data-done={item.isDone}>
          <MarqueeText text={item.title} userText />
        </div>
        {item.detail !== undefined && <span className="planner-shared-detail">{item.detail}</span>}
        <span className="planner-shared-chevron" data-visible={hovering}>
          <Icon id="chevron.forward" size={9} />
        </span>
      </button>
    </Tooltip>
  );
}

/** The shared row's ring, 16 px: a faint track and the accent arc for the work done. */
function ProgressRingSmall({ fraction, accent }: { fraction: number; accent: string }) {
  const size = 16;
  const r = size / 2 - 0.75;
  const circumference = 2 * Math.PI * r;
  const clamped = Math.min(Math.max(fraction, 0), 1);
  return (
    <svg className="planner-shared-ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={`color-mix(in srgb, ${accent} 28%, transparent)`} strokeWidth={1.5} />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={accent}
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeDasharray={`${circumference * clamped} ${circumference}`}
        transform={`rotate(-90 ${size / 2} ${size / 2})`}
      />
    </svg>
  );
}
