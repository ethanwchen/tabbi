/*
 * The closed pill's preview items the snapshot harness draws, one per kind
 * of live activity, from demo data (the Mac's SnapshotRenderer previews).
 * The pets wear no cape: demo art never does.
 */

import { MODULE_IDS } from "../../../core/modules/moduleId";
import type { PetBreed } from "../../../core/pets/petKinds";
import { PetProfile } from "../../../core/pets/petProfile";
import { ProgressItem } from "../../../core/providers/progressItem";
import { TickerHighlight } from "../../../core/providers/tickerHighlight";
import { tickerFocus, tickerMeeting, tickerPet, type TickerItem } from "../../../core/ticker/tickerItem";

function pet(name: string, breed: PetBreed): PetProfile {
  return new PetProfile(name, breed);
}

/* A name the user chose, so the pill shows it (an app-given name stays hidden). */
const PUMPKIN = pet("Pumpkin", "orangeTabby");

export const DEMO_PREVIEWS: Readonly<Record<string, () => TickerItem>> = {
  focus: () => ({
    type: "focus",
    focus: tickerFocus({ phase: "focus", time: 18 * 60 + 42, isRunning: true, source: MODULE_IDS.focus, length: 25 * 60 }),
  }),
  "focus-paused": () => ({
    type: "focus",
    focus: tickerFocus({ phase: "focus", time: 12 * 60 + 5, isRunning: false, source: MODULE_IDS.study, length: 50 * 60 }),
  }),
  break: () => ({
    type: "focus",
    focus: tickerFocus({ phase: "rest", time: 4 * 60 + 10, isRunning: true, source: MODULE_IDS.focus, length: 5 * 60 }),
  }),
  meeting: () => ({
    type: "meeting",
    meeting: tickerMeeting({ title: "Design review", timing: { kind: "startsIn", minutes: 12 }, canJoin: false }),
  }),
  "meeting-join": () => ({
    type: "meeting",
    meeting: tickerMeeting({
      title: "Standup",
      timing: { kind: "startsIn", minutes: 4 },
      canJoin: true,
      link: { provider: "zoom", url: "https://zoom.us/j/123456789" },
    }),
  }),
  nowPlaying: () => ({ type: "nowPlaying" }),
  tasks: () => ({ type: "tasks", remaining: 3 }),
  progress: () => ({
    type: "progress",
    item: new ProgressItem({ id: "due", source: MODULE_IDS.anki, title: "Anki reviews", completed: 36, target: 120, unit: "cards" }),
  }),
  highlight: () => ({
    type: "highlight",
    highlight: new TickerHighlight({ id: "5h", source: MODULE_IDS.claudeUsage, text: "5h 86%", summary: "Claude: 86% of the 5-hour limit used", tone: "accent", priority: 10 }),
  }),
  pet: () => ({ type: "pet", pet: tickerPet({ profile: PUMPKIN, mood: "awake" }) }),
  "pet-asleep": () => ({ type: "pet", pet: tickerPet({ profile: PUMPKIN, mood: "asleep" }) }),
  party: () => ({
    type: "party",
    party: {
      pets: [
        { id: "me", name: "Pumpkin", pet: PUMPKIN, isAway: false },
        { id: "maya", name: "Biscuit", pet: pet("Biscuit", "goldenRetriever"), isAway: false },
        { id: "priya", name: "Luna", pet: pet("Luna", "siamese"), isAway: false },
      ],
      memberCount: 3,
    },
  }),
};
