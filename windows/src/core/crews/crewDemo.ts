import { PARTY_BADGE_FOUNDING } from "../party/partyModels";
import { partyPetUpdate } from "../party/partyPetAppearance";
import type { PetAccessory, PetOutfit } from "../pets/petCostume";
import type { PetBreed } from "../pets/petKinds";
import { PetProfile } from "../pets/petProfile";
import type { Instant } from "../time";
import { crewWeekContaining, type CrewBoard, type CrewDetail, type CrewLaurel, type CrewMember, type CrewPet, type CrewSummary } from "./crewModels";
import { crewsState, type CrewsState } from "./crewsState";

/*
 * Port of CrewDemo: the Crew section's screens with sample crews, for demo
 * mode and snapshots. The pets are the Party demo's, and one member hid
 * theirs, so the silhouette shows too. Built relative to `now` so the
 * countdown reads sensibly.
 */

export const CREW_DEMO_SCENARIOS = ["mine", "noCrew", "create", "edit", "find", "lastWeek", "viewing", "invite"] as const;
export type CrewDemoScenario = (typeof CREW_DEMO_SCENARIOS)[number];

function pet(name: string, breed: PetBreed, options: { outfit?: PetOutfit; accessories?: PetAccessory[] } = {}): CrewPet {
  const profile = new PetProfile(name, breed, options);
  const update = partyPetUpdate(profile);
  return {
    petName: update.petName ?? profile.name,
    species: update.species ?? "cat",
    breed: update.breed ?? "tabby",
    colors: update.colors ?? [],
    costume: update.costume ?? "none",
    accessories: update.accessories ?? [],
  };
}

function member(ref: string, name: string, crewPet: CrewPet | undefined, weekMinutes: number, extra: Partial<CrewMember> = {}): CrewMember {
  return { ref, name, pet: crewPet, studyLevel: undefined, badges: [], weekMinutes, owner: false, me: false, ...extra };
}

function summary(fields: Omit<CrewSummary, "description" | "laurel" | "trophies" | "maxMembers"> & Partial<CrewSummary>): CrewSummary {
  return { description: "", laurel: undefined, trophies: 0, maxMembers: 20, ...fields };
}

export function demoNightOwls(now: Instant): CrewDetail {
  const members = [
    member("SAMREF2K7Q", "Sam", pet("Mochi", "orangeTabby", { accessories: ["scarf", "graduationCap"] }), 1_140, { badges: [PARTY_BADGE_FOUNDING], owner: true, me: true }),
    member("MAYAREF4QR", "Maya", pet("Biscuit", "goldenRetriever", { accessories: ["roundGlasses", "cowboyHat"] }), 1_720, { badges: [PARTY_BADGE_FOUNDING] }),
    member("PRJYAREF6K", "Priya", pet("Luna", "siamese", { outfit: "scrubs", accessories: ["surgicalCap"] }), 2_210),
    member("LEQREF9WXC", "Leo", pet("Waffles", "corgi", { outfit: "cozyHoodie", accessories: ["frogHat"] }), 870),
    member("JQNAHREF2P", "Jonah", undefined, 1_360),
  ];
  return {
    summary: summary({
      id: "NGHTQWLS2K",
      name: "Night Owls",
      description: "Late study sessions, quiet focus, good snacks.",
      frame: "shield",
      emblem: "owl",
      color: "indigo",
      visibility: "private",
      laurel: "gold",
      trophies: 3,
      memberCount: members.length,
      weekMinutes: members.reduce((sum, m) => sum + m.weekMinutes, 0),
    }),
    createdAt: now - 40 * 86_400,
    medals: { gold: 2, silver: 1, bronze: 0 },
    rank: 2,
    members,
    mine: true,
    owner: true,
    inviteCode: "W4LNUT7",
    hidden: false,
  };
}

