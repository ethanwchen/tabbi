import { tr } from "../localization/tr";
import type { ModuleID } from "../modules/moduleId";

/**
 * Port of OnboardingExtra: one line on onboarding's last screen, "A few
 * extras": something optional that is easy to miss, said in a line, with
 * nothing to answer. Every extra shares that one screen, so a new one never
 * makes onboarding longer.
 */
export interface OnboardingExtra {
  readonly id: string;
  readonly title: string;
  /** One short line: what it is and where to find it. */
  readonly detail: string;
  /** SF Symbol name for the row. */
  readonly symbol: string;
  /** The tab the extra lives in; the row shows only while that tab is on. Undefined for app-wide extras. */
  readonly module?: ModuleID;
}

export function onboardingExtra(
  id: string,
  title: string,
  detail: string,
  symbol: string,
  module?: ModuleID,
): OnboardingExtra {
  return module === undefined ? { id, title, detail, symbol } : { id, title, detail, symbol, module };
}

/** A built-in extra, whose text is read from the catalog each time so it follows the language. */
function builtInExtra(id: string, titleKey: string, detailKey: string, symbol: string, module?: ModuleID): OnboardingExtra {
  return {
    id,
    get title() {
      return tr(titleKey);
    },
    get detail() {
      return tr(detailKey);
    },
    symbol,
    ...(module === undefined ? {} : { module }),
  };
}

/*
 * The Mac's extras, with the Mac's copy. The desktop widget and Apple
 * Account sync don't exist on Windows yet, so the Windows onboarding
 * should pass the flow only the extras that apply there.
 */
export const ONBOARDING_EXTRAS = {
  /** The pet, streak and focus clock on the desktop. */
  widget: builtInExtra("widget", "Desktop widget", "Right-click the desktop, Edit Widgets.", "rectangle.on.rectangle"),
  /** The pet's once-a-day nudge, off until the user turns it on. */
  reminder: builtInExtra("reminder", "Daily reminder", "A daily nudge, in Closet options.", "bell.badge", "closet"),
  /** A link a friend opens to add you or join a party in one click. */
  invites: builtInExtra("invites", "Invite links", "Share a link from Party.", "link", "party"),
  /** The optional account that syncs the pet. */
  sync: builtInExtra("sync", "Sync your pet", "Optional, with your Apple Account.", "arrow.triangle.2.circlepath"),
} as const;

/** Every extra, in the order the screen lists them. */
export const ALL_ONBOARDING_EXTRAS: readonly OnboardingExtra[] = [
  ONBOARDING_EXTRAS.widget,
  ONBOARDING_EXTRAS.reminder,
  ONBOARDING_EXTRAS.invites,
  ONBOARDING_EXTRAS.sync,
];
