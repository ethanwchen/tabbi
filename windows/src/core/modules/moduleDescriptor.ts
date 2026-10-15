import { tr } from "../localization/tr";
import type { KitSettingsSchema } from "../kits/kitSettingsSchema";
import type { OnboardingSetupStep } from "../onboarding/onboardingSetupStep";
import type { ModuleID } from "./moduleId";

/**
 * Port of ModuleCategory: the shelf a module sits on in Settings and the
 * module browser. Open like ModuleID, so a new vertical can bring a
 * category of its own; two categories are equal when their ids are, and only
 * the id is stored.
 */
export interface ModuleCategory {
  readonly id: string;
  /** The name shown to people, such as "Productivity". */
  readonly title: string;
}

/** A category whose title is `title`, or its id with the first letter capitalized. */
export function moduleCategory(id: string, title?: string): ModuleCategory {
  return { id, title: title ?? id.slice(0, 1).toUpperCase() + id.slice(1) };
}

/** A built-in category, whose title is read from the catalog each time so it follows the language. */
function builtInCategory(id: string, key: string): ModuleCategory {
  return {
    id,
    get title() {
      return tr(key);
    },
  };
}

export const MODULE_CATEGORIES = {
  media: builtInCategory("media", "Media"),
  system: builtInCategory("system", "System"),
  productivity: builtInCategory("productivity", "Productivity"),
  study: builtInCategory("study", "Study"),
  ai: builtInCategory("ai", "AI"),
  fun: builtInCategory("fun", "Fun"),
} as const;

/** The categories the built-in modules use, so decoding a stored id gets the proper title ("AI", not "Ai"). */
export const BUILT_IN_CATEGORIES: readonly ModuleCategory[] = Object.values(MODULE_CATEGORIES);

/** The category a stored id names. */
export function decodeModuleCategory(id: string): ModuleCategory {
  return BUILT_IN_CATEGORIES.find((category) => category.id === id) ?? moduleCategory(id);
}

/** Port of ModulePermission: a system permission a module asks for, so Settings and onboarding can say so up front. */
export type ModulePermission = "automation" | "calendars" | "reminders" | "notifications" | "claudeCLI";

/** Every permission, in the Mac's declaration order. */
export const MODULE_PERMISSIONS: readonly ModulePermission[] = [
  "automation",
  "calendars",
  "reminders",
  "notifications",
  "claudeCLI",
];

export function modulePermissionTitle(permission: ModulePermission): string {
  switch (permission) {
    case "automation":
      return tr("Automation");
    case "calendars":
      return tr("Calendars");
    case "reminders":
      return tr("Reminders");
    case "notifications":
      return tr("Notifications");
    case "claudeCLI":
      return "Claude Code CLI";
  }
}

/**
 * Port of ModuleNetworkAccess: a host a module talks to, declared on its
 * descriptor so Settings and the kit import sheet can say where data goes.
 */
export interface ModuleNetworkAccess {
  /** The host name, such as `i.scdn.co`. */
  readonly host: string;
  /** What the module fetches or sends there, finishing "connects to the host for ...". */
  readonly purpose: string;
}

/** True for a service on this machine (AnkiConnect), which sends nothing off it. */
export function isLocalNetworkAccess(access: ModuleNetworkAccess): boolean {
  return ["localhost", "127.0.0.1", "::1"].includes(access.host.toLowerCase());
}

/** Port of ModuleAccent: an sRGB color in 0...1 components. */
export interface ModuleAccent {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
}

/** Claude's terracotta, shared by both Claude modules. */
export const CLAUDE_ACCENT: ModuleAccent = { red: 0.85, green: 0.47, blue: 0.34 };

/** Port of ModuleHeaderShortcut: a module opened from a header button instead of a tab. */
export interface ModuleHeaderShortcut {
  /** Tooltip and accessibility label, e.g. "Your pet". */
  readonly label: string;
  /** One lowercase letter, e.g. "p"; matched case-insensitively. */
  readonly key: string;
}

/**
 * Port of ModuleDescriptor: everything about a module known without
 * running it, which the tab bar, Settings and kit manifests need.
 */
export interface ModuleDescriptor {
  readonly id: ModuleID;
  readonly title: string;
  /** SF Symbol name, mapped to an icon by the UI. */
  readonly symbol: string;
  /** One plain sentence for the "Add more" library; undefined falls back to the category's name. */
  readonly summary?: string;
  readonly category: ModuleCategory;
  readonly accent: ModuleAccent;
  readonly permissions: ReadonlySet<ModulePermission>;
  /** Every host the module's own code connects to; empty for a module that never touches the network. */
  readonly network: readonly ModuleNetworkAccess[];
  /** Label for the Settings toggle of this module's ticker highlights; undefined when it publishes none. */
  readonly highlightTitle?: string;
  /** The module runs a focus clock of its own, not the shared Pomodoro. */
  readonly ownsFocusClock: boolean;
  /** The keys this module reads from its kit `moduleSettings` section; undefined leaves it unchecked. */
  readonly kitSettings?: KitSettingsSchema;
  /** What first-run onboarding asks once this module is on. */
  readonly setup: readonly OnboardingSetupStep[];
  /** Set for a module reached from its own header button rather than a tab. */
  readonly headerShortcut?: ModuleHeaderShortcut;
}

export interface ModuleDescriptorInput {
  id: ModuleID;
  title: string;
  symbol: string;
  summary?: string;
  category: ModuleCategory;
  accent: ModuleAccent;
  permissions?: Iterable<ModulePermission>;
  network?: readonly ModuleNetworkAccess[];
  highlightTitle?: string;
  ownsFocusClock?: boolean;
  kitSettings?: KitSettingsSchema;
  setup?: readonly OnboardingSetupStep[];
  headerShortcut?: ModuleHeaderShortcut;
}

/** A descriptor with the Mac initializer's defaults filled in. */
export function moduleDescriptor(input: ModuleDescriptorInput): ModuleDescriptor {
  const { permissions, network, ownsFocusClock, setup, headerShortcut, ...rest } = input;
  const descriptor: ModuleDescriptor = {
    ...rest,
    permissions: new Set(permissions ?? []),
    network: [...(network ?? [])],
    ownsFocusClock: ownsFocusClock ?? false,
    setup: [...(setup ?? [])],
  };
  return headerShortcut === undefined
    ? descriptor
    : { ...descriptor, headerShortcut: { label: headerShortcut.label, key: headerShortcut.key.toLowerCase() } };
}

/** Stand-in for an id no catalog knows, so the UI degrades to a neutral tab instead of failing. */
export function unknownModuleDescriptor(id: ModuleID): ModuleDescriptor {
  return moduleDescriptor({
    id,
    title: id,
    symbol: "square.dashed",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.6, green: 0.6, blue: 0.6 },
  });
}
