/*
 * The Mac's `.contextMenu`: a right-click (or Shift+F10) on a row opens a
 * small menu of actions at the pointer, drawn like the Picker's menu on a
 * card and portaled to the body so no clipping container cuts it. A click
 * on an item runs it and closes the menu; a click elsewhere, Escape or a
 * scroll closes it. Destructive items (Remove, Block) draw in the danger
 * color. `useContextMenu` gives a row the handler and the menu element.
 */

import { useCallback, useEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type MouseEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Icon } from "./Icon";

export interface ContextMenuItem {
  readonly title: string;
  readonly symbol?: string;
  readonly destructive?: boolean;
  /** A hairline before this item. */
  readonly separator?: boolean;
  readonly onSelect: () => void;
}

export interface ContextMenuProps {
  readonly items: readonly ContextMenuItem[];
  /** Where to open, in viewport pixels; the menu stays inside the window. */
  readonly at: { readonly x: number; readonly y: number };
  readonly onClose: () => void;
  readonly label?: string;
}

const MARGIN = 8;

export function ContextMenu({ items, at, onClose, label }: ContextMenuProps) {
  const menu = useRef<HTMLUListElement>(null);
  const [position, setPosition] = useState<{ left: number; top: number } | null>(null);
  const [active, setActive] = useState(0);

  useEffect(() => {
    const element = menu.current;
    if (!element) return;
    const box = element.getBoundingClientRect();
    const left = Math.max(MARGIN, Math.min(at.x, window.innerWidth - box.width - MARGIN));
    const top = Math.max(MARGIN, Math.min(at.y, window.innerHeight - box.height - MARGIN));
    setPosition({ left: Math.round(left + window.scrollX), top: Math.round(top + window.scrollY) });
    element.focus();
  }, [at]);

  useEffect(() => {
    const onPointer = (event: PointerEvent) => {
      if (menu.current && !menu.current.contains(event.target as Node)) onClose();
    };
    const onScroll = () => onClose();
    document.addEventListener("pointerdown", onPointer, true);
    window.addEventListener("scroll", onScroll, true);
    window.addEventListener("blur", onScroll);
    return () => {
      document.removeEventListener("pointerdown", onPointer, true);
      window.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("blur", onScroll);
    };
  }, [onClose]);

  const choose = (item: ContextMenuItem) => {
    onClose();
    item.onSelect();
  };

  const onKeyDown = (event: KeyboardEvent<HTMLUListElement>) => {
    switch (event.key) {
      case "Escape":
        onClose();
        break;
      case "ArrowDown":
        setActive((index) => (index + 1) % items.length);
        break;
      case "ArrowUp":
        setActive((index) => (index - 1 + items.length) % items.length);
        break;
      case "Enter":
      case " ": {
        const item = items[active];
        if (item) choose(item);
        break;
      }
      default:
        return;
    }
    event.preventDefault();
  };

  return createPortal(
    <ul
      ref={menu}
      role="menu"
      aria-label={label}
      tabIndex={-1}
      className="kit-menu kit-card"
      data-visible={position !== null}
      style={position ? { left: position.left, top: position.top } : { left: 0, top: 0 }}
      onKeyDown={onKeyDown}
      onContextMenu={(event) => event.preventDefault()}
    >
      {items.map((item, index) => (
        <li
          key={item.title}
          role="menuitem"
          className="kit-menu-item"
          data-active={index === active}
          data-destructive={item.destructive || undefined}
          data-separator={item.separator || undefined}
          onPointerEnter={() => setActive(index)}
          onClick={() => choose(item)}
        >
          {item.symbol && <Icon id={item.symbol} size={12} />}
          <span>{item.title}</span>
        </li>
      ))}
    </ul>,
    document.body,
  );
}

export interface ContextMenuHandle {
  /** Put on the row: `onContextMenu={menu.open}`. */
  readonly open: (event: MouseEvent<HTMLElement>) => void;
  /** The menu element while open; render it inside the row. */
  readonly element: ReactNode;
  readonly isOpen: boolean;
}

/** A context menu for one row with `items`; `items` is read when the menu opens. */
export function useContextMenu(items: () => readonly ContextMenuItem[], label?: string): ContextMenuHandle {
  const [at, setAt] = useState<{ x: number; y: number } | null>(null);
  const [current, setCurrent] = useState<readonly ContextMenuItem[]>([]);
  const close = useCallback(() => setAt(null), []);
  const open = useCallback(
    (event: MouseEvent<HTMLElement>) => {
      const list = items();
      if (list.length === 0) return;
      event.preventDefault();
      event.stopPropagation();
      setCurrent(list);
      /* A keyboard-opened menu (Shift+F10) has no pointer: open at the row. */
      const box = event.currentTarget.getBoundingClientRect();
      setAt(event.clientX === 0 && event.clientY === 0 ? { x: box.left + 12, y: box.bottom } : { x: event.clientX, y: event.clientY });
    },
    [items],
  );
  const style: CSSProperties = { display: "contents" };
  return {
    open,
    isOpen: at !== null,
    element: at === null ? null : <span style={style}><ContextMenu items={current} at={at} onClose={close} label={label} /></span>,
  };
}
