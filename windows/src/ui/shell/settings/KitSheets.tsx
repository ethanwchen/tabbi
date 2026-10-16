/*
 * Port of KitQuestionsView and KitImportReviewView: the sheets Settings >
 * Tabs shows before a kit changes anything. The questions sheet asks a
 * kit's onboarding questions (every one optional) with a live row of the
 * tabs the answers turn on; the review sheet says what an imported kit
 * will do (the tabs it turns on and off, the permissions and hosts those
 * tabs bring, the starter tasks, whether the pill's previews change, what
 * this build skips, and which earlier import it replaces) before it is
 * saved or applied.
 */

import { useState, type CSSProperties } from "react";
import { kitAccentModule, kitLayout, selectingAnswer, type KitAnswers } from "../../../core/kits/kitApplication";
import type { KitChangePreview } from "../../../core/kits/kitChangePreview";
import { kitVersionChange, type KitImportCandidate } from "../../../core/kits/importedKitStore";
import type { KitAnswer, KitManifest, KitQuestion } from "../../../core/kits/kitManifest";
import { kitIssueDescription, type KitIssue } from "../../../core/kits/kitSettingsSchema";
import { currentLanguage, tr } from "../../../core/localization/tr";
import type { ModuleCatalog } from "../../../core/modules/moduleCatalog";
import { modulePermissionTitle } from "../../../core/modules/moduleDescriptor";
import { useTheme, useTransition } from "../../kit/context";
import { Icon } from "../../kit/Icon";
import { Sheet } from "../../kit/Sheet";
import { useTactile } from "../../kit/tactile";
import { accentCss } from "../../kit/tokens";
import { Tooltip } from "../../kit/Tooltip";
import { listOf, SettingsButton, TabIcons } from "./parts";

function kitBadge(kit: KitManifest, catalog: ModuleCatalog, theme: ReturnType<typeof useTheme>) {
  const module = kitAccentModule(kit, catalog);
  const tint = module === undefined ? "var(--primary-text)" : accentCss(theme, catalog.descriptor(module).accent);
  return (
    <span className="settings-kit-badge" style={{ background: tint }}>
      <Icon id={kit.symbol} size={24} />
    </span>
  );
}

export interface KitQuestionsSheetProps {
  readonly kit: KitManifest;
  readonly catalog: ModuleCatalog;
  /** The answers to start from, e.g. when the user comes back from the import review to change them. */
  readonly answers?: KitAnswers;
  /** Cancel: leaves the current kit as it was. */
  readonly onCancel: () => void;
  readonly onContinue: (answers: KitAnswers) => void;
  /** The primary button's title: Switch Kit, or Continue on the way to an import review. */
  readonly continueTitle?: string;
}

/** The kit's onboarding questions. Every question is optional; the tabs row previews what the answers will turn on or off. */
export function KitQuestionsSheet({ kit, catalog, answers: initial = {}, onCancel, onContinue, continueTitle }: KitQuestionsSheetProps) {
  const theme = useTheme();
  const [answers, setAnswers] = useState<KitAnswers>(initial);
  const tabs = kitLayout(kit, catalog, answers).enabled.map((id) => catalog.descriptor(id));
  const module = kitAccentModule(kit, catalog);
  const tint = module === undefined ? "var(--primary-text)" : accentCss(theme, catalog.descriptor(module).accent);
  const title = continueTitle ?? tr("Switch Kit");
  return (
    <Sheet
      badge={kitBadge(kit, catalog, theme)}
      title={tr("Set up %@", kit.name)}
      intro={tr("A few quick questions so your tabs and starter tasks fit you. Skip any you like.")}
      onCancel={onCancel}
      actions={
        <>
          <SettingsButton title={tr("Cancel")} help={tr("Keep your current kit and tabs")} onClick={onCancel} />
          <span className="kit-sheet-spacer" />
          <SettingsButton title={title} help={tr("Switch to %@ with these answers", kit.name)} primary onClick={() => onContinue(answers)} />
        </>
      }
    >
      {kit.onboarding.map((question) => (
        <QuestionBlock
          key={question.id}
          question={question}
          picked={answers[question.id] ?? new Set()}
          tint={tint}
          select={(id) => setAnswers((current) => ({ ...current, [question.id]: selectingAnswer(question, id, current[question.id] ?? new Set()) }))}
        />
      ))}
      <Tooltip text={tr("The tabs %@ starts with: %@", kit.name, listOf(tabs.map((tab) => tab.title), currentLanguage()))}>
        <div className="settings-your-tabs">
          <span className="kit-caption kit-secondary">{tr("Your tabs")}</span>
          <TabIcons modules={tabs} />
        </div>
      </Tooltip>
    </Sheet>
  );
}

