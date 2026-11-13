import { PartyError } from "../party/partyError";
import { PARTY_BADGE_FOUNDING } from "../party/partyModels";
import type { PetAccessory, PetOutfit } from "../pets/petCostume";
import type { PetBreed } from "../pets/petKinds";
import { PetProfile } from "../pets/petProfile";
import type { Instant } from "../time";
import { crewEmblems, resolvedCrewColor, resolvedCrewFrame } from "./crewCatalog";
import {
  crewPetOf,
  crewWeekContaining,
  laurelForRank,
  type CrewBoard,
  type CrewBoardEntry,
  type CrewDetail,
  type CrewFeatured,
  type CrewHallEntry,
  type CrewJoinRequest,
  type CrewLaurel,
  type CrewMedals,
  type CrewMember,
  type CrewPet,
  type CrewSummary,
  type CrewVisibility,
  type CrewWeek,
  type CrewWeekResult,
} from "./crewModels";
import { crewsState, type CrewsState } from "./crewsState";

/*
 * Port of CrewDemo: the Crews screens and states, so demo mode and snapshots
 * can show each one, as the Crews UI spec lists them. Built relative to `now`
 * so the countdown reads sensibly; the crews, people and places match the
 * Mac's demo one for one.
 */

export const CREW_DEMO_SCENARIOS = [
  /** This week: the top 3 and the rest, my crew pinned at 12th. */
  "week",
  /** This week with my crew 2nd, in the top 3. */
  "podium",
  /** This week with two crews tied. */
  "tie",
  /** A quiet start to the week: no minutes yet. */
  "quietWeek",
  /** The board still loading. */
  "loading",
  /** The Hall of Fame, my crew pinned without medals. */
  "hall",
  /** My crew, which I own. */
  "mine",
  /** My crew with people asking to join. */
  "requests",
  /** Not in a crew yet. */
  "noCrew",
  /** Not in a crew, waiting for an owner to let me in. */
  "requested",
  /** Find with public crews. */
  "find",
  /** Find with nothing matching. */
  "findEmpty",
  /** Another crew's page. */
  "crew",
  /** The crest editor, making a new crew. */
  "create",
  /** The crest editor, the owner editing. */
  "edit",
  /** The party server can't be reached. */
  "offline",
  /** A crew invite link waiting to be confirmed. */
  "invite",
] as const;
export type CrewDemoScenario = (typeof CREW_DEMO_SCENARIOS)[number];

export function crewsDemo(scenario: CrewDemoScenario, now: Instant): CrewsState {
  const week = crewWeekContaining(now);
  const data = new CrewDemoData(now, week);
  const state = crewsState(now, {
    section: "week",
    week,
    mine: data.mine(),
    mineLoaded: true,
    board: data.board(),
    hall: data.hall(),
    results: data.publicCrews,
  });
  switch (scenario) {
    case "week":
      return state;
    case "podium":
      return {
        ...state,
        mine: data.mine({ minutes: 2_940 }),
        board: data.board({ myPlace: 2 }),
      };
    case "tie":
      return { ...state, board: data.board({ tie: true }) };
    case "quietWeek":
      return {
        ...state,
        board: {
          week,
          top: [],
          featured: data.featured(),
          rows: [],
          next: undefined,
          crewCount: 0,
          mine: { rank: undefined, minutes: 0 },
        },
      };
    case "loading":
      return { ...state, board: undefined };
    case "hall":
      return { ...state, section: "hall" };
    case "mine":
      return { ...state, section: "mine" };
    case "requests":
      return { ...state, section: "mine", mine: data.mine({ requests: true }) };
    case "noCrew":
      return { ...state, section: "mine", mine: undefined };
    case "requested":
      return {
        ...state,
        section: "mine",
        mine: undefined,
        myRequest: {
          crew: data.crews[1] as CrewSummary,
          requestedAt: now - 3600,
          expiresAt: now + 6 * 86_400,
        },
      };
    case "find":
      return { ...state, section: "find" };
    case "findEmpty":
      return { ...state, section: "find", query: "zebra", results: [] };
    case "crew":
      return {
        ...state,
        pushed: { kind: "crew", crew: data.detail(0), from: "week" },
      };
    case "create":
      return {
        ...state,
        section: "find",
        pushed: { kind: "editor", editing: false, from: "find" },
      };
    case "edit":
      return {
        ...state,
        section: "mine",
        pushed: { kind: "editor", editing: true, from: "mine" },
      };
    case "offline":
      return {
        ...state,
        board: undefined,
        loadError: PartyError.of("unreachable"),
      };
    case "invite":
      return { ...state, section: "mine", mine: undefined, invite: "LQFJ7RM" };
  }
}

