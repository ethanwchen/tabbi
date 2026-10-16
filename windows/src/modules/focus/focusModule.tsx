import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { FocusMix } from "../../core/focus/focusMix";
import { FOCUS_SOUNDS } from "../../core/focus/focusSound";
import { KitSettingsSchema, kitSetting } from "../../core/kits/kitSettingsSchema";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { placeholderPanel } from "../placeholderPanel";

/* Port of FocusSettings.kitSettings: a kit may set the focus sounds, up to three layers. */
export const FOCUS_KIT_SCHEMA = new KitSettingsSchema({
  sounds: kitSetting.list(
    kitSetting.object({ sound: kitSetting.choice(FOCUS_SOUNDS), level: kitSetting.number(0, 1) }),
    FocusMix.maxLayers,
  ),
});

/* Port of FocusModule: the Pomodoro that switches between focus and breaks, and the focus sounds. */
export const FOCUS_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.focus,
    title: "Focus",
    symbol: "hourglass",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.3, green: 0.84, blue: 0.76 },
    permissions: ["notifications"],
    kitSettings: FOCUS_KIT_SCHEMA,
  },
  {
    title: () => tr("Focus"),
    summary: () => tr("A Pomodoro timer that switches between focus and breaks."),
  },
);

export const FocusModule = defineModule(FOCUS_DESCRIPTOR, () => ({
  Panel: placeholderPanel(FOCUS_DESCRIPTOR),
}));
