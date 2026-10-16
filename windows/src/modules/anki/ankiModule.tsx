import { lazyView } from "../../app/lazyView";
import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { derived } from "../../app/store";
import { ANKI_CONNECT_ENDPOINT } from "../../core/anki/ankiConnectClient";
import { ANKI_STUDY_ACTION_ID } from "../../core/anki/ankiSummary";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import type { ModuleProvision } from "../../core/providers/moduleProvision";
import { ANKI_SNAPSHOT_STATES, AnkiStore } from "./ankiStore";

/* The views load on first use; the store and descriptor stay eager. */
const AnkiConnectSetupView = lazyView(() => import("./AnkiPanel"), "AnkiConnectSetupView");
const AnkiPanel = lazyView(() => import("./AnkiPanel"), "AnkiPanel");

/* Port of AnkiModule: cards due today and the review streak, from AnkiConnect on this PC. */
export const ANKI_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.anki,
    /* A product name, the same in every language. */
    title: "Anki",
    symbol: "rectangle.stack.fill",
    category: MODULE_CATEGORIES.study,
    accent: { red: 0.36, green: 0.62, blue: 1.0 },
    network: [{ host: new URL(ANKI_CONNECT_ENDPOINT).hostname, purpose: "your decks through AnkiConnect" }],
    setup: [ONBOARDING_SETUP_STEPS.anki],
  },
  {
    summary: () => tr("Cards due today and your daily review streak."),
  },
);

/** Two provisions with the same progress goal are the same provision, so the hub only re-merges real changes. */
function sameProvision(a: ModuleProvision, b: ModuleProvision): boolean {
  if (a.progress.length !== b.progress.length) return false;
  return a.progress.every((item, index) => {
    const other = b.progress[index];
    return other !== undefined && item.equals(other);
  });
}

export const AnkiModule = defineModule(
  ANKI_DESCRIPTOR,
  (context) => {
    const store = new AnkiStore(context);
    function Panel() {
      return <AnkiPanel store={store} />;
    }
    function SetupView() {
      return <AnkiConnectSetupView store={store} accent={ANKI_DESCRIPTOR.accent} />;
    }
    return {
      store,
      Panel,
      /* Onboarding's Anki step: connect to AnkiConnect without leaving the island. */
      setupView: (step) => (step.id === ONBOARDING_SETUP_STEPS.anki.id ? SetupView : undefined),
      /* Today's reviews as a progress goal for Today and the ticker; re-read at each rollover. */
      provision: derived([store], () => store.provision(), sameProvision),
      start: () => store.start(),
      stop: () => store.stop(),
      /* The reviews goal's "Study <deck>", clicked in Today or the closed island. */
      perform: (action) => {
        if (action.id === ANKI_STUDY_ACTION_ID) store.studyFromShared();
      },
      showSnapshotState: (state) => store.showSnapshotState(state),
    };
  },
  { snapshotStates: ANKI_SNAPSHOT_STATES },
);
