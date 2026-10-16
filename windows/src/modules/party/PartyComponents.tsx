/*
 * Port of PartyComponents: the small building blocks the Party panel's
 * stage, friends card, onboarding and settings share: a pet drawn from a
 * server profile, the copy-code capsule, the share-invite button, the code
 * field with its Paste, the quiet text button, and the status colors.
 */

import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { currentLanguage, tr } from "../../core/localization/tr";
import { inviteWebURL, type PartyInvite } from "../../core/party/partyInvite";
import { PartyCode, type PartyProfile, type PartyStatus } from "../../core/party/partyModels";
import { partyPet } from "../../core/party/partyPetAppearance";
import type { PetProfile } from "../../core/pets/petProfile";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { PetView } from "../../ui/kit/PetView";
import { Pill } from "../../ui/kit/Pill";
import { Tooltip } from "../../ui/kit/Tooltip";
import { useKit } from "../../ui/kit/context";
import { PetPlayer } from "../../ui/kit/petPlayer";

/** The dot beside a status: accent while studying, amber on a break, green when around, gray when away. */
export function statusColor(status: PartyStatus): string {
  switch (status) {
    case "studying":
      return "var(--accent)";
    case "onBreak":
      return "var(--warning)";
    case "idle":
      return "var(--success)";
    case "offline":
      return "var(--tertiary-text)";
  }
}

/** "K7QW-2MZD": codes read and dictate more easily in groups of four. */
export function displayCode(code: string): string {
  if (code.length <= 6) return code;
  const split = Math.trunc(code.length / 2);
  return `${code.slice(0, split)}-${code.slice(split)}`;
}

/** Puts `text` on the clipboard; false when the page may not (a still render, or no clipboard). */
export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

/** A pet drawn from a server profile (or my own); offline people's pets doze. */
export function PartyPet({ pet, profile, asleep = false, pixelSize = 1 }: { pet?: PetProfile; profile?: PartyProfile; asleep?: boolean; pixelSize?: number }) {
  const shown = useMemo(() => pet ?? (profile === undefined ? undefined : partyPet(profile)), [pet, profile]);
  const player = useMemo(() => (shown === undefined ? undefined : new PetPlayer(shown, { asleep })), [shown, asleep]);
  if (player === undefined) return null;
  return <PetView player={player} pixelSize={pixelSize} />;
}

/** A member's pet that hops once shortly after it appears, staggered so a row bounces like a wave. */
export function HoppingPet({ pet, delay }: { pet: PetProfile; delay: number }) {
  const { reduceMotion, still } = useKit();
  const player = useMemo(() => new PetPlayer(pet), [pet]);
  useEffect(() => {
    if (reduceMotion || still) return;
    const timer = window.setTimeout(() => player.send({ kind: "celebrate" }), delay * 1000);
    return () => window.clearTimeout(timer);
  }, [player, delay, reduceMotion, still]);
  return <PetView player={player} pixelSize={1} />;
}

/** A code in monospaced type with a copy button that confirms with a check. `showsLabel` spells out "Copy" beside the icon. */
export function PartyCopyCode({ code, showsLabel = false, help }: { code: string; showsLabel?: boolean; help: string }) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1500);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return (
    <Tooltip text={copied ? tr("Copied") : help}>
      <button
        type="button"
        className="party-copy-code"
        data-copied={copied || undefined}
        onClick={() => void copyText(displayCode(code)).then((ok) => setCopied(ok))}
      >
        <span className="party-code">{displayCode(code)}</span>
        <Icon id={copied ? "check" : "doc.on.doc"} size={10} className="party-copy-glyph" />
        {showsLabel && <span className="kit-caption party-copy-label">{copied ? tr("Copied") : tr("Copy")}</span>}
      </button>
    </Tooltip>
  );
}

/**
 * A share icon beside a friend or party code. Windows has no share sheet,
 * so it copies the code's invite link (`https://tabbinotch.com/add/<code>`),
 * which a friend can open with one click, and confirms with a check.
 */
