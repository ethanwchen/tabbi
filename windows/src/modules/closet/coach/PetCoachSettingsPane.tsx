/*
 * Port of PetCoachSettingsPane and StudyReminderSettingsSection: Settings >
 * Pet Coach. Whether the pet nudges during focus, and which apps count as
 * distracting: suggestions are opt-in chips; any other app is added by its
 * executable name (Windows has no Applications folder to pick from). The
 * daily study reminder, in the pet's voice, sits below.
 */

import { useState } from "react";
import { useStore } from "../../../app/useStore";
import { SUGGESTED_DISTRACTING_APPS } from "../../../core/coach/coachAppList";
import { tr } from "../../../core/localization/tr";
import { Icon } from "../../../ui/kit/Icon";
import { IconButton } from "../../../ui/kit/IconButton";
import { Picker } from "../../../ui/kit/Picker";
import { Pill } from "../../../ui/kit/Pill";
import { SettingsGroup, SettingsRow } from "../../../ui/kit/SettingsGroup";
import { TextField } from "../../../ui/kit/TextField";
import { Toggle } from "../../../ui/kit/Toggle";
import { Tooltip } from "../../../ui/kit/Tooltip";
import type { StudyReminderScheduler } from "../studyReminderScheduler";
import type { PetCoachController } from "./petCoachController";
import "./coach.css";

export function PetCoachSettingsPane({ coach, reminder }: { coach: PetCoachController; reminder: StudyReminderScheduler }) {
  const state = useStore(coach);
  const [draft, setDraft] = useState("");
  const add = () => {
    coach.addDistractingApp(draft);
    setDraft("");
  };
  return (
    <div className="settings-page">
      <SettingsGroup
        title={tr("Nudges")}
        footer={tr("Only while a focus phase runs, at most a few times an hour. Your pet checks how long since you last typed or moved the pointer, and which app is in front. Nothing else, and no permissions.")}
      >
        <SettingsRow label={tr("Nudge me during focus")} tooltip={tr("Let your pet walk out of the island when you drift during a focus phase")}>
          <Toggle isOn={state.nudgesOn} onChange={(on) => coach.setNudgesOn(on)} label={tr("Nudge me during focus")} />
        </SettingsRow>
      </SettingsGroup>
      <SettingsGroup title={tr("Distracting apps")} footer={tr("Time in these apps counts as drifting. Websites can't be told apart, since that would need Screen Recording, so pick apps rather than sites.")}>
        <div className="coach-chips" aria-disabled={!state.nudgesOn || undefined}>
          {SUGGESTED_DISTRACTING_APPS.map((app) => {
            const isOn = state.apps.isDistracting(app.executable);
            return (
              <Tooltip key={app.executable} text={isOn ? tr("Stop counting %@ as distracting", app.name) : tr("Count time in %@ as drifting", app.name)}>
                <button type="button" className="coach-chip" data-on={isOn} aria-pressed={isOn} disabled={!state.nudgesOn} onClick={() => coach.toggleDistracting(app.executable)}>
                  <Icon id="app.dashed" size={13} className="coach-chip-icon" />
                  <span className="coach-chip-name">{app.name}</span>
                  {isOn && <Icon id="checkmark" size={10} fixedDirection />}
                </button>
              </Tooltip>
            );
          })}
        </div>
        {state.apps.addedDistracting.map((executable) => (
          <SettingsRow key={executable} label={executable} tooltip={executable} className="kit-user-text">
            <IconButton symbol="minus.circle.fill" size={20} help={tr("Stop counting %@ as distracting", executable)} disabled={!state.nudgesOn} onClick={() => coach.toggleDistracting(executable)} />
          </SettingsRow>
        ))}
        <SettingsRow label={tr("Add an app by its program name")} help={tr("The name of its program file, such as Discord.exe")} stacked>
          <div className="coach-add-row">
            <TextField value={draft} onChange={setDraft} onSubmit={add} label={tr("Program name")} placeholder="Discord.exe" width={200} disabled={!state.nudgesOn} />
            <Pill title={tr("Add")} symbol="plus" onClick={add} disabled={!state.nudgesOn || draft.trim() === ""} />
          </div>
        </SettingsRow>
      </SettingsGroup>
      <StudyReminderSection reminder={reminder} />
    </div>
  );
}

/* Half-hour slots for the reminder's time, plus the saved time when it sits between two. */
function timeItems(minuteOfDay: number, locale: string): { id: string; title: string }[] {
  const format = new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" });
  const title = (minute: number) => format.format(new Date(2026, 0, 1, Math.floor(minute / 60), minute % 60));
  const minutes = Array.from({ length: 48 }, (_, index) => index * 30);
  if (!minutes.includes(minuteOfDay)) minutes.push(minuteOfDay);
  minutes.sort((a, b) => a - b);
  return minutes.map((minute) => ({ id: String(minute), title: title(minute) }));
}

/** Settings > Pet Coach > Daily reminder: one switch and a time. Port of StudyReminderSettingsSection. */
function StudyReminderSection({ reminder }: { reminder: StudyReminderScheduler }) {
  const state = useStore(reminder);
  const name = reminder.petName.trim() === "" ? "Tabbi" : reminder.petName;
  const locale = typeof navigator === "undefined" ? "en" : navigator.language;
  return (
    <SettingsGroup title={tr("Daily reminder")} footer={tr("\"%@ misses you. 10 minutes?\" At most once a day, and only if you haven't studied or met your goal yet. Focus assist silences it.", name)}>
      <SettingsRow label={tr("Remind me to study")} tooltip={tr("A gentle nudge from %@ on days you haven't studied yet", name)}>
        <Toggle isOn={state.settings.isEnabled} onChange={(on) => reminder.setEnabled(on)} label={tr("Remind me to study")} />
      </SettingsRow>
      <SettingsRow label={tr("Time")} tooltip={tr("When the reminder can come, in your PC's time zone")}>
        <Picker label={tr("Time")} items={timeItems(state.settings.minuteOfDay, locale)} selected={String(state.settings.minuteOfDay)} onSelect={(id) => reminder.setMinuteOfDay(Number(id))} disabled={!state.settings.isEnabled} width={112} />
      </SettingsRow>
    </SettingsGroup>
  );
}
