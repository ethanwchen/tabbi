/*
 * Port of the Mac's LeetCodeFixture: a minimal "LeetCode daily" module
 * written the way a new module is added (AGENTS.md, "Adding a module"). In
 * the app it would be `src/modules/leetcode/` plus one line in
 * `moduleList.ts`; `appRuntime.test.ts` adds it to the list and checks that
 * the catalog, kits, the provider snapshot, the ticker and the activity log
 * all pick it up with no shared code.
 */

import type { ModuleContext } from "../../src/app/context";
import { defineModule } from "../../src/app/module";
import { mapped, Store } from "../../src/app/store";
import { useStore } from "../../src/app/useStore";
import { makeActivityRecord } from "../../src/core/activity/activityRecord";
import { KitSettingsSchema, kitSetting } from "../../src/core/kits/kitSettingsSchema";
import { moduleCategory, moduleDescriptor } from "../../src/core/modules/moduleDescriptor";
import { isJSONObject, type JSONValue } from "../../src/core/persistence/json";
import { moduleProvision, type ModuleProvision } from "../../src/core/providers/moduleProvision";
import { ProgressItem } from "../../src/core/providers/progressItem";
import { providedTask } from "../../src/core/providers/providedTask";
import { TickerHighlight } from "../../src/core/providers/tickerHighlight";
import { Card } from "../../src/ui/kit/Card";

/** The estimate a kit may set for one problem, in minutes. */
const MINUTES_PER_PROBLEM = { min: 5, max: 180 } as const;

export const LEETCODE_DESCRIPTOR = moduleDescriptor({
  id: "leetcode",
  title: "LeetCode",
  symbol: "chevron.left.forwardslash.chevron.right",
  summary: "Solve the LeetCode daily problem.",
  /* Categories are open: a new vertical brings its own. */
  category: moduleCategory("coding", "Coding"),
  accent: { red: 1.0, green: 0.63, blue: 0.16 },
  highlightTitle: "LeetCode daily",
  kitSettings: new KitSettingsSchema({ minutesPerProblem: kitSetting.number(MINUTES_PER_PROBLEM.min, MINUTES_PER_PROBLEM.max) }),
});

interface LeetCodeDaily {
  readonly title: string;
  readonly difficulty: string;
  readonly estimatedMinutes: number;
  readonly isSolved: boolean;
  readonly streak: number;
  readonly isRunning: boolean;
}

/** Owns today's problem and turns it into what the module shares. */
export class LeetCodeStore extends Store<LeetCodeDaily> {
  constructor(private readonly context: ModuleContext) {
    /* Sample data; a real module would fetch it, and only when not `context.isDemo`. */
    super({ title: "Two Sum", difficulty: "Easy", estimatedMinutes: 20, isSolved: false, streak: 6, isRunning: false });
  }

  start(): void {
    this.setState({ isRunning: true });
  }

  stop(): void {
    this.setState({ isRunning: false });
  }

  /** Reads the module's kit section leniently: a value outside the schema's range keeps the current estimate. */
  useKitSettings(section: JSONValue | undefined): void {
    const minutes = isJSONObject(section) ? section.minutesPerProblem : undefined;
    if (typeof minutes !== "number" || minutes < MINUTES_PER_PROBLEM.min || minutes > MINUTES_PER_PROBLEM.max) return;
    this.setState({ estimatedMinutes: minutes });
  }

  /** Marks today's problem solved and logs it under an activity kind of the module's own. */
  markSolved(): void {
    this.setState((daily) => ({ isSolved: true, streak: daily.streak + 1 }));
    void this.context.activityLog.record(
      makeActivityRecord({ source: this.context.id, kind: "problem.solved", start: this.context.now(), quantity: 1, subject: this.state.title }),
    );
  }

  /** A task for Today and Plan my day, a progress goal, and a ticker line while the problem is unsolved. */
  provision(): ModuleProvision {
    const daily = this.state;
    const source = this.context.id;
    return moduleProvision({
      tasks: [providedTask({ id: "daily", source, title: `LeetCode: ${daily.title}`, isDone: daily.isSolved, estimatedMinutes: daily.estimatedMinutes })],
      progress: [new ProgressItem({ id: "daily", source, title: "LeetCode daily", completed: daily.isSolved ? 1 : 0, target: 1, unit: "problem" })],
      highlights: daily.isSolved
        ? []
        : [new TickerHighlight({ id: "daily", source, text: "1 problem left", summary: `Today's LeetCode: ${daily.title} (${daily.difficulty})`, priority: 10 })],
    });
  }
}

export const LeetCodeModule = defineModule(LEETCODE_DESCRIPTOR, (context) => {
  const store = new LeetCodeStore(context);
  store.useKitSettings(context.kitSettings());
  context.kitApplied((application) => store.useKitSettings(context.kitSettings(application.kit)));

  function Panel() {
    const daily = useStore(store);
    return (
      <Card>
        <div className="kit-title">{daily.title}</div>
        <div className="kit-caption">{`${daily.difficulty}, ${daily.streak} day streak`}</div>
      </Card>
    );
  }

  return {
    store,
    Panel,
    /* The provision follows the store: the hub reads it and hears every change. */
    provision: mapped(store, () => store.provision()),
    start: () => store.start(),
    stop: () => store.stop(),
  };
});
