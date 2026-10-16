/*
 * Port of ClosetModule: the pet's page, opened from the paw at the far
 * right of the open island's header (or P) rather than a tab. Preview the
 * study pet, rename and recolor it, and dress it in items unlocked with
 * study points. The pet itself is the shared `studyPet`, which this module
 * edits and hands the coach, so the island, the coach, Study and Party show
 * the same pet. The pet's study coach, the daily reminder, the seasonal
 * greeter and the weekly recap run while this module is on, and its
 * Settings pane shows with it. The pet is shared as a provider, so the
 * closed island shows it too.
 */

import { lazyView } from "../../app/lazyView";
import type { ComponentType } from "react";
import { defineModule, type SetupStepProps } from "../../app/module";
import { mapped } from "../../app/store";
import { currentLanguage } from "../../core/localization/tr";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { accessoryItem } from "../../core/pets/petItem";
import { PET_ACCESSORIES, type PetAccessory } from "../../core/pets/petCostume";
import { moduleProvision } from "../../core/providers/moduleProvision";
import { resolveTheme } from "../../core/themes/themeCatalog";
import { focusTimer } from "../focus/focusServices";
import { PetCoachController } from "./coach/petCoachController";
import { CLOSET_DESCRIPTOR } from "./closetDescriptor";
import { studyPet, surpriseGifts } from "./closetServices";
import type { ClosetSection } from "./closetStore";
import { recapTakeover } from "./recap/RecapCard";
import { RecapMoment } from "./recap/recapMoment";
import { copyRecapImage, saveRecapImage } from "./recap/recapSharing";
import { RecapStore } from "./recap/recapStore";
import { SeasonalEventGreeter } from "./seasonalEventGreeter";
import { StudyReminderScheduler } from "./studyReminderScheduler";

/* The views load on first use; the store and descriptor stay eager. */
const PetCoachSettingsPane = lazyView(() => import("./coach/PetCoachSettingsPane"), "PetCoachSettingsPane");
const ClosetPanel = lazyView(() => import("./ClosetPanel"), "ClosetPanel");
const ClosetSetupView = lazyView(() => import("./ClosetSetupView"), "ClosetSetupView");

export { CLOSET_DESCRIPTOR, CLOSET_KIT_SCHEMA } from "./closetDescriptor";

/** The Closet's other sections and its longest lines (the Mac's `ClosetShot`s), plus the recap card in a heavy and a light week. */
const SNAPSHOT_STATES = [
  "wardrobe",
  "limited",
  "streak",
  "look",
  "weeks",
  "founding",
  "founding-unearned",
  "founding-unearned-scrolling",
  "long-name",
  "long-name-scrolling",
  "animated",
  "recap-heavy",
  "recap-light",
] as const;

interface SnapshotShot {
  readonly tryingOn?: PetAccessory;
  readonly foundingMember?: boolean;
  readonly name?: string;
  readonly scrolled?: number;
}

