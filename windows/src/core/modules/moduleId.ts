/**
 * Port of ModuleID: a module's stable id, lower camel case, shared with the Mac
 * so kits, Party and sync stay compatible. Ids are open: a module declares its
 * own, so this is a string, with the built-in ones named here.
 */
export type ModuleID = string;

export const MODULE_IDS = {
  spotify: "spotify",
  system: "system",
  claudeUsage: "claudeUsage",
  planner: "planner",
  claudeAsk: "claudeAsk",
  focus: "focus",
  schedule: "schedule",
  study: "study",
  anki: "anki",
  party: "party",
  closet: "closet",
} as const satisfies Record<string, ModuleID>;
