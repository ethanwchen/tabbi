import type { PetAccessory } from "../pets/petCostume";
import type { PetBreed } from "../pets/petKinds";
import { PetPointsRules } from "../pets/petPointsRules";
import { PetProfile } from "../pets/petProfile";
import type { Instant } from "../time";
import { PartyError } from "./partyError";
import {
  PARTY_BADGE_FOUNDING,
  partyProfile,
  type Party,
  type PartyFriend,
  type PartyMember,
  type PartyPresence,
  type PartyProfile,
  type PartyStatus,
} from "./partyModels";
import type { PartyBlockedUser } from "./partyModeration";
import { partyPetUpdate } from "./partyPetAppearance";
import { presenceDayString } from "./partyPresenceTracker";
import { PartySessionCompletion } from "./partySessionTracker";
import { partySettings } from "./partySettings";
import { PartyState } from "./partyState";
import { PartyTeamCelebration } from "./partyTeamCelebration";

/*
 * Port of PartyDemo: sample data for demo mode and snapshots. I host a
 * party with two friends on a shared session, one more friend is in another
 * party I could join, the rest cover every status, and Noor asked to be
 * friends. Maya and I are Founding Members, so the badge shows. Everyone
 * wears a hat the server could not carry before catalog version 2, and
 * nobody wears a cape (no capes in demo art). Built relative to `now`.
 */

/** A profile as the server would return it for `pet`. */
function demoProfile(code: string, name: string, pet: PetProfile, badges: readonly string[] = []): PartyProfile {
  const update = partyPetUpdate(pet);
  return partyProfile({
    code,
    name,
    petName: update.petName ?? pet.name,
    species: update.species ?? "cat",
    breed: update.breed ?? "tabby",
    colors: update.colors ?? [],
    costume: update.costume ?? "none",
    accessories: update.accessories ?? [],
    badges,
  });
}

function pet(name: string, breed: PetBreed, accessories: readonly PetAccessory[], outfit: "none" | "scrubs" | "cozyHoodie" = "none"): PetProfile {
  return new PetProfile(name, breed, { outfit, accessories });
}

/** The Party tab's screens, so demo snapshots can show each one. Port of PartyDemoScenario. */
export const PARTY_DEMO_SCENARIOS = [
  "hosting",
  "guest",
  "member",
  "celebrating",
  "crowded",
  "lobby",
  "noFriends",
  "requests",
  "reporting",
  "refusedName",
  "connecting",
  "unreachable",
  "invalidServer",
  "banned",
  "ageCheck",
  "tooYoung",
] as const;
export type PartyDemoScenario = (typeof PARTY_DEMO_SCENARIOS)[number];

/** The default demo state at `now`, with days in `timeZone`. */
export function partyDemoState(now: Instant, timeZone: string): PartyState {
  const day = presenceDayString(now, timeZone);
  const presence = (status: PartyStatus, minutesLeft?: number, today = 0, streak = 0): PartyPresence => ({
    status,
    method: status === "studying" || status === "onBreak" ? "pomodoro" : undefined,
    phaseEndsAt: minutesLeft === undefined ? undefined : now + minutesLeft * 60,
    sessionMinutes: status === "studying" ? 25 : 0,
    todayMinutes: today,
    streakDays: streak,
    day,
    lastSeen: now - 30,
  });
  const since = now - 14 * 86_400;

  const me = demoProfile("K7QW2MZD", "Sam", pet("Mochi", "orangeTabby", ["scarf", "graduationCap"]), [PARTY_BADGE_FOUNDING]);
  const maya = demoProfile("M4YA8QRT", "Maya", pet("Biscuit", "goldenRetriever", ["roundGlasses", "cowboyHat"]), [PARTY_BADGE_FOUNDING]);
  const priya = demoProfile("PR1YA6KD", "Priya", pet("Luna", "siamese", ["surgicalCap"], "scrubs"));
  const leo = demoProfile("LE0J9WXC", "Leo", pet("Waffles", "corgi", ["frogHat"], "cozyHoodie"));
  const jonah = demoProfile("J0NAH2PF", "Jonah", pet("Pepper", "blackCat", ["wizardHat"]));
  const noor = demoProfile("N4ZR7HVB", "Noor", pet("Pip", "scottishFold", ["chunkyHeadphones"]));

  const party: Party = {
    code: "Q4RT8M",
    host: me.code,
    createdAt: now - 40 * 60,
    lastActive: now,
    expiresAt: now + 4 * 3600,
    maxMembers: 8,
    session: { method: "pomodoro", phaseEndsAt: now + 18 * 60 + 20, startedAt: now - 6 * 60 - 40 },
    members: [
      { profile: me, joinedAt: now - 40 * 60, host: true, presence: presence("studying", 18.3, 95, 6), online: true },
      { profile: maya, joinedAt: now - 35 * 60, host: false, presence: presence("studying", 18.3, 140, 12), online: true },
      { profile: priya, joinedAt: now - 12 * 60, host: false, presence: presence("onBreak", 3.5, 60, 3), online: true },
    ],
  };
  const friends: PartyFriend[] = [
    { profile: maya, since, presence: presence("studying", 18.3, 140, 12), online: true, party: { code: party.code, size: 3 } },
    { profile: priya, since, presence: presence("onBreak", 3.5, 60, 3), online: true, party: { code: party.code, size: 3 } },
    { profile: leo, since, presence: presence("studying", 41, 30, 2), online: true, party: { code: "ZX7M2P", size: 2 } },
    { profile: jonah, since, presence: undefined, online: false, party: undefined },
  ];
  return PartyState.loaded(me, friends, party, [{ profile: noor, since: now - 2 * 3600 }]);
}