export const ClosetModule = defineModule(
  CLOSET_DESCRIPTOR,
  (context) => {
    const store = studyPet(context);
    const gifts = surpriseGifts(context);
    const recaps = new RecapStore(context);
    const progress = mapped(context.snapshot, (snapshot) => snapshot.progress);
    const reminder = new StudyReminderScheduler(context, store, progress);
    const greeter = new SeasonalEventGreeter(context, () => store.seasonNow);
    greeter.greeted.on(() => store.preview.send({ kind: "celebrate" }));
    const moment = new RecapMoment(context, recaps, (shown, done) =>
      recapTakeover({
        recap: shown.recap,
        cheer: shown.cheer,
        pet: () => context.snapshot.get().pet?.profile,
        timeZone: () => context.timeZone(),
        showsWeekDates: !context.isDemo,
        done,
        share: async (format, action) => {
          const input = {
            recap: shown.recap,
            cheer: shown.cheer,
            pet: context.snapshot.get().pet?.profile,
            format,
            theme: resolveTheme(context.settings.current.themeID),
            locale: currentLanguage(),
            timeZone: context.timeZone(),
          };
          try {
            return action === "copy" ? await copyRecapImage(input) : await saveRecapImage(context.host, input, format);
          } catch (error) {
            context.logger.error("The recap image could not be shared", error);
            return undefined;
          }
        },
      }),
    );
    /* Pausing and resuming go to the shared Pomodoro, the Mac's `context.focusTimer`. */
    const pomodoro = focusTimer(context);
    const coach = new PetCoachController(context, {
      profile: () => store.profile,
      closet: store,
      gifts,
      pauseTimer: () => pomodoro.change((timer) => timer.pause(context.now())),
      resumeTimer: () => pomodoro.change((timer) => timer.start(context.now())),
    });

    /* The island opening and closing: the recap shows on open and is done with on close. */
    const kinds = context.closedPreview.watchedKinds;
    let wasOpen = kinds.get().size === 0;
    kinds.subscribe(() => {
      const open = kinds.get().size === 0;
      if (open === wasOpen) return;
      wasOpen = open;
      if (open) void moment.islandOpened();
      else moment.islandClosed();
    });

    function Panel() {
      return <ClosetPanel store={store} recaps={recaps} gifts={gifts} />;
    }

    function SettingsPane() {
      return <PetCoachSettingsPane coach={coach} reminder={reminder} />;
    }

    const PetSetup: ComponentType<SetupStepProps> = () => <ClosetSetupView store={store} />;

    const show = (section: ClosetSection, shot: SnapshotShot = {}) => {
      store.setSection(section);
      store.showForSnapshot({
        ...(shot.foundingMember === undefined ? {} : { foundingMember: shot.foundingMember }),
        ...(shot.name === undefined ? {} : { name: shot.name }),
        ...(shot.scrolled === undefined ? {} : { scrolled: shot.scrolled }),
      });
      store.tryOn(shot.tryingOn === undefined || !PET_ACCESSORIES.includes(shot.tryingOn) ? undefined : accessoryItem(shot.tryingOn));
    };

    const showRecap = (pick: "heavy" | "light") => {
      const list = recaps.archive.recaps;
      const recap = pick === "heavy" ? list[0] : list.reduce((best, candidate) => (best === undefined || candidate.focusMinutes < best.focusMinutes ? candidate : best), list[0]);
      if (recap !== undefined) moment.present({ recap, cheer: recaps.cheer(recap) });
    };

    return {
      store,
      coach,
      recaps,
      moment,
      Panel,
      SettingsPane,
      setupView: (step) => (step.id === ONBOARDING_SETUP_STEPS.pet.id ? PetSetup : undefined),
      /* Shares the pet, so the closed island can show it. */
      provision: mapped(store, (state) => moduleProvision({ pet: state.presence })),
      start: () => {
        coach.start();
        reminder.start();
        greeter.start();
        moment.start();
      },
      stop: () => {
        coach.stop();
        reminder.stop();
        greeter.stop();
        moment.stop();
      },
      showSnapshotState: (state: string) => {
        switch (state) {
          case "wardrobe":
          case "limited":
          case "streak":
          case "look":
          case "weeks":
            return show(state);
          case "founding":
            return show("limited", { tryingOn: "foundersPin" });
          case "founding-unearned":
            return show("limited", { tryingOn: "foundersPin", foundingMember: false });
          case "founding-unearned-scrolling":
            return show("limited", { tryingOn: "foundersPin", foundingMember: false, scrolled: 0.6 });
          case "long-name":
            return show("wardrobe", { tryingOn: "chunkyHeadphones", name: "Wolfgang Wombats" });
          case "long-name-scrolling":
            return show("wardrobe", { tryingOn: "chunkyHeadphones", name: "Wolfgang Wombats", scrolled: 0.6 });
          case "animated":
            return show("activity", { tryingOn: "angelWings" });
          case "recap-heavy":
            return showRecap("heavy");
          case "recap-light":
            return showRecap("light");
          default:
            return coach.showSnapshotState(state);
        }
      },
    };
  },
  { snapshotStates: SNAPSHOT_STATES, closedSnapshotStates: PetCoachController.snapshotStates },
);
