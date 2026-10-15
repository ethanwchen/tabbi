/*
 * Icons for the SF Symbol names that kits and descriptors use. SF Symbols are
 * licensed for Apple platforms only, so each name maps to an original SVG
 * drawn on a 24 px grid; an unknown name gets a neutral dot. Phase 2 moves
 * the name table to shared data so both apps agree on imported kits.
 */

import type { ReactElement } from "react";

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2.4,
  strokeLinecap: "round",
  strokeLinejoin: "round",
} as const;

const GLYPHS: Record<string, ReactElement> = {
  timer: (
    <g {...stroke}>
      <circle cx="12" cy="13.5" r="7.5" />
      <path d="M12 13.5V9.5M10 2.75h4M18.25 6.25l1.25-1.25" />
    </g>
  ),
  checklist: (
    <g {...stroke}>
      <path d="M3.5 6.5l1.75 1.75L8.5 5M3.5 15.5l1.75 1.75L8.5 14M12 7h8.5M12 16h8.5" />
    </g>
  ),
  "music.note": (
    <g>
      <ellipse cx="8.25" cy="17.75" rx="3.75" ry="3.25" fill="currentColor" />
      <path d="M11 17.5V3.5c3.5 0 6.5 1.75 7.5 5" {...stroke} />
    </g>
  ),
  sparkles: (
    <g fill="currentColor">
      <path d="M10 4.5c.7 4.6 1.9 5.8 6.5 6.5-4.6.7-5.8 1.9-6.5 6.5-.7-4.6-1.9-5.8-6.5-6.5 4.6-.7 5.8-1.9 6.5-6.5Z" />
      <path d="M18 2.5c.3 1.9.8 2.4 2.7 2.7-1.9.3-2.4.8-2.7 2.7-.3-1.9-.8-2.4-2.7-2.7 1.9-.3 2.4-.8 2.7-2.7Z" />
      <path d="M17.5 15.5c.25 1.5.6 1.85 2.1 2.1-1.5.25-1.85.6-2.1 2.1-.25-1.5-.6-1.85-2.1-2.1 1.5-.25 1.85-.6 2.1-2.1Z" />
    </g>
  ),
  "pawprint.fill": (
    <g fill="currentColor">
      <path d="M12 11.5c3 0 5.75 3.25 5.75 5.75 0 2-1.6 2.75-3 2.75-1.15 0-1.75-.6-2.75-.6s-1.6.6-2.75.6c-1.4 0-3-.75-3-2.75 0-2.5 2.75-5.75 5.75-5.75Z" />
      <ellipse cx="5" cy="10.5" rx="2" ry="2.4" transform="rotate(-20 5 10.5)" />
      <ellipse cx="9.25" cy="5.75" rx="2.1" ry="2.6" transform="rotate(-8 9.25 5.75)" />
      <ellipse cx="14.75" cy="5.75" rx="2.1" ry="2.6" transform="rotate(8 14.75 5.75)" />
      <ellipse cx="19" cy="10.5" rx="2" ry="2.4" transform="rotate(20 19 10.5)" />
    </g>
  ),
};

const FALLBACK = <circle cx="12" cy="12" r="4" fill="currentColor" />;

export function Icon({ symbol, size }: { symbol: string; size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      {GLYPHS[symbol] ?? FALLBACK}
    </svg>
  );
}
