/*
 * Port of SharedServices: app-wide services several modules use, created
 * the first time any module asks, so no shared file has to list them.
 *
 * A service is declared beside the module that owns it, as a key and an
 * accessor, so every module asking gets the same instance:
 *
 * ```ts
 * const FOCUS_TIMER = serviceKey<FocusTimerService>("focus.timer");
 * export const focusTimer = (context: ModuleContext) =>
 *   context.shared.resolve(FOCUS_TIMER, () => new FocusTimerService(context));
 * ```
 */

/** Names one shared service and its type. Two keys are the same service only when they are the same object. */
export interface ServiceKey<T> {
  readonly name: string;
  /* Never read; it carries `T` so `resolve` is typed by the key. */
  readonly type?: T;
}

export function serviceKey<T>(name: string): ServiceKey<T> {
  return { name };
}

export class SharedServices {
  private readonly services = new Map<ServiceKey<unknown>, unknown>();

  /** The one service for `key` in this window, made by `make` on first use. */
  resolve<T>(key: ServiceKey<T>, make: () => T): T {
    if (this.services.has(key)) return this.services.get(key) as T;
    const service = make();
    this.services.set(key, service);
    return service;
  }

  /** The service for `key` if some module already made it. */
  existing<T>(key: ServiceKey<T>): T | undefined {
    return this.services.get(key) as T | undefined;
  }
}
