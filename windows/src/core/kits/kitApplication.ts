import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { ModuleID } from "../modules/moduleId";
import { ModuleLayout } from "../modules/moduleLayout";
import { kitModuleIDs, type KitAnswer, type KitManifest, type KitQuestion } from "./kitManifest";

/** The user's onboarding answers: question id to the chosen answer ids. */
export type KitAnswers = Readonly<Record<string, ReadonlySet<string>>>;

/**
 * The answers picked after the user clicks `answerID`: a multiple-choice
 * question toggles it, a single-choice one picks it alone. Clicking a picked
 * answer clears it either way, since every question can be skipped.
 */
export function selectingAnswer(question: KitQuestion, answerID: string, picked: ReadonlySet<string>): Set<string> {
  if (!question.options.some((option) => option.id === answerID)) return new Set(picked);
  if (picked.has(answerID)) return new Set([...picked].filter((id) => id !== answerID));
  return question.allowsMultiple ? new Set([...picked, answerID]) : new Set([answerID]);
}

/** The answers picked for `answers`, in question and option order, so later answers win when two disagree. */
export function chosenAnswers(kit: KitManifest, answers: KitAnswers): KitAnswer[] {
  return kit.onboarding.flatMap((question) => {
    const picked = answers[question.id] ?? new Set<string>();
    const chosen = question.options.filter((option) => picked.has(option.id));
    return question.allowsMultiple ? chosen : chosen.slice(0, 1);
  });
}

/**
 * Port of KitManifest.layout(catalog:answers:): the kit's modules in kit
 * order, then every other module in `catalog` switched off (so Settings can
 * still offer them). Onboarding answers then switch modules on or off.
 * Modules `catalog` doesn't know are skipped.
 */
export function kitLayout(kit: KitManifest, catalog: ModuleCatalog, answers: KitAnswers = {}): ModuleLayout {
  const kitIDs = kitModuleIDs(kit).filter((id) => catalog.contains(id));
  const kitSet = new Set(kitIDs);
  const others = catalog.ids.filter((id) => !kitSet.has(id));
  const disabled = new Set<ModuleID>(others);
  for (const entry of kit.modules) if (!entry.enabled) disabled.add(entry.id);
  for (const answer of chosenAnswers(kit, answers)) {
    for (const id of answer.enables) disabled.delete(id);
    for (const id of answer.disables) disabled.add(id);
  }
  return new ModuleLayout([...kitIDs, ...others], disabled, catalog);
}

/** The kit's starter tasks plus any the chosen answers add, trimmed, without blanks or duplicates. */
export function kitStarterTasks(kit: KitManifest, answers: KitAnswers = {}): string[] {
  const tasks = [...kit.starterTasks, ...chosenAnswers(kit, answers).flatMap((answer) => answer.tasks)]
    .map((task) => task.trim())
    .filter((task) => task !== "");
  return [...new Set(tasks)];
}

/** The module whose accent tints the kit: `accent` if `catalog` knows it, otherwise the first tab the kit turns on. */
export function kitAccentModule(kit: KitManifest, catalog: ModuleCatalog): ModuleID | undefined {
  if (kit.accent !== undefined && catalog.contains(kit.accent)) return kit.accent;
  return kitLayout(kit, catalog).enabled[0];
}

/** Whether two answer sets pick the same answers. */
export function sameKitAnswers(a: KitAnswers, b: KitAnswers): boolean {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const key of keys) {
    const left = a[key];
    const right = b[key];
    if (left === undefined || right === undefined) {
      if (left !== right) return false;
      continue;
    }
    if (left.size !== right.size || [...left].some((id) => !right.has(id))) return false;
  }
  return true;
}
