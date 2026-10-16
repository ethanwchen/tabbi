import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { SystemPanel } from "./SystemPanel";
import { SYSTEM_SNAPSHOT_STATES, SystemStore } from "./systemStore";

/* Port of SystemModule: CPU, GPU and memory use, sampled by the host only while the tab shows. */
export const SYSTEM_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.system,
    title: "System",
    symbol: "cpu",
    category: MODULE_CATEGORIES.system,
    accent: { red: 0.35, green: 0.78, blue: 1.0 },
  },
  {
    title: () => tr("System"),
    summary: () => tr("Your PC's CPU, GPU and memory use at a glance."),
  },
);

export const SystemModule = defineModule(
  SYSTEM_DESCRIPTOR,
  (context) => {
    const store = new SystemStore(context);
    function Panel() {
      return <SystemPanel store={store} />;
    }
    return {
      store,
      Panel,
      showSnapshotState: (state: string) => store.showSnapshotState(state),
    };
  },
  { snapshotStates: SYSTEM_SNAPSHOT_STATES },
);