export function PartyShareInvite({ invite, help }: { invite: PartyInvite; help: string }) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1500);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return (
    <IconButton
      symbol={copied ? "check" : "square.and.arrow.up"}
      size={20}
      help={copied ? tr("Copied") : help}
      tint={copied ? "var(--success)" : "var(--accent)"}
      className="party-share"
      onClick={() => void copyText(inviteWebURL(invite)).then((ok) => setCopied(ok))}
    />
  );
}

/** Quiet text button for secondary actions such as Leave. */
export function PartyTextButton({ title, help, busy = false, onClick }: { title: string; help: string; busy?: boolean; onClick: () => void }) {
  return <Pill title={title} help={help} height={20} busy={busy} onClick={onClick} className="party-text-button" />;
}

/** A capsule button in the Party accent; `prominent` fills it for the panel's main call to action. */
export function PartyPillButton({
  title,
  symbol,
  prominent = false,
  busy = false,
  height = 24,
  help,
  onClick,
}: {
  title: string;
  symbol?: string;
  prominent?: boolean;
  busy?: boolean;
  height?: 20 | 24;
  help: string;
  onClick: () => void;
}) {
  return <Pill title={title} symbol={symbol} accent={!prominent} prominent={prominent} busy={busy} height={height} help={help} onClick={onClick} className="party-pill" />;
}

/**
 * A one-line field for a friend or party code: Enter submits, Esc clears.
 * It's cleared after a well-formed code is submitted; a malformed one stays
 * so the store's notice can explain it. While empty it offers a Paste
 * button that pulls the code out of whatever was copied.
 */
export function PartyCodeField({
  placeholder,
  symbol,
  length,
  help,
  onSubmit,
  onFocusChange,
}: {
  placeholder: string;
  symbol: string;
  length: number;
  help: string;
  onSubmit: (text: string) => void;
  onFocusChange?: (focused: boolean) => void;
}) {
  const [text, setText] = useState("");
  const [focused, setFocused] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const send = () => {
    const draft = text;
    if (draft.trim() === "") return;
    onSubmit(draft);
    if (PartyCode.normalize(draft, length) !== undefined) setText("");
  };
  const paste = async () => {
    let pasted: string;
    try {
      pasted = (await navigator.clipboard.readText()).trim();
    } catch {
      input.current?.focus();
      return;
    }
    if (pasted === "") return;
    const code = PartyCode.find(pasted, length);
    setText(code === undefined ? pasted.slice(0, 40) : displayCode(code));
    input.current?.focus();
  };
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") {
      event.preventDefault();
      send();
    } else if (event.key === "Escape") {
      event.preventDefault();
      if (text === "") input.current?.blur();
      else setText("");
    }
  };
  return (
    <Tooltip text={help}>
      <div className="party-code-field" data-focused={focused || undefined} onClick={() => input.current?.focus()}>
        <Icon id={symbol} size={11} className="party-code-field-symbol" />
        <input
          ref={input}
          className="party-code-field-input"
          aria-label={placeholder}
          placeholder={placeholder}
          value={text}
          spellCheck={false}
          autoComplete="off"
          onChange={(event) => setText(event.target.value)}
          onFocus={() => {
            setFocused(true);
            onFocusChange?.(true);
          }}
          onBlur={() => {
            setFocused(false);
            onFocusChange?.(false);
          }}
          onKeyDown={onKeyDown}
        />
        {text === "" ? (
          <Tooltip text={tr("Paste a code you copied")}>
            <button type="button" className="party-paste" onClick={() => void paste()}>
              {tr("Paste")}
            </button>
          </Tooltip>
        ) : (
          <IconButton symbol="arrow.right.circle.fill" size={20} help={tr("Submit")} tint="var(--accent)" className="party-submit" onClick={send} />
        )}
      </div>
    </Tooltip>
  );
}

/** The user's locale for dates. */
export function partyLocale(): string {
  return currentLanguage();
}