function pet(name: string, breed: PetBreed, options: { outfit?: PetOutfit; accessories?: PetAccessory[] } = {}): CrewPet {
  return crewPetOf(new PetProfile(name, breed, options));
}

/** Swift's `unicodeScalars` sum, the demo's member seed. */
function scalarSum(text: string): number {
  let sum = 0;
  for (const scalar of text) sum += scalar.codePointAt(0) ?? 0;
  return sum;
}

/**
 * The emblem a demo crew wears: the named one while the set has it, else one
 * picked from the crew's id (Swift's wrapping `seed &* 31 &+ scalar`), so a
 * new emblem set still shows varied crests with no code change.
 */
export function demoEmblem(preferred: string, id: string): string {
  const emblems = crewEmblems();
  if (emblems.includes(preferred)) return preferred;
  let seed = 0n;
  for (const scalar of id) seed = BigInt.asIntN(64, seed * 31n + BigInt(scalar.codePointAt(0) ?? 0));
  const index = Number((seed < 0n ? -seed : seed) % BigInt(emblems.length));
  return emblems[index] as string;
}

/** The demo crews and people. */
export class CrewDemoData {
  /** How many crews have minutes this week in the demo. */
  static readonly crewCount = 38;
  static readonly myID = "PQMQDQRQ2S";

  /** A little pool of pets the demo crews draw their members from. */
  static readonly pets: readonly (readonly [string, CrewPet])[] = [
    ["Maya", pet("Biscuit", "goldenRetriever", { accessories: ["roundGlasses"] })],
    ["Priya", pet("Luna", "siamese", { outfit: "scrubs" })],
    [
      "Leo",
      pet("Waffles", "corgi", {
        outfit: "cozyHoodie",
        accessories: ["frogHat"],
      }),
    ],
    ["Noor", pet("Pip", "scottishFold", { accessories: ["chunkyHeadphones"] })],
    ["Kai", pet("Pepper", "blackCat", { accessories: ["wizardHat"] })],
    ["Ava", pet("Clover", "beagle", { accessories: ["flowerCrown"] })],
    ["Omar", pet("Nori", "tuxedo")],
    ["Lena", pet("Pudding", "britishShorthair")],
    ["Ahmed", pet("Taco", "grayTabby")],
    ["Emma", pet("Maple", "dachshund", { outfit: "scrubs" })],
    ["Jonah", pet("Bean", "calico")],
    ["Sofia", pet("Mocha", "frenchBulldog")],
  ];

  /** The crews, most minutes first; mine is the eighth (12th on the board). */
  readonly crews: readonly CrewSummary[];

  constructor(
    readonly now: Instant,
    readonly week: CrewWeek,
  ) {
    const crew = (
      id: string,
      name: string,
      frame: string,
      emblem: string,
      color: string,
      visibility: CrewVisibility,
      fields: {
        members: number;
        minutes: number;
        golds: number;
        trophies: number;
        laurel?: CrewLaurel;
        description?: string;
      },
    ): CrewSummary => ({
      id,
      name,
      description: fields.description ?? "",
      frame: resolvedCrewFrame(frame),
      emblem: demoEmblem(emblem, id),
      color: resolvedCrewColor(color).id,
      visibility,
      laurel: fields.laurel,
      trophies: fields.trophies,
      memberCount: fields.members,
      maxMembers: 20,
      weekMinutes: fields.minutes,
      golds: fields.golds,
    });
    this.crews = [
      crew("NGHTQWLS2K", "Night Owls", "shield", "moon", "indigo", "public", {
        members: 18,
        minutes: 3_138,
        golds: 3,
        trophies: 4,
        laurel: "gold",
        description: "Late study sessions, quiet focus.",
      }),
      crew("MEDSQUAD2K", "Med School Grind", "heater", "apple", "coral", "public", {
        members: 20,
        minutes: 2_868,
        golds: 3,
        trophies: 5,
        laurel: "silver",
        description: "Anki every morning.",
      }),
      crew("BJBLRATTEN", "Bibliotheksratten", "seal", "book", "amber", "public", {
        members: 15,
        minutes: 2_646,
        golds: 1,
        trophies: 3,
        laurel: "bronze",
      }),
      crew("LATENJGHT2", "Late Night Legends", "star", "star-smile", "violet", "public", { members: 11, minutes: 2_376, golds: 0, trophies: 2 }),
      crew("DEEPWQRKDQ", "Deep Work Dojo", "hexagon", "pencil", "teal", "public", { members: 9, minutes: 2_310, golds: 1, trophies: 2 }),
      crew("QUJETHQURS", "Quiet Hours", "pennant", "mug", "sky", "private", {
        members: 12,
        minutes: 2_160,
        golds: 0,
        trophies: 1,
      }),
      crew("RAJNYDAYRD", "Rainy Day Readers", "seal", "mushroom", "mint", "public", { members: 7, minutes: 1_890, golds: 0, trophies: 0 }),
      crew(CrewDemoData.myID, "Pomodoro Pals", "shield", "onigiri", "teal", "public", { members: 5, minutes: 1_464, golds: 0, trophies: 0 }),
      crew("EARLYB8RDS", "Early Birds", "heater", "frog", "sky", "public", {
        members: 6,
        minutes: 1_320,
        golds: 0,
        trophies: 0,
      }),
      crew("LQFJBEATSX", "Lofi and Chill", "pennant", "paw", "rose", "public", { members: 14, minutes: 1_110, golds: 0, trophies: 0 }),
    ];
  }

