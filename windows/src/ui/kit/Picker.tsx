/*
 * A picker in Tabbi's look, the Settings window's pop-up menu (the theme,
 * the AI provider, the focus method): a 24 px field showing the chosen
 * item with an up-down chevron, which opens a menu of rows on a card (a
 * check beside the chosen one, a caption under a row that has one). Arrow
 * keys move through the menu, Enter picks, Esc closes; a click outside
 * closes it too. The field is tactile and has a tooltip.
 */

import { useCallback, useEffect, useId, useRef, useState, type CSSProperties, type KeyboardEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";

export interface PickerItem<T extends string> {
  readonly id: T;
  readonly title: string;
  readonly caption?: string;
  readonly symbol?: string;
  readonly disabled?: boolean;
}

export interface PickerProps<T extends string> {
  readonly items: readonly PickerItem<T>[];
  readonly selected: T;
  readonly onSelect: (id: T) => void;
  readonly label: string;
  readonly help?: string;
  readonly disabled?: boolean;
  /** Keeps the menu open, for reviews. */
  readonly open?: boolean;
  readonly preview?: PreviewState;
  readonly width?: number | string;
  readonly className?: string;
}

export function Picker<T extends string>({ items, selected, onSelect, label, help, disabled = false, open: forcedOpen, preview, width, className }: PickerProps<T>) {
  const id = useId();
  const [isOpen, setOpen] = useState(false);
  const [active, setActive] = useState<T>(selected);
  const root = useRef<HTMLDivElement>(null);
  const open = forcedOpen ?? isOpen;
  const tactile = useTactile({ feedback: TactileFeedback.pill, disabled, preview });
  const transition = useTransition("snappy", ["background-color", "border-color", "box-shadow"]);
  const handlers = mergeHandlers<HTMLButtonElement>(tactile.handlers, {});
  const current = items.find((item) => item.id === selected);

  const close = useCallback(() => setOpen(false), []);
  const show = () => {
    setActive(selected);
    setOpen(true);
  };

  useEffect(() => {
    if (!open) return;
    const onPointer = (event: PointerEvent) => {
      if (root.current && !root.current.contains(event.target as Node)) close();
    };
    document.addEventListener("pointerdown", onPointer);
    return () => document.removeEventListener("pointerdown", onPointer);
  }, [open, selected, close]);

  const choose = (item: PickerItem<T>) => {
    if (item.disabled) return;
    onSelect(item.id);
    close();
  };

  const onKeyDown = (event: KeyboardEvent<HTMLElement>) => {
    if (disabled) return;
    const enabled = items.filter((item) => !item.disabled);
    const index = enabled.findIndex((item) => item.id === active);
    const move = (step: number) => {
      const next = enabled[(index + step + enabled.length) % enabled.length];
      if (next) setActive(next.id);
    };
    switch (event.key) {
      case "ArrowDown":
        if (!open) show();
        else move(1);
        break;
      case "ArrowUp":
        if (!open) show();
        else move(-1);
        break;
      case "Enter":
      case " ":
        if (!open) show();
        else {
          const item = items.find((i) => i.id === active);
          if (item) choose(item);
        }
        break;
      case "Escape":
        if (!open) return;
        close();
        break;
      default:
        return;
    }
    event.preventDefault();
  };

  const style: CSSProperties = { ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", "), width };
  return (
    <div ref={root} className={["kit-picker", className].filter(Boolean).join(" ")} onKeyDown={onKeyDown}>
      <Tooltip text={help ?? label}>
        <button
          type="button"
          className="kit-picker-field"
          aria-label={label}
          aria-haspopup="listbox"
          aria-expanded={open}
          aria-controls={`${id}-menu`}
          disabled={disabled}
          data-open={open}
          {...tactile.data}
          {...handlers}
          onClick={() => {
            setActive(selected);
            setOpen((o) => !o);
          }}
          style={style}
        >
          {current?.symbol && <Icon id={current.symbol} size={12} className="kit-picker-symbol" />}
          <span className="kit-picker-title">{current?.title ?? ""}</span>
          <Icon id="chevron-up-down" size={12} className="kit-picker-chevron" />
        </button>
      </Tooltip>
      {open && (
        <ul id={`${id}-menu`} className="kit-picker-menu kit-card" role="listbox" aria-label={label} aria-activedescendant={`${id}-${active}`}>
          {items.map((item) => (
            <li
              key={item.id}
              id={`${id}-${item.id}`}
              role="option"
              aria-selected={item.id === selected}
              aria-disabled={item.disabled || undefined}
              className="kit-picker-item"
              data-active={item.id === active}
              data-selected={item.id === selected}
              onPointerEnter={() => {
                if (!item.disabled) setActive(item.id);
              }}
              onClick={() => choose(item)}
            >
              <span className="kit-picker-check">{item.id === selected && <Icon id="check" size={11} fixedDirection />}</span>
              {item.symbol && <Icon id={item.symbol} size={12} className="kit-picker-symbol" />}
              <span className="kit-picker-item-text">
                <span className="kit-picker-item-title">{item.title}</span>
                {item.caption && <span className="kit-picker-item-caption">{item.caption}</span>}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
