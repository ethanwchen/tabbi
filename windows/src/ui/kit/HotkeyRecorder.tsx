/*
 * The Mac's `HotkeyRecorderField` for Windows: a clickable shortcut field
 * that shows the current shortcut as Windows names it (Ctrl+Alt+Space) and
 * switches to a highlighted recording state when clicked. While recording
 * it swallows every key, shows the modifiers held so far, accepts the first
 * safe combination, and stops on Esc, on a click or when focus leaves.
 * While it records, the app should suspend its global hotkey, which
 * `onRecordingChange` reports. A refusal (no modifier, a key Tabbi can't
 * register) and a conflict (Windows keeps the combination, or the host
 * says another app owns it) show plainly under the field.
 */

import { useCallback, useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import { tr } from "../../core/localization/tr";
import type { Hotkey } from "../../core/settings/hotkey";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { interpretKey, modifiersLabel, modifiersOf, rejectionText, windowsLabel, windowsReservedReason, type KeyMeaning } from "./hotkeyRecording";
import { Tooltip } from "./Tooltip";

export interface HotkeyRecorderProps {
  readonly hotkey: Hotkey;
  readonly onRecord: (hotkey: Hotkey) => void;
  readonly onRecordingChange?: (recording: boolean) => void;
  /** What the host reports when the shortcut could not be registered (another app owns it). */
  readonly conflict?: string;
  readonly disabled?: boolean;
  /** Starts in the recording state, for reviews. */
  readonly recordingPreview?: boolean;
  readonly preview?: "hover";
  readonly className?: string;
}

export function HotkeyRecorder({ hotkey, onRecord, onRecordingChange, conflict, disabled = false, recordingPreview = false, preview, className }: HotkeyRecorderProps) {
  const [recording, setRecording] = useState(recordingPreview);
  const [held, setHeld] = useState(0);
  const [rejection, setRejection] = useState<KeyMeaning | undefined>(undefined);
  const button = useRef<HTMLButtonElement>(null);
  const transition = useTransition("snappy", ["border-color", "box-shadow", "color", "background-color"]);
  const change = useRef(onRecordingChange);
  useEffect(() => {
    change.current = onRecordingChange;
  }, [onRecordingChange]);

  const stop = useCallback(() => {
    setRecording(false);
    setHeld(0);
    setRejection(undefined);
    change.current?.(false);
  }, []);

  const start = () => {
    if (disabled || recording) return;
    setRecording(true);
    setRejection(undefined);
    change.current?.(true);
    button.current?.focus();
  };

  useEffect(() => {
    if (!recording) return;
    const onKeyUp = (event: KeyboardEvent) => setHeld(modifiersOf(event));
    const onBlur = () => stop();
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", onBlur);
    return () => {
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", onBlur);
    };
  }, [recording, stop]);

  const onKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>) => {
    if (!recording) {
      if (event.key === " " || event.key === "Enter") {
        event.preventDefault();
        start();
      }
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    setHeld(modifiersOf(event));
    /* Holding a key down repeats; only the first press counts. */
    if (event.repeat) return;
    const meaning = interpretKey(event);
    switch (meaning.kind) {
      case "modifierOnly":
        return;
      case "recorded":
        stop();
        onRecord(meaning.hotkey);
        return;
      case "cancelled":
        stop();
        return;
      default:
        setRejection(meaning);
    }
  };

  const label = recording ? (held ? `${modifiersLabel(held)}+` : tr("Type shortcut")) : windowsLabel(hotkey);
  const help = recording ? tr("Press a new shortcut, or Esc to cancel") : tr("Click to record a new shortcut");
  const problem = conflict ?? windowsReservedReason(hotkey) ?? (rejection ? rejectionText(rejection) : undefined);

  return (
    <div className={["kit-hotkey", className].filter(Boolean).join(" ")}>
      <Tooltip text={help}>
        <button
          ref={button}
          type="button"
          className="kit-hotkey-field"
          aria-label={tr("Shortcut %@", windowsLabel(hotkey))}
          aria-pressed={recording}
          disabled={disabled}
          data-recording={recording}
          data-hover={preview === "hover" || undefined}
          data-problem={problem !== undefined && !recording ? "" : undefined}
          style={{ transition }}
          onClick={recording ? stop : start}
          onKeyDown={onKeyDown}
          onBlur={() => {
            if (recording) stop();
          }}
        >
          <span className="kit-hotkey-label">{label}</span>
        </button>
      </Tooltip>
      {problem !== undefined && (
        <div className="kit-hotkey-problem" role="alert">
          <Icon id="warning-filled" size={12} />
          <span>{problem}</span>
        </div>
      )}
    </div>
  );
}