  /** Members for a crew: `count` from the pool, most minutes first. */
  members(crew: CrewSummary, count: number, mine = false): CrewMember[] {
    const seed = scalarSum(crew.id) % 7;
    const pool = CrewDemoData.pets;
    let members: CrewMember[] = Array.from({ length: count }, (_, index) => {
      const [name, crewPet] = pool[(seed + index * 5) % pool.length] as readonly [string, CrewPet];
      return {
        ref: `${crew.id.slice(0, 6)}RF${index}${index}`,
        name,
        pet: crewPet,
        studyLevel: 52 - index * 7,
        badges: [],
        weekMinutes: Math.max(0, Math.trunc(crew.weekMinutes / Math.max(count, 1)) - index * 25),
        owner: index === 0 && !mine,
        me: false,
      };
    });
    if (mine) {
      const me: CrewMember = {
        ref: "SAMREF2K7Q",
        name: "Sam",
        pet: pet("Mochi", "orangeTabby", { accessories: ["scarf"] }),
        studyLevel: 37,
        badges: [PARTY_BADGE_FOUNDING],
        weekMinutes: 570,
        owner: true,
        me: true,
      };
      members = [me, ...members.slice(0, -1)];
      members.sort((a, b) => b.weekMinutes - a.weekMinutes);
    }
    return members;
  }

  pets(crew: CrewSummary): CrewPet[] {
    return this.members(crew, 3).flatMap((member) => (member.pet === undefined ? [] : [member.pet]));
  }

  /** My crew, Pomodoro Pals, which I own. */
  mine(options: { minutes?: number; requests?: boolean } = {}): CrewDetail {
    const base = this.crews[7] as CrewSummary;
    const summary = options.minutes === undefined ? base : { ...base, weekMinutes: options.minutes };
    const pool = CrewDemoData.pets;
    const requests: CrewJoinRequest[] = options.requests
      ? [
          {
            ref: "AVAREQ7K3R",
            name: "Ava",
            pet: pool[5]?.[1],
            badges: [],
            requestedAt: this.now - 5400,
            expiresAt: this.now + 6 * 86_400,
          },
          {
            ref: "QMARREQ8M2",
            name: "Omar",
            pet: pool[6]?.[1],
            badges: [],
            requestedAt: this.now - 600,
            expiresAt: this.now + 7 * 86_400,
          },
        ]
      : [];
    return {
      summary,
      createdAt: this.now - 40 * 86_400,
      medals: { gold: 0, silver: 0, bronze: 0 },
      rank: options.minutes === undefined ? 12 : 2,
      members: this.members(summary, 5, true),
      mine: true,
      owner: true,
      inviteCode: "W4LNUT7",
      hidden: false,
      history: this.history([14, 18, 21]),
      crewCount: CrewDemoData.crewCount,
      requests,
    };
  }