/** One question: its prompt and a row of answer tiles. */
function QuestionBlock({ question, picked, tint, select }: { question: KitQuestion; picked: ReadonlySet<string>; tint: string; select: (id: string) => void }) {
  return (
    <div className="settings-question">
      <div className="settings-question-prompt">
        <span className="kit-title">{question.prompt}</span>
        {question.allowsMultiple && <span className="kit-caption kit-tertiary">{tr("Pick any")}</span>}
      </div>
      <div className="settings-answers">
        {question.options.map((option) => (
          <AnswerTile key={option.id} answer={option} isSelected={picked.has(option.id)} tint={tint} onPick={() => select(option.id)} />
        ))}
      </div>
    </div>
  );
}

/** A selectable answer: its symbol over its label, styled like the kit cards. */
function AnswerTile({ answer, isSelected, tint, onPick }: { answer: KitAnswer; isSelected: boolean; tint: string; onPick: () => void }) {
  const tactile = useTactile();
  const transition = useTransition("snappy", ["background-color", "box-shadow", "color"]);
  return (
    <Tooltip text={isSelected ? tr('Clear "%@"', answer.label) : answer.label}>
      <button
        type="button"
        className="settings-answer"
        data-selected={isSelected}
        aria-pressed={isSelected}
        {...tactile.data}
        {...tactile.handlers}
        style={{ "--tile-tint": tint, ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", ") } as CSSProperties}
        onClick={onPick}
      >
        <span className="settings-answer-symbol" style={{ color: isSelected ? tint : "var(--secondary-text)" }}>
          <Icon id={answer.symbol ?? "circle"} size={16} />
        </span>
        <span className="settings-answer-label kit-body">{answer.label}</span>
      </button>
    </Tooltip>
  );
}

export interface KitImportReviewSheetProps {
  readonly candidate: KitImportCandidate;
  readonly preview: KitChangePreview;
  /** What the kit uses that this build skips. */
  readonly issues: readonly KitIssue[];
  /** True when the kit is the active one, so applying it is an update. */
  readonly isActiveKit: boolean;
  readonly catalog: ModuleCatalog;
  /** Back to the questions when the kit has any; undefined shows Cancel only. */
  readonly onBack?: () => void;
  readonly onCancel: () => void;
  /** Saves the kit without changing the user's tabs. */
  readonly onAddOnly: () => void;
  /** Saves the kit and switches to it. */
  readonly onApply: () => void;
}