export const DEMO_MED_SQUAD: CrewDetail = {
  summary: summary({
    id: "MEDSQUAD2K",
    name: "Med School Squad",
    description: "Anki every morning.",
    frame: "seal",
    emblem: "cat",
    color: "coral",
    visibility: "public",
    laurel: "silver",
    trophies: 5,
    memberCount: 14,
    weekMinutes: 9_120,
  }),
  createdAt: 1_790_000_000,
  medals: { gold: 1, silver: 3, bronze: 1 },
  rank: 1,
  members: [
    member("AVAREF7K3R", "Ava", pet("Clover", "beagle", { accessories: ["flowerCrown"] }), 2_640, { owner: true }),
    member("NQQRREF7HV", "Noor", pet("Pip", "scottishFold", { accessories: ["chunkyHeadphones"] }), 2_380),
    member("KAJREF8M2D", "Kai", pet("Pepper", "blackCat", { accessories: ["wizardHat"] }), 2_150),
    member("EMMAREF5TB", "Emma", pet("Maple", "dachshund", { outfit: "scrubs" }), 1_950),
  ],
  mine: false,
  owner: false,
  inviteCode: undefined,
  hidden: false,
};

export const DEMO_LOFI: CrewDetail = {
  summary: summary({ id: "LQFJBEATSX", name: "Lofi and Chill", frame: "pennant", emblem: "headphones", color: "mint", visibility: "public", trophies: 1, memberCount: 9, weekMinutes: 5_340 }),
  createdAt: 1_790_000_000,
  medals: { gold: 0, silver: 0, bronze: 0 },
  rank: undefined,
  members: [],
  mine: false,
  owner: false,
  inviteCode: undefined,
  hidden: false,
};

const BOOKWORMS = summary({ id: "BQQKWQRMS2", name: "Bookworms", description: "One more chapter.", frame: "hexagon", emblem: "books", color: "amber", visibility: "public", laurel: "bronze", trophies: 1, memberCount: 20, weekMinutes: 3_980 });
const EARLY_BIRDS = summary({ id: "EARLYB8RDS", name: "Early Birds", frame: "heater", emblem: "bird", color: "sky", visibility: "public", memberCount: 6, weekMinutes: 2_210 });
const QUIET_CORNER = summary({ id: "QUJETC6RNR", name: "Quiet Corner", frame: "star", emblem: "moon", color: "violet", visibility: "public", memberCount: 3, weekMinutes: 640 });

function won(crew: CrewSummary, laurel: CrewLaurel): CrewSummary {
  return { ...crew, laurel };
}

/** Every public demo crew, as Find lists them. */
export function demoCrewResults(): CrewSummary[] {
  return [DEMO_MED_SQUAD.summary, DEMO_LOFI.summary, BOOKWORMS, EARLY_BIRDS, QUIET_CORNER];
}

export function crewsDemo(scenario: CrewDemoScenario, now: Instant): CrewsState {
  const week = crewWeekContaining(now);
  const lastWeek = crewWeekContaining(week.startsAt - 3600);
  const mine = demoNightOwls(now);
  const board: CrewBoard = {
    week,
    top: [
      { rank: 1, minutes: 9_120, crew: DEMO_MED_SQUAD.summary },
      { rank: 2, minutes: mine.summary.weekMinutes, crew: mine.summary },
      { rank: 3, minutes: 5_340, crew: DEMO_LOFI.summary },
    ],
    featured: {
      week: lastWeek,
      entries: [
        { rank: 1, minutes: 11_460, crew: won(mine.summary, "gold") },
        { rank: 2, minutes: 10_020, crew: won(DEMO_MED_SQUAD.summary, "silver") },
        { rank: 3, minutes: 4_410, crew: won(BOOKWORMS, "bronze") },
      ],
    },
  };
  const base = crewsState(now, { week, mine, mineLoaded: true, board, results: demoCrewResults() });
  switch (scenario) {
    case "mine":
      return base;
    case "noCrew":
      return { ...base, mine: undefined };
    case "create":
      return { ...base, mine: undefined, section: "create" };
    case "edit":
      return { ...base, editing: true };
    case "find":
      return { ...base, section: "find" };
    case "lastWeek":
      return { ...base, showsLastWeek: true };
    case "viewing":
      return { ...base, viewing: DEMO_MED_SQUAD };
    case "invite":
      return { ...base, mine: undefined, invite: "LQFJ7RM" };
  }
}