  /** Another crew's page. */
  detail(index: number): CrewDetail {
    const summary = this.crews[index] ?? (this.crews[0] as CrewSummary);
    const medals: CrewMedals = {
      gold: summary.golds,
      silver: 1,
      bronze: summary.trophies - summary.golds - 1 > 0 ? 1 : 0,
    };
    return {
      summary,
      createdAt: this.now - 120 * 86_400,
      medals,
      rank: index + 1,
      members: this.members(summary, Math.min(summary.memberCount, 8)),
      mine: false,
      owner: false,
      inviteCode: undefined,
      hidden: false,
      history: this.history([1, 2, 1], [3_210, 3_120, 3_390]),
      crewCount: CrewDemoData.crewCount,
      requests: [],
    };
  }

  /** A crew's page by id: mine, or one of the demo crews. */
  detailFor(id: string): CrewDetail {
    if (id === CrewDemoData.myID) return this.mine();
    return this.detail(
      Math.max(
        0,
        this.crews.findIndex((crew) => crew.id === id),
      ),
    );
  }

  history(places: readonly number[], minutes: readonly number[] = [1_380, 1_102, 980]): CrewWeekResult[] {
    return places.map((place, index) => ({
      week: crewWeekContaining(this.week.startsAt - (index + 1) * 7 * 86_400),
      place,
      minutes: minutes[index] ?? 0,
      medal: laurelForRank(place),
    }));
  }

  /** The weekly board; `myPlace` moves my crew up, `tie` ties fifth and sixth. */
  board(options: { myPlace?: number; tie?: boolean } = {}): CrewBoard {
    const ordered = [...this.crews];
    if (options.myPlace !== undefined) {
      const [mine] = ordered.splice(7, 1);
      ordered.splice(options.myPlace - 1, 0, {
        ...(mine as CrewSummary),
        weekMinutes: 2_940,
      });
    }
    if (options.tie)
      ordered[5] = {
        ...(ordered[5] as CrewSummary),
        weekMinutes: (ordered[4] as CrewSummary).weekMinutes,
      };
    const entries: CrewBoardEntry[] = [];
    ordered.forEach((crew, index) => {
      let rank = index + 1;
      const previous = entries[entries.length - 1];
      if (previous !== undefined && previous.minutes === crew.weekMinutes) rank = previous.rank;
      /* Ranks past the shown crews jump, as on a board of 38. */
      if (index >= 7 && options.myPlace === undefined) rank = index + 5;
      entries.push({
        rank,
        minutes: crew.weekMinutes,
        crew,
        pets: index < 3 ? this.pets(crew) : [],
        tiedWith: [],
      });
    });
    const tied = entries.map((entry) => ({
      ...entry,
      tiedWith: entries.filter((other) => other.rank === entry.rank && other.crew.id !== entry.crew.id).map((other) => other.crew.name),
    }));
    const mine = tied.find((entry) => entry.crew.id === CrewDemoData.myID);
    return {
      week: this.week,
      top: tied.slice(0, 3),
      featured: this.featured(),
      rows: tied.slice(3),
      next: undefined,
      crewCount: CrewDemoData.crewCount,
      mine: mine === undefined ? undefined : { rank: mine.rank, minutes: mine.minutes },
    };
  }

  featured(): CrewFeatured {
    const last = crewWeekContaining(this.week.startsAt - 3600);
    return {
      week: last,
      entries: this.crews.slice(0, 3).map((crew, index) => ({
        rank: index + 1,
        minutes: 3_400 - index * 200,
        crew,
        pets: this.pets(crew),
        tiedWith: [],
      })),
    };
  }

  /** The Hall of Fame: the medalled crews in Olympic order. */
  hall(): CrewHallEntry[] {
    const medals: readonly (readonly [number, CrewMedals])[] = [
      [0, { gold: 3, silver: 1, bronze: 0 }],
      [1, { gold: 3, silver: 0, bronze: 2 }],
      [4, { gold: 1, silver: 2, bronze: 1 }],
      [2, { gold: 1, silver: 1, bronze: 1 }],
      [3, { gold: 0, silver: 2, bronze: 0 }],
      [5, { gold: 0, silver: 0, bronze: 1 }],
    ];
    return medals.map(([index, tally], place) => {
      const crew = this.crews[index] as CrewSummary;
      return {
        rank: place + 1,
        medals: tally,
        reachedAt: this.week.startsAt - place * 7 * 86_400,
        crew,
        pets: place < 3 ? this.pets(crew) : [],
      };
    });
  }

  /** Find's list: the public crews. */
  get publicCrews(): CrewSummary[] {
    return this.crews.filter((crew) => crew.visibility === "public" && crew.id !== CrewDemoData.myID);
  }
}
