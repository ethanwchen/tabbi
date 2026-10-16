import { tr } from "../localization/tr";
import type { Instant, Seconds } from "../time";
import type { PartyFriend, PartyMember, PartyPresence, PartyProfile, PartyStatus } from "./partyModels";

/*
 * Port of PartyRoster: how friends and party members read in the Party
 * panel: who's studying, how long they have left, and a stable order that
 * puts active people first.
 */

/** The status to show: the server's presence, or offline when not online or never sent a heartbeat. */
export function rosterStatus(presence: PartyPresence | undefined, online: boolean): PartyStatus {
  if (!online || presence === undefined) return "offline";
  return presence.status;
}

/** Seconds left in the current phase, counted down locally from `phaseEndsAt`; undefined without one. */
export function rosterTimeLeft(presence: PartyPresence | undefined, online: boolean, now: Instant): Seconds | undefined {
  const status = rosterStatus(presence, online);
  if (status !== "studying" && status !== "onBreak") return undefined;
  const end = presence?.phaseEndsAt;
  return end === undefined ? undefined : Math.max(end - now, 0);
}

/** "18 min left", rounding up so a phase reads "1 min left" until it ends. */
export function minutesLeft(seconds: Seconds): string {
  const left = Math.ceil(Math.max(seconds, 0) / 60);
  return left <= 0 ? tr("ending") : tr("%lld min left", left);
}

/** One short line: "Studying · 18 min left", "On a break", "Online" or "Offline". */
export function statusLine(presence: PartyPresence | undefined, online: boolean, now: Instant): string {
  const timeLeft = rosterTimeLeft(presence, online, now);
  const left = timeLeft === undefined ? "" : ` · ${minutesLeft(timeLeft)}`;
  switch (rosterStatus(presence, online)) {
    case "studying":
      return tr("Studying") + left;
    case "onBreak":
      return tr("On a break") + left;
    case "idle":
      return tr("Online");
    case "offline":
      return tr("Offline");
  }
}

/** The same in a narrow row: "Studying · 18m", "Break · 4m", "Online" or "Offline". */
export function compactStatusLine(presence: PartyPresence | undefined, online: boolean, now: Instant): string {
  const timeLeft = rosterTimeLeft(presence, online, now);
  const minutes = timeLeft === undefined ? 0 : Math.ceil(timeLeft / 60);
  const left = minutes > 0 ? ` · ${tr("%lldm", minutes)}` : "";
  switch (rosterStatus(presence, online)) {
    case "studying":
      return tr("Studying") + left;
    case "onBreak":
      return tr("Break") + left;
    case "idle":
      return tr("Online");
    case "offline":
      return tr("Offline");
  }
}

/** The status word alone, for a row too narrow for the count. */
export function compactStatusWord(presence: PartyPresence | undefined, online: boolean): string {
  switch (rosterStatus(presence, online)) {
    case "studying":
      return tr("Studying");
    case "onBreak":
      return tr("Break");
    case "idle":
      return tr("Online");
    case "offline":
      return tr("Offline");
  }
}

/** Study time as "45m" or "1h 20m". */
export function rosterDuration(minutes: number): string {
  const total = Math.max(minutes, 0);
  if (total < 60) return `${total}m`;
  const rest = total % 60;
  const hours = Math.trunc(total / 60);
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`;
}

const RANK: Readonly<Record<PartyStatus, number>> = { studying: 0, onBreak: 1, idle: 2, offline: 3 };

const nameCollator = new Intl.Collator("en", { sensitivity: "accent" });

function order(lhs: PartyProfile, rhs: PartyProfile): number {
  const byName = nameCollator.compare(lhs.name, rhs.name);
  if (byName !== 0) return byName;
  return lhs.code < rhs.code ? -1 : lhs.code > rhs.code ? 1 : 0;
}

/** Friends ordered studying, on a break, online, then offline; by name within each group. */
export function sortedFriends(friends: readonly PartyFriend[]): PartyFriend[] {
  return [...friends].sort((lhs, rhs) => {
    const left = RANK[rosterStatus(lhs.presence, lhs.online)];
    const right = RANK[rosterStatus(rhs.presence, rhs.online)];
    return left !== right ? left - right : order(lhs.profile, rhs.profile);
  });
}

/** Party members with the host first, then by name, so the pets stand in the same place on every refresh. */
export function sortedMembers(members: readonly PartyMember[]): PartyMember[] {
  return [...members].sort((lhs, rhs) => {
    if (lhs.host !== rhs.host) return lhs.host ? -1 : 1;
    return order(lhs.profile, rhs.profile);
  });
}
