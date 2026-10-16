/*
 * Port of StudyCustomEditor: the Custom method's lengths, drawn inside the
 * island in place of the timer: focus and break steppers, and a long break
 * that can be switched on with its own length and spacing. Edits apply at
 * once; a Custom session under way keeps its round and clock.
 */

import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { type CustomRhythmField, type StudyCustomRhythm, customFieldStepper } from "../../core/studyMethods/studyCustomRhythm";
import { CapsuleToggle } from "../../ui/kit/CapsuleToggle";
import { Card } from "../../ui/kit/Card";
import { IconButton } from "../../ui/kit/IconButton";
import { Pill } from "../../ui/kit/Pill";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { StudyStore } from "./studyStore";

export function StudyCustomEditor({ store, close }: { store: StudyStore; close: () => void }) {
  const { custom: rhythm, session } = useStore(store);
  const isCurrent = session.method.kind === "custom";
  const isOn = rhythm.hasLongBreak;
  return (
    <div className="study-custom">
      <div className="study-custom-header">
        <span className="kit-title">{tr("Custom")}</span>
        <span className="kit-title study-accent study-rhythm">{rhythm.method.rhythmLabel}</span>
        <span className="kit-caption kit-tertiary study-custom-note">{isCurrent ? tr("Changes apply right away") : tr("Your own rhythm")}</span>
        <span className="study-spacer" />
        {!isCurrent && (
          <Pill
            title={tr("Use Custom")}
            help={tr("Start a fresh session with these lengths")}
            accent
            onClick={() => {
              store.choose("custom");
              close();
            }}
          />
        )}
        <IconButton symbol="xmark" help={tr("Done")} onClick={close} />
      </div>
      <div className="study-custom-body">
        <LengthCard title={tr("Focus")} field="focus" rhythm={rhythm} noun={tr("focus")} help={tr("How long each focus block runs")} set={(next) => store.setCustom(next)} />
        <LengthCard title={tr("Break")} field="shortBreak" rhythm={rhythm} noun={tr("break")} help={tr("The pause after each block")} set={(next) => store.setCustom(next)} />
        <Tooltip
          text={
            isOn
              ? tr("A %lld min break replaces every %@ break", rhythm.longBreakMinutes, ordinal(rhythm.longBreakEvery))
              : tr("No long break: every break is %lld min", rhythm.breakMinutes)
          }
        >
          <Card className="study-custom-card study-custom-long">
            <div className="study-custom-caption">
              <span className="kit-caption kit-tertiary">{tr("Long break")}</span>
              <span className="study-spacer" />
              <CapsuleToggle
                title={isOn ? tr("switch.on") : tr("Off")}
                symbol="cup.and.saucer"
                isOn={isOn}
                help={isOn ? tr("Turn the long break off") : tr("Take a longer break every few rounds")}
                onClick={() => store.setCustom(rhythm.withLongBreak(!isOn))}
              />
            </div>
            <span className="study-spacer" />
            <div className="study-custom-rows" data-disabled={!isOn || undefined}>
              <LongBreakRow label={tr("%lld min", rhythm.longBreakMinutes)} field="longBreak" rhythm={rhythm} noun={tr("long break")} disabled={!isOn} set={(next) => store.setCustom(next)} />
              <LongBreakRow
                label={rhythm.longBreakEvery === 2 ? tr("Every other round") : tr("Every %lld rounds", rhythm.longBreakEvery)}
                field="longBreakEvery"
                rhythm={rhythm}
                noun={tr("rounds between long breaks")}
                disabled={!isOn}
                set={(next) => store.setCustom(next)}
              />
            </div>
          </Card>
        </Tooltip>
      </div>
    </div>
  );
}

function LengthCard({
  title,
  field,
  rhythm,
  noun,
  help,
  set,
}: {
  title: string;
  field: CustomRhythmField;
  rhythm: StudyCustomRhythm;
  noun: string;
  help: string;
  set: (rhythm: StudyCustomRhythm) => void;
}) {
  return (
    <Tooltip text={help}>
      <Card className="study-custom-card">
        {/* As tall as the long break's switch, so the three captions line up. */}
        <div className="study-custom-caption">
          <span className="kit-caption kit-tertiary">{title}</span>
        </div>
        <span className="study-spacer" />
        <div className="study-custom-value">
          <span className="kit-metric">{rhythm.value(field)}</span>
          <span className="kit-caption kit-secondary">{tr("min")}</span>
        </div>
        <StudyStepper field={field} rhythm={rhythm} noun={noun} set={set} />
      </Card>
    </Tooltip>
  );
}

function LongBreakRow({
  label,
  field,
  rhythm,
  noun,
  disabled,
  set,
}: {
  label: string;
  field: CustomRhythmField;
  rhythm: StudyCustomRhythm;
  noun: string;
  disabled: boolean;
  set: (rhythm: StudyCustomRhythm) => void;
}) {
  return (
    <div className="study-custom-row">
      <span className="kit-body-emphasis study-tabular study-custom-row-label">{label}</span>
      <span className="study-spacer" />
      <StudyStepper field={field} rhythm={rhythm} noun={noun} disabled={disabled} set={set} />
    </div>
  );
}

/** Minus and plus buttons that move one field of the Custom rhythm by its step, each dimmed at the end of the field's range. */
function StudyStepper({ field, rhythm, noun, disabled = false, set }: { field: CustomRhythmField; rhythm: StudyCustomRhythm; noun: string; disabled?: boolean; set: (rhythm: StudyCustomRhythm) => void }) {
  const step = customFieldStepper(field).step;
  const tip = (steps: number): string => {
    if (field === "longBreakEvery") return steps < 0 ? tr("Fewer %@", noun) : tr("More %@", noun);
    return tr("%@ (%lld min)", steps < 0 ? tr("Shorter %@", noun) : tr("Longer %@", noun), step);
  };
  const button = (steps: number, symbol: string) => (
    <IconButton symbol={symbol} size={22} help={tip(steps)} disabled={disabled || !rhythm.canStep(field, steps)} onClick={() => set(rhythm.stepped(field, steps))} />
  );
  return (
    <div className="study-stepper">
      {button(-1, "minus")}
      {button(1, "plus")}
    </div>
  );
}

/** "2nd", "3rd", "4th", for the long break's tooltip. */
export function ordinal(number: number): string {
  switch (number) {
    case 2:
      return tr("2nd");
    case 3:
      return tr("3rd");
    default:
      return tr("%lldth", number);
  }
}

/** A small pencil on the method card that opens the Custom lengths. */
export function StudyEditButton({ onClick }: { onClick: () => void }) {
  return <IconButton symbol="pencil" size={20} className="study-quiet-button" help={tr("Edit the Custom focus and break lengths")} onClick={onClick} />;
}
