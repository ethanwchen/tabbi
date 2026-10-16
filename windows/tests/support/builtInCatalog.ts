import { KitSettingsSchema, kitSetting } from "../../src/core/kits/kitSettingsSchema";
import { ModuleCatalog } from "../../src/core/modules/moduleCatalog";
import { CLAUDE_ACCENT, MODULE_CATEGORIES, moduleDescriptor } from "../../src/core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../src/core/modules/moduleId";
import { ModuleLayout } from "../../src/core/modules/moduleLayout";
import { ONBOARDING_SETUP_STEPS } from "../../src/core/onboarding/onboardingSetupStep";

/*
 * Port of the Swift tests' BuiltInCatalog fixture: the built-in modules as
 * the Mac's ModuleList declares them, in the same order. The kit settings
 * schemas of other areas (Today's plan, focus sounds, study methods, the
 * pet) are written out here as plain data with the values their Swift
 * types give, so kit validation can be tested before those areas exist.
 */

const studyMethods = [
  "pomodoro",
  "fiftyTwoSeventeen",
  "ultradian",
  "flowtime",
  "ankiSprint",
  "questionBlock",
  "custom",
  "timer",
];

export const PET_BREEDS = [
  "orangeTabby",
  "grayTabby",
  "blackCat",
  "whiteCat",
  "tuxedo",
  "calico",
  "siamese",
  "britishShorthair",
  "sphynx",
  "scottishFold",
  "goldenRetriever",
  "labrador",
  "frenchBulldog",
  "corgi",
  "dachshund",
  "beagle",
  "poodle",
  "shihTzu",
];

export const STUDY_METHODS = studyMethods;

const todayPlanSchema = new KitSettingsSchema({
  planMode: kitSetting.choice(["local", "claude", "study"]),
  reviewsFirst: kitSetting.bool,
  eventBufferMinutes: kitSetting.number(0, 240),
  studyBlockTitle: kitSetting.text(120),
  secondsPerCard: kitSetting.number(1, 600),
  upNextEvents: kitSetting.text(80),
  dayEndHour: kitSetting.number(0, 22),
  sampleDay: kitSetting.choice(["work", "medicine"]),
});

const focusSchema = new KitSettingsSchema({
  sounds: kitSetting.list(
    kitSetting.object({
      sound: kitSetting.choice(["brown", "pink", "white", "rain", "fireplace", "cafe"]),
      level: kitSetting.number(0, 1),
    }),
    3,
  ),
});

const methodChoice = kitSetting.choice(studyMethods);
const studySchema = new KitSettingsSchema({
  methods: kitSetting.list(methodChoice, studyMethods.length),
  method: methodChoice,
  dailyGoalMinutes: kitSetting.number(15, 720),
});

const closetSchema = new KitSettingsSchema({
  coachLines: kitSetting.object(
    Object.fromEntries(["distraction", "offerPause", "idleCheck", "autoPause"].map((kind) => [kind, kitSetting.lines(64, 20)])),
  ),
  pet: kitSetting.object({ breed: kitSetting.choice(PET_BREEDS), name: kitSetting.text(16) }),
});

export const BUILT_IN_CATALOG = new ModuleCatalog([
  moduleDescriptor({
    id: MODULE_IDS.spotify,
    title: "Now Playing",
    symbol: "music.note",
    category: MODULE_CATEGORIES.media,
    accent: { red: 0.12, green: 0.84, blue: 0.38 },
    permissions: ["automation"],
    network: [{ host: "i.scdn.co", purpose: "Spotify album artwork" }],
  }),
  moduleDescriptor({
    id: MODULE_IDS.system,
    title: "System",
    symbol: "cpu",
    category: MODULE_CATEGORIES.system,
    accent: { red: 0.35, green: 0.78, blue: 1.0 },
  }),
  moduleDescriptor({
    id: MODULE_IDS.claudeUsage,
    title: "AI Usage",
    symbol: "gauge.with.dots.needle.67percent",
    category: MODULE_CATEGORIES.ai,
    accent: CLAUDE_ACCENT,
    permissions: ["claudeCLI"],
    highlightTitle: "AI usage above 80%",
  }),
  moduleDescriptor({
    id: MODULE_IDS.planner,
    title: "Today",
    symbol: "checklist",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.66, green: 0.55, blue: 1.0 },
    permissions: ["calendars", "notifications"],
    kitSettings: todayPlanSchema,
    setup: [ONBOARDING_SETUP_STEPS.calendar],
  }),
  moduleDescriptor({
    id: MODULE_IDS.claudeAsk,
    title: "Ask AI",
    symbol: "sparkles",
    category: MODULE_CATEGORIES.ai,
    accent: CLAUDE_ACCENT,
    permissions: ["claudeCLI"],
  }),
  moduleDescriptor({
    id: MODULE_IDS.focus,
    title: "Focus",
    symbol: "hourglass",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.3, green: 0.84, blue: 0.76 },
    permissions: ["notifications"],
    kitSettings: focusSchema,
  }),
  moduleDescriptor({
    id: MODULE_IDS.study,
    title: "Timer",
    symbol: "timer",
    category: MODULE_CATEGORIES.study,
    accent: { red: 1.0, green: 0.62, blue: 0.26 },
    ownsFocusClock: true,
    kitSettings: studySchema,
    setup: [ONBOARDING_SETUP_STEPS.studyMethod],
  }),
  moduleDescriptor({
    id: MODULE_IDS.anki,
    title: "Anki",
    symbol: "rectangle.stack.fill",
    category: MODULE_CATEGORIES.study,
    accent: { red: 0.36, green: 0.62, blue: 1.0 },
    network: [{ host: "127.0.0.1", purpose: "your decks through AnkiConnect" }],
    setup: [ONBOARDING_SETUP_STEPS.anki],
  }),
  moduleDescriptor({
    id: MODULE_IDS.party,
    title: "Party",
    symbol: "person.3.fill",
    category: MODULE_CATEGORIES.study,
    accent: { red: 1.0, green: 0.42, blue: 0.62 },
    network: [{ host: "friends.example.com", purpose: "your presence and parties" }],
    setup: [ONBOARDING_SETUP_STEPS.party],
  }),
  moduleDescriptor({
    id: MODULE_IDS.closet,
    title: "Closet",
    symbol: "pawprint.fill",
    category: MODULE_CATEGORIES.fun,
    accent: { red: 0.98, green: 0.8, blue: 0.3 },
    kitSettings: closetSchema,
    setup: [ONBOARDING_SETUP_STEPS.pet],
  }),
]);

/** A layout against the built-in catalog. */
export function builtInLayout(order: readonly string[], disabled: Iterable<string> = []): ModuleLayout {
  return new ModuleLayout(order, disabled, BUILT_IN_CATALOG);
}

/** The five tabs Tabbi first shipped with, every other module parked off. A fixed layout for tests. */
export function defaultTestLayout(): ModuleLayout {
  return builtInLayout(["spotify", "system", "claudeUsage", "planner", "claudeAsk"]);
}