export function KitImportReviewSheet({ candidate, preview, issues, isActiveKit, catalog, onBack, onCancel, onAddOnly, onApply }: KitImportReviewSheetProps) {
  const theme = useTheme();
  const kit = candidate.kit;
  const locale = currentLanguage();
  const on = preview.turnsOn.map((id) => catalog.descriptor(id).title);
  const off = preview.turnsOff.map((id) => catalog.descriptor(id).title);
  const tabChange = [on.length === 0 ? undefined : tr("Turns on %@.", listOf(on, locale)), off.length === 0 ? undefined : tr("Turns off %@.", listOf(off, locale))]
    .filter((part): part is string => part !== undefined)
    .join(" ");
  const change = kitVersionChange(candidate);
  const replacement = change === undefined ? tr("Replaces the %@ kit you imported before.", candidate.replaces?.name ?? kit.name) : tr("Updates %@, replacing the copy you imported before.", change);
  const tasks = preview.starterTasks;
  const starterNote =
    tasks.length === 0
      ? tr("Adds no tasks.")
      : tasks.length === 1
        ? tr('Adds "%@".', tasks[0] ?? "")
        : tr("Adds %lld starter tasks: %@.", tasks.length, listOf(tasks.map((task) => `"${task}"`), locale));
  const rows: { label: string; value: string; warning?: boolean; tabs?: boolean }[] = [];
  if (candidate.overwritesFile) rows.push({ label: tr("Replaces"), value: replacement, warning: true });
  rows.push({ label: tr("Tabs"), value: tabChange === "" ? (preview.tabs.length === 0 ? "" : tr("Your tabs stay on.")) : tabChange, tabs: true });
  if (preview.newPermissions.length > 0) rows.push({ label: tr("Permissions"), value: tr("New tabs may ask for %@.", listOf(preview.newPermissions.map(modulePermissionTitle), locale)) });
  if (preview.newNetworkAccess.length > 0) {
    rows.push({ label: tr("Network"), value: tr("New tabs connect to %@.", listOf(preview.newNetworkAccess.map((access) => tr("%@ for %@", access.host, access.purpose)), locale)) });
  }
  rows.push({ label: tr("Today"), value: starterNote });
  if (preview.changesNotchPreviews) rows.push({ label: tr("Closed pill"), value: tr("Shows the previews this kit picks.") });
  if (issues.length > 0) rows.push({ label: tr("Skipped"), value: issues.map(kitIssueDescription).join(" "), warning: true });

  return (
    <Sheet
      badge={kitBadge(kit, catalog, theme)}
      title={isActiveKit ? tr("Update %@", kit.name) : tr("Import %@", kit.name)}
      intro={kit.summary === "" ? tr("Check what this kit changes before you switch to it.") : kit.summary}
      onCancel={onCancel}
      actions={
        <>
          {onBack !== undefined && <SettingsButton title={tr("Back")} help={tr("Change your answers")} onClick={onBack} />}
          <SettingsButton title={tr("Cancel")} help={isActiveKit ? tr("Keep the kit as it was") : tr("Don't import %@", kit.name)} onClick={onCancel} />
          <span className="kit-sheet-spacer" />
          <SettingsButton
            title={isActiveKit ? tr("Keep My Tabs") : tr("Add Only")}
            help={isActiveKit ? tr("Save the update without changing your tabs") : tr("Add %@ to your kits without switching; pick it later under Kit in Settings > Tabs", kit.name)}
            onClick={onAddOnly}
          />
          <SettingsButton
            title={isActiveKit ? tr("Apply Update") : tr("Switch Kit")}
            help={isActiveKit ? tr("Save the update and set your tabs up the way it does") : tr("Add %@ and switch to it", kit.name)}
            primary
            onClick={onApply}
          />
        </>
      }
    >
      <div className="settings-review kit-card">
        {rows.map((row) => (
          <div key={row.label} className="settings-review-row" data-warning={row.warning}>
            <span className="settings-review-label kit-body kit-secondary">
              {row.warning && <Icon id="exclamationmark.triangle.fill" size={12} className="settings-review-warning" />}
              {row.label}
            </span>
            <span className="settings-review-value kit-body">
              {row.tabs && <TabIcons modules={preview.tabs.map((id) => catalog.descriptor(id))} />}
              {row.value !== "" && <span className={row.tabs ? "kit-secondary" : undefined}>{row.value}</span>}
            </span>
          </div>
        ))}
      </div>
      <p className="kit-caption kit-tertiary settings-review-note">{tr("Switching keeps your other settings, and you can undo it under Kit in Settings.")}</p>
    </Sheet>
  );
}
