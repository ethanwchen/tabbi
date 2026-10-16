/*
 * Helpers for the runtime's tests: a module type that records its
 * lifecycle and publishes whatever provision the test sets, and an
 * AppServices over the mock host with a hand-driven clock and alarm.
 */

import { AppServices, type AppServicesOptions } from "../../src/app/appServices";
import { silentSink } from "../../src/app/logger";
import { defineModule, type ModuleType } from "../../src/app/module";
import type { TickerAlarm } from "../../src/app/tickerStore";
import { Observable } from "../../src/app/store";
import { MODULE_CATEGORIES, moduleDescriptor, type ModuleDescriptorInput } from "../../src/core/modules/moduleDescriptor";
import { EMPTY_PROVISION, type ModuleProvision } from "../../src/core/providers/moduleProvision";
import type { Instant } from "../../src/core/time";
import { MOCK_STARTUP, mockHost, type MockHost } from "../../src/host/mock";

/** A module whose lifecycle calls land in `log` and whose provision is `provision`. */
export function recordingModule(
  id: string,
  log: string[],
  provision = new Observable<ModuleProvision>(EMPTY_PROVISION),
  extra: Partial<ModuleDescriptorInput> = {},
): ModuleType & { readonly provision: Observable<ModuleProvision> } {
  const descriptor = moduleDescriptor({
    id,
    title: id,
    symbol: "circle",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.5, green: 0.5, blue: 0.5 },
    ...extra,
  });
  const type = defineModule(descriptor, () => {
    log.push(`create ${id}`);
    return {
      Panel: () => null,
      provision,
      start: () => log.push(`start ${id}`),
      stop: () => log.push(`stop ${id}`),
    };
  });
  return Object.assign(type, { provision });
}

/** An alarm the test fires by hand; `at` is the moment it was last set for. */
export class ManualAlarm implements TickerAlarm {
  at: Instant | undefined;
  constructor(readonly fire: () => void) {}
  schedule(at: Instant): void {
    this.at = at;
  }
  cancel(): void {
    this.at = undefined;
  }
  dispose(): void {
    this.at = undefined;
  }
}

export interface TestApp {
  readonly app: AppServices;
  readonly host: MockHost;
  readonly clock: { now: Instant };
  readonly alarm: () => ManualAlarm | undefined;
}

/** AppServices for a test, on the mock host, at a pinned clock in UTC. */
export async function testApp(options: Partial<AppServicesOptions> & Pick<AppServicesOptions, "moduleTypes">, start: Instant = 1_790_000_000): Promise<TestApp> {
  const host = (options.host as MockHost | undefined) ?? mockHost();
  const clock = { now: start };
  let alarm: ManualAlarm | undefined;
  const app = await AppServices.create({
    host,
    startup: MOCK_STARTUP,
    role: "island",
    now: () => clock.now,
    timeZone: () => "UTC",
    logSink: silentSink,
    alarm: (fire) => {
      alarm = new ManualAlarm(fire);
      return alarm;
    },
    ...options,
  });
  return { app, host, clock, alarm: () => alarm };
}
