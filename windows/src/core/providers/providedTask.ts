import type { ModuleID } from "../modules/moduleId";

/**
 * Port of ProvidedTask: something to do today that a module contributes to
 * Today and the ticker, such as a checklist item or "Review 84 Anki cards".
 * The TaskSource role of a module.
 */
export interface ProvidedTask {
  /** Stable within its source module, so a refresh updates the same row. */
  readonly id: string;
  /** The module that provided it; `ProviderSnapshot` sets it when merging. */
  readonly source: ModuleID;
  readonly title: string;
  readonly isDone: boolean;
  /** A rough size for Plan my day, when the source knows one. */
  readonly estimatedMinutes?: number | undefined;
}

/** A task with the Mac initializer's defaults: not done, no estimate. */
export function providedTask(init: {
  id: string;
  source: ModuleID;
  title: string;
  isDone?: boolean;
  estimatedMinutes?: number | undefined;
}): ProvidedTask {
  return {
    id: init.id,
    source: init.source,
    title: init.title,
    isDone: init.isDone ?? false,
    ...(init.estimatedMinutes === undefined ? {} : { estimatedMinutes: init.estimatedMinutes }),
  };
}