/** Someone who isn't a friend in the demo yet: the person a demo friend link adds. */
export function partyDemoInvitee(): PartyProfile {
  return demoProfile("AVA7K3RN", "Ava", pet("Clover", "beagle", ["flowerCrown"]));
}

/** The age check's saved answer behind a demo screen: unanswered, about 18 months away, or long past. */
export function demoAgeEligibleFrom(scenario: PartyDemoScenario, now: Instant): Instant | undefined {
  switch (scenario) {
    case "ageCheck":
      return undefined;
    case "tooYoung":
      return now + 540 * 86_400;
    default:
      return Number.NEGATIVE_INFINITY;
  }
}

/** The default demo reshaped into `scenario`. */
export function partyDemoScenario(scenario: PartyDemoScenario, now: Instant, timeZone: string): PartyState {
  const base = partyDemoState(now, timeZone);
  const me = base.profile;
  const party = base.party;
  if (me === undefined || party === undefined) return base;
  const oldEnough = partySettings({ ageEligibleFrom: Number.NEGATIVE_INFINITY });
  switch (scenario) {
    case "hosting":
    case "reporting":
    case "refusedName":
      return base;
    case "guest":
    case "member":
    case "celebrating": {
      const host = party.members[1]?.profile.code ?? party.host;
      const members = party.members.map((member) => ({ ...member, host: member.profile.code === host }));
      const reshaped: Party = { ...party, host, members, session: scenario === "member" ? party.session : undefined };
      return PartyState.loaded(me, base.friends, reshaped, base.incomingRequests);
    }
    case "crowded": {
      const template = party.members[1];
      if (template === undefined) return base;
      const extra: [string, string, PetBreed, PetAccessory][] = [
        ["Ana", "Pretzel", "corgi", "partyHat"],
        ["Ben", "Olive", "tuxedo", "tinyCrown"],
        ["Chloe", "Noodle", "beagle", "flowerCrown"],
        ["Dev", "Tofu", "frenchBulldog", "chefHat"],
        ["Eli", "Smudge", "grayTabby", "pirateHat"],
      ];
      const added = extra.map(([name, petName, breed, accessory], index): PartyMember => {
        const even = index % 2 === 0;
        const presence = template.presence === undefined
          ? undefined
          : { ...template.presence, status: (even ? "idle" : "studying") as PartyStatus, phaseEndsAt: even ? undefined : now + (10 + index) * 60 };
        return { ...template, profile: demoProfile(`CRWD${index + 2}ABZ`, name, pet(petName, breed, [accessory])), host: false, presence };
      });
      return PartyState.loaded(me, base.friends, { ...party, session: undefined, members: [...party.members, ...added] }, base.incomingRequests);
    }
    case "lobby":
      return PartyState.loaded(me, base.friends, undefined, base.incomingRequests);
    case "requests": {
      const kai = demoProfile("K4AZ9TMW", "Kai", pet("Tango", "dachshund", ["backwardsCap"]));
      return PartyState.loaded(me, [], undefined, base.incomingRequests, [{ profile: kai, since: now - 26 * 3600 }]);
    }
    case "noFriends":
      return PartyState.loaded(me, [], undefined);
    case "connecting":
      return new PartyState(oldEnough, now);
    case "unreachable": {
      const state = new PartyState(oldEnough, now);
      state.didFailToConnect(PartyError.of("unreachable"));
      return state;
    }
    case "invalidServer":
      return new PartyState(partySettings({ serverText: "http://tabbi.example.com" }), now);
    case "banned": {
      const state = new PartyState(oldEnough, now);
      state.didFailToConnect(PartyError.of("banned"));
      return state;
    }
    case "ageCheck":
    case "tooYoung":
      return new PartyState(partySettings({ ageEligibleFrom: demoAgeEligibleFrom(scenario, now) }), now);
  }
}

/** The celebration the `celebrating` demo shows: a 25-minute session with two friends, just finished. */
export function partyDemoCelebration(now: Instant): PartyTeamCelebration {
  const completion = new PartySessionCompletion({ method: "pomodoro", joinedAt: now - 25 * 60, endedAt: now, friendCount: 2, hostName: "Maya" });
  return new PartyTeamCelebration(completion, PetPointsRules.sharedPoints(25, 2), now, "Mochi");
}

/** The Blocked list for demo mode and snapshots: one person, blocked a few days ago. */
export function partyDemoBlocked(now: Instant): PartyBlockedUser[] {
  return [{ code: "R7LEY5TV", name: "Riley", petName: "Noodle", since: now - 3 * 86_400 }];
}
