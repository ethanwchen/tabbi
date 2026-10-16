/*
 * The Mac's TactileButtonStyle: a control sinks while pressed (press spring,
 * no bounce) and, when it `lifts`, grows a little while hovered (hover
 * spring). Under Reduce Motion a press dims it instead. The amounts come
 * from the core's TactileFeedback. `useTactile` gives a control the
 * handlers and the inline style; the label keeps its own hover colors.
 */

import { useMemo, useState, type CSSProperties, type KeyboardEvent, type PointerEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useKit } from "./context";
import { adaptedTransition, transitionCss } from "./motion";
import { themedSpring } from "./tokens";

/** A forced state for reviews: the gallery renders every control hovered and pressed. */
export type PreviewState = "hover" | "pressed" | undefined;

export interface TactileOptions {
  readonly feedback?: TactileFeedback;
  readonly lifts?: boolean;
  readonly disabled?: boolean;
  readonly preview?: PreviewState;
}

export interface TactileHandlers<E extends HTMLElement = HTMLElement> {
  onPointerEnter: (event: PointerEvent<E>) => void;
  onPointerLeave: (event: PointerEvent<E>) => void;
  onPointerDown: (event: PointerEvent<E>) => void;
  onPointerUp: (event: PointerEvent<E>) => void;
  onPointerCancel: (event: PointerEvent<E>) => void;
  onKeyDown: (event: KeyboardEvent<E>) => void;
  onKeyUp: (event: KeyboardEvent<E>) => void;
}

export interface Tactile {
  readonly hovering: boolean;
  readonly pressed: boolean;
  readonly style: CSSProperties;
  readonly handlers: TactileHandlers;
  /** `data-hover` and `data-pressed`, so CSS can color the label. */
  readonly data: { "data-hover": boolean; "data-pressed": boolean };
}

const PRESS_KEYS = new Set([" ", "Enter"]);

export function useTactile({ feedback = TactileFeedback.control, lifts = false, disabled = false, preview }: TactileOptions = {}): Tactile {
  const { theme, pace, reduceMotion, still } = useKit();
  const [hoverState, setHover] = useState(false);
  const [pressState, setPressed] = useState(false);
  const hovering = !disabled && (preview === "hover" || preview === "pressed" || hoverState);
  const pressed = !disabled && (preview === "pressed" || pressState);

  const handlers = useMemo<TactileHandlers>(
    () => ({
      onPointerEnter: () => setHover(true),
      onPointerLeave: () => {
        setHover(false);
        setPressed(false);
      },
      onPointerDown: (event) => {
        if (event.button === 0) setPressed(true);
      },
      onPointerUp: () => setPressed(false),
      onPointerCancel: () => setPressed(false),
      onKeyDown: (event) => {
        if (PRESS_KEYS.has(event.key) && !event.repeat) setPressed(true);
      },
      onKeyUp: (event) => {
        if (PRESS_KEYS.has(event.key)) setPressed(false);
      },
    }),
    [],
  );

  const style = useMemo<CSSProperties>(() => {
    const scale = feedback.scale(pressed, hovering, lifts, reduceMotion);
    const opacity = feedback.opacity(pressed, reduceMotion);
    const token = pressed ? "press" : "hover";
    const spec = themedSpring(theme, pace, token);
    const transition = still || !spec ? { duration: 0, easing: "linear" } : adaptedTransition(spec, reduceMotion, pace);
    return {
      transform: scale === 1 ? undefined : `scale(${scale})`,
      opacity: opacity === 1 ? undefined : opacity,
      transition: transitionCss(["transform", "opacity"], transition),
    };
  }, [feedback, pressed, hovering, lifts, reduceMotion, theme, pace, still]);

  return {
    hovering,
    pressed,
    style,
    handlers,
    data: { "data-hover": hovering, "data-pressed": pressed },
  };
}

/** Merges a tactile's handlers with a caller's, so both run. */
export function mergeHandlers<E extends HTMLElement>(tactile: TactileHandlers, own: Partial<TactileHandlers<E>>): TactileHandlers<E> {
  const merged: Record<string, unknown> = {};
  for (const key of Object.keys(tactile) as (keyof TactileHandlers)[]) {
    const theirs = own[key] as ((event: never) => void) | undefined;
    const ours = tactile[key] as (event: never) => void;
    merged[key] = theirs
      ? (event: never) => {
          ours(event);
          theirs(event);
        }
      : ours;
  }
  return merged as unknown as TactileHandlers<E>;
}
