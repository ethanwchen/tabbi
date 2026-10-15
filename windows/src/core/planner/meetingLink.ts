/**
 * Port of MeetingLink: a video-call URL found in a calendar event, so the
 * Up next card can offer a one-click Join button.
 */

export type MeetingProvider = "zoom" | "googleMeet" | "teams";

export interface MeetingLink {
  readonly provider: MeetingProvider;
  /** The join URL, upgraded to https. */
  readonly url: string;
}

/** The provider's name for tooltips, e.g. "Join Zoom call". */
export function meetingProviderName(provider: MeetingProvider): string {
  switch (provider) {
    case "zoom":
      return "Zoom";
    case "googleMeet":
      return "Google Meet";
    case "teams":
      return "Teams";
  }
}

/**
 * Finds the first Zoom, Google Meet or Teams join link in an event.
 *
 * Fields are checked in order of intent: the event's URL field, then the
 * location, then the notes (where invites bury the link among dial-in
 * numbers and other URLs). Other links, such as a Zoom marketing page or a
 * shared doc, are ignored so the button only appears for real calls.
 */
export function detectMeetingLink(fields: { url?: string; location?: string; notes?: string }): MeetingLink | undefined {
  if (fields.url !== undefined) {
    const link = classifyMeetingURL(fields.url.trim());
    if (link !== undefined) return link;
  }
  for (const text of [fields.location, fields.notes]) {
    if (text === undefined) continue;
    for (const url of linksInText(text)) {
      const link = classifyMeetingURL(url);
      if (link !== undefined) return link;
    }
  }
  return undefined;
}

/** Recognizes a single URL as a meeting join link. */
export function classifyMeetingURL(text: string): MeetingLink | undefined {
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return undefined;
  }
  const scheme = url.protocol.toLowerCase();
  if (scheme !== "https:" && scheme !== "http:") return undefined;
  const host = url.hostname.toLowerCase();
  if (host === "") return undefined;
  const path = safeDecode(url.pathname).toLowerCase();
  const secured = scheme === "http:" ? text.replace(/^http:/i, "https:") : text;

  if (host === "zoom.us" || host.endsWith(".zoom.us") || host === "zoomgov.com" || host.endsWith(".zoomgov.com")) {
    /* Meetings (/j/), personal rooms (/my/), webinars (/w/) and /s/ starts. */
    const joinPrefixes = ["/j/", "/my/", "/w/", "/s/"];
    return joinPrefixes.some((prefix) => path.startsWith(prefix)) ? { provider: "zoom", url: secured } : undefined;
  }
  if (host === "meet.google.com") {
    /* Meeting codes look like abc-defg-hij; "/" alone is the landing page. */
    const code = path.slice(1).split("-").filter((piece) => piece !== "");
    const isCode = code.length === 3 && code[0]?.length === 3 && code[1]?.length === 4 && code[2]?.length === 3;
    const isLookup = path.startsWith("/lookup/");
    return isCode || isLookup ? { provider: "googleMeet", url: secured } : undefined;
  }
  if (host === "teams.microsoft.com" && (path.startsWith("/l/meetup-join/") || path.startsWith("/meet/"))) {
    return { provider: "teams", url: secured };
  }
  if (host === "teams.live.com" && path.startsWith("/meet/")) {
    return { provider: "teams", url: secured };
  }
  return undefined;
}

function safeDecode(path: string): string {
  try {
    return decodeURIComponent(path);
  } catch {
    return path;
  }
}

/*
 * A web address in free text: one with a scheme, or a bare host with a path
 * (`meet.google.com/abc-defg-hij`), which invites often write without one.
 */
const LINK_PATTERN = /\bhttps?:\/\/[^\s<>"]+|\b(?:[a-z0-9-]+\.)+[a-z]{2,}\/[^\s<>"]*/gi;
const TRAILING = new Set([".", ",", ";", ":", "!", "?", "'", "*"]);

/**
 * Every URL in free text, in order, the way the Mac's `NSDataDetector`
 * reads invites: angle brackets, quotes and line breaks end a link, and
 * trailing punctuation (or a closing bracket with no opening one) is not
 * part of it. Bare hosts get `http://` in front.
 */
export function linksInText(text: string): string[] {
  const links: string[] = [];
  for (const match of text.matchAll(LINK_PATTERN)) {
    let link = match[0];
    for (;;) {
      const last = link.at(-1);
      if (last === undefined) break;
      if (TRAILING.has(last)) {
        link = link.slice(0, -1);
        continue;
      }
      const pairs: Readonly<Record<string, string>> = { ")": "(", "]": "[", "}": "{" };
      const opening = pairs[last];
      if (opening !== undefined && count(link, opening) < count(link, last)) {
        link = link.slice(0, -1);
        continue;
      }
      break;
    }
    if (link === "") continue;
    links.push(/^https?:\/\//i.test(link) ? link : `http://${link}`);
  }
  return links;
}

function count(text: string, character: string): number {
  return text.split(character).length - 1;
}
