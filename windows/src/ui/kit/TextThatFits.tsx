/*
 * The Mac's horizontal `ViewThatFits` over a few wordings of one line:
 * shows the first candidate that fits the width it gets, longest first
 * ("Add a task for tomorrow…", "Add a task…", "Add…"), so a narrow spot
 * shortens its words instead of cutting them. The last candidate always
 * shows, whatever the width. Candidates are measured in a layout pass
 * before paint and again when the container or the words change.
 */

import { useLayoutEffect, useRef, useState, type CSSProperties } from "react";

export interface TextThatFitsProps {
  /** The wordings to try, longest first. */
  readonly candidates: readonly string[];
  readonly className?: string;
  readonly style?: CSSProperties;
}

/** The index of the first candidate no wider than `available`, or the last one. */
export function candidateThatFits(widths: readonly number[], available: number): number {
  for (let index = 0; index < widths.length; index++) {
    if ((widths[index] ?? 0) <= available + 0.5) return index;
  }
  return Math.max(widths.length - 1, 0);
}

export function TextThatFits({ candidates, className, style }: TextThatFitsProps) {
  const container = useRef<HTMLSpanElement>(null);
  const [chosen, setChosen] = useState(0);
  const key = candidates.join("\u0000");

  useLayoutEffect(() => {
    const element = container.current;
    if (!element) return;
    const measure = () => {
      const probes = [...element.querySelectorAll<HTMLElement>(":scope > .kit-fits-probe")];
      const widths = probes.map((probe) => probe.getBoundingClientRect().width);
      setChosen(candidateThatFits(widths, element.clientWidth));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [key]);

  return (
    <span ref={container} className={["kit-fits", className].filter(Boolean).join(" ")} style={style}>
      {candidates.map((candidate, index) => (
        <span key={index} className="kit-fits-probe" aria-hidden="true">
          {candidate}
        </span>
      ))}
      <span className="kit-fits-shown">{candidates[Math.min(chosen, candidates.length - 1)] ?? ""}</span>
    </span>
  );
}
