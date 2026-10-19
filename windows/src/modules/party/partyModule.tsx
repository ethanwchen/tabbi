import { lazyView } from "../../app/lazyView";
import { type CSSProperties } from "react";
import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { derived } from "../../app/store";
import type { NotchTakeover } from "../../app/takeover";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { parseInvite } from "../../core/party/partyInvite";
import { PARTY_PRODUCTION_URL } from "../../core/party/partyServer";
import { moduleProvision, type ModuleProvision } from "../../core/providers/moduleProvision";
import type { ProvidedParty } from "../../core/providers/providedParty";
import { useTheme } from "../../ui/kit/context";
import { accentVariables } from "../../ui/kit/tokens";
import { PartyInviteBody, PartyInviteTitle, type PartyInviteActions } from "./PartyInviteView";
import { PARTY_SNAPSHOT_STATES, PartyStore } from "./partyStore";
import { accountSync, partyCredentialStore } from "./syncService";

/* The views load on first use; the store and descriptor stay eager. */
const PartyOnboardingView = lazyView(() => import("./PartyOnboardingView"), "PartyOnboardingView");
const PartyPanel = lazyView(() => import("./PartyPanel"), "PartyPanel");
const PartySettingsPane = lazyView(() => import("./PartySettingsPane"), "PartySettingsPane");

/* Port of PartyModule: studying with friends, through the Party Worker. */
export const PARTY_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.party,
    title: "Party",
    symbol: "person.3.fill",
    category: MODULE_CATEGORIES.study,
    accent: { red: 1.0, green: 0.42, blue: 0.62 },
    network: [{ host: new URL(PARTY_PRODUCTION_URL).hostname, purpose: "your presence and parties" }],
    setup: [ONBOARDING_SETUP_STEPS.party],
  },
  {
    title: () => tr("Party"),
    summary: () => tr("Study with friends and see who is focusing now."),
  },
);

function sameParty(a: ProvidedParty | undefined, b: ProvidedParty | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  if (a.pets.length !== b.pets.length) return false;
  const samePets = a.pets.every((pet, index) => {
    const other = b.pets[index];
    return other !== undefined && pet.id === other.id && pet.name === other.name && pet.isAway === other.isAway && pet.pet.equals(other.pet);
  });
  if (!samePets) return false;
  const x = a.session;
  const y = b.session;
  if (x === undefined || y === undefined) return x === y;
  return x.method === y.method && x.startedAt === y.startedAt && x.endsAt === y.endsAt && x.friendCount === y.friendCount && x.hostName === y.hostName;
}

/** Two provisions with the same party, session and badge merge to the same snapshot. */
function sameProvision(a: ModuleProvision, b: ModuleProvision): boolean {
  return a.badge === b.badge && sameParty(a.party, b.party);
}

export const PartyModule = defineModule(
  PARTY_DESCRIPTOR,
  (context) => {
    const store = new PartyStore(context, { credentials: partyCredentialStore(context) });
    const account = accountSync(context, () => ({
      server: () => store.serverURL,
      credentials: partyCredentialStore(context),
      ageAnswer: { load: () => store.state.settings.ageEligibleFrom },
    }));
    store.isSignedIn = () => account.isSignedIn;
    store.ageAnswered = () => account.refreshAgeStatus();
    account.identityChanged.on(() => store.identityDidChange());
    store.follow();
    /* A stay in a shared session ended: the activity log records the focus stretch, and a finished session celebrates; a hidden panel gets a toast instead. */
    store.onCompletion((completion) => {
      const { record, celebration } = store.finish(completion);
      if (record !== undefined) void context.activityLog.record(record);
      if (celebration !== undefined && !store.isVisible) void context.host.notify(celebration.title, celebration.detail).catch(() => undefined);
    });
    store.onGrants((items) => context.logger.info(`Party granted ${items.length} limited edition items`));

    const openURL = (url: string) => store.openURL(url);
    function Panel() {
      return <PartyPanel store={store} onOpenURL={openURL} />;
    }
    function SetupView() {
      return <PartyOnboardingView store={store} accent={PARTY_DESCRIPTOR.accent} />;
    }
    function SettingsPane() {
      const theme = useTheme();
      return (
        <div style={accentVariables(theme, PARTY_DESCRIPTOR.accent) as CSSProperties}>
          <PartySettingsPane store={store} account={account} />
        </div>
      );
    }

    const inviteActions: PartyInviteActions = {
      /* Adds Party as a tab, which starts it, then lets the invite go on. */
      turnOnParty: () => {
        context.settings.update((settings) => {
          const modules = settings.modules.clone();
          modules.add(PARTY_DESCRIPTOR.id);
          return { ...settings, modules };
        });
        store.inviteTurnedPartyOn();
      },
      /* The island already opened on Party for the link it took; after the invite the tab is still Party. */
      showPartyTab: () => {},
    };
    function InviteBody() {
      return <PartyInviteBody store={store} accent={PARTY_DESCRIPTOR.accent} symbol={PARTY_DESCRIPTOR.symbol} actions={inviteActions} />;
    }
    function InviteTitle() {
      return <PartyInviteTitle symbol={PARTY_DESCRIPTOR.symbol} accent={PARTY_DESCRIPTOR.accent} />;
    }
    const inviteTakeover: NotchTakeover = { Leading: InviteTitle, Trailing: () => null, Body: InviteBody };

    return {
      store,
      account,
      Panel,
      SettingsPane,
      setupView: (step) => (step.id === ONBOARDING_SETUP_STEPS.party.id ? SetupView : undefined),
      /* The party and its shared session (also as the shared focus clock), and the friend requests waiting for me as the tab's badge. */
      provision: derived(
        [store],
        () => {
          const party = store.provided();
          return moduleProvision({ party, focus: party?.session?.focus(PARTY_DESCRIPTOR.id), badge: store.state.party.waitingRequestCount });
        },
        sameProvision,
      ),
      takeover: derived([store], () => (store.state.invite === undefined ? undefined : inviteTakeover)),
      start: () => {
        store.start();
        account.start();
      },
      stop: () => {
        store.stop();
        account.stop();
      },
      /* An invite link (`tabbi://add/<code>`, `tabbi://join/<code>`) or the sign-in callback (`tabbi://auth/apple`). */
      openLink: (url) => {
        const invite = parseInvite(url);
        if (invite !== undefined) {
          store.open(invite, context.settings.current.modules.isEnabled(PARTY_DESCRIPTOR.id));
          return true;
        }
        return account.receiveCallback(url);
      },
      showSnapshotState: (state) => store.showSnapshotState(state),
    };
  },
  { snapshotStates: PARTY_SNAPSHOT_STATES },
);
