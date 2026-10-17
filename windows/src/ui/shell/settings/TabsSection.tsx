/*
 * Port of ModulesSettingsPane: the Kit section (pick a kit, undo, and under
 * More options import a kit from a .json file, remove an imported one, run
 * setup again and reset to the kit's defaults), the user's tabs as rows
 * that drag to reorder (each with its module's Options button and a quiet
 * minus that moves it back to the library), and the Add more library. A
 * picked kit with questions asks them in a sheet first; an import shows
 * its questions and then what it changes, and nothing is saved before the
 * user confirms.
 */

import { Suspense, useEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent as ReactKeyboardEvent, type PointerEvent as ReactPointerEvent } from "react";
import type { AppServices } from "../../../app/appServices";
import type { KitSwitchUndo } from "../../../app/settingsStore";
import { constant } from "../../../app/store";
import { useStore } from "../../../app/useStore";
import type { KitAnswers } from "../../../core/kits/kitApplication";
import type { KitImportCandidate } from "../../../core/kits/importedKitStore";
import type { KitManifest } from "../../../core/kits/kitManifest";
import { kitErrorDescription } from "../../../core/kits/kitValidation";
import { tr } from "../../../core/localization/tr";
import type { ModuleDescriptor } from "../../../core/modules/moduleDescriptor";
import type { ModuleID } from "../../../core/modules/moduleId";
import type { ModuleLayout } from "../../../core/modules/moduleLayout";
import { RowReorderDrag } from "../../../core/modules/rowReorderDrag";
import { useTransition } from "../../kit/context";
import { Icon } from "../../kit/Icon";
import { Picker } from "../../kit/Picker";
import { SettingsGroup } from "../../kit/SettingsGroup";
import { Sheet } from "../../kit/Sheet";
import { useTactile } from "../../kit/tactile";
import { Tooltip } from "../../kit/Tooltip";
import { KitImportReviewSheet, KitQuestionsSheet } from "./KitSheets";
import { ModuleIcon, SettingsButton, SettingsMessage } from "./parts";
import type { SettingsSectionProps } from "./sections";
import { SettingsPage } from "./SettingsWindow";

export const TABS_SNAPSHOT_STATES = ["questions", "import", "switched", "more"] as const;

/* The kit sheet: a picked kit's questions, or an import's questions and then what it will change. */
type KitSheet =
  | { readonly step: "questions"; readonly kit: KitManifest; readonly candidate?: KitImportCandidate; readonly answers: KitAnswers }
  | { readonly step: "review"; readonly kit: KitManifest; readonly candidate: KitImportCandidate; readonly answers: KitAnswers };

interface Message {
  readonly text: string;
  readonly warning: boolean;
}

/* A sample import for the snapshot harness: a kit written by someone else, with a question, a Party tab and a starter task. */
const SAMPLE_IMPORT = `{
  "formatVersion": 1,
  "version": "1.2",
  "id": "law-school",
  "name": "Law School",
  "summary": "Case briefs, outlines and a study group.",
  "symbol": "books.vertical",
  "modules": ["study", "planner", "party"],
  "starterTasks": ["Brief tomorrow's cases"],
  "onboarding": [{ "id": "group", "prompt": "Do you study with a group?", "options": [{ "id": "yes", "label": "Yes", "symbol": "person.3.fill", "enables": ["party"] }, { "id": "no", "label": "On my own", "symbol": "person.fill", "disables": ["party"] }] }]
}`;

export function TabsSection({ app, host, snapshotState }: SettingsSectionProps) {
  const store = app.settings;
  const settings = useStore(store.settings);
  useStore(store.kitsChanged);
  const undo = useStore(store.lastKitSwitch);
  const catalog = store.catalog;
  const [message, setMessage] = useState<Message | undefined>(snapshotState === "switched" ? { text: tr("Switched to %@.", store.activeKit?.name ?? tr("the kit")), warning: false } : undefined);
  const [sheet, setSheet] = useState<KitSheet | undefined>(() => {
    const medicine = store.kits.get("medicine");
    return snapshotState === "questions" && medicine !== undefined ? { step: "questions", kit: medicine, answers: {} } : undefined;
  });
  const [options, setOptions] = useState<ModuleID | undefined>(undefined);
  const activeKit = store.activeKit;
  const kitMatch = useMemo(() => (activeKit === undefined ? constant(true) : app.modules.usesKitDefaults(activeKit)), [app.modules, activeKit]);
  const modulesMatchKit = useStore(kitMatch);
  const usesKitDefaults = store.usesKitDefaults && (store.activeKit === undefined || modulesMatchKit);
  const kitName = store.activeKit?.name ?? tr("the kit");

  /* The snapshot harness opens the import review once the sample is read. */
  useEffect(() => {
    if (snapshotState === "import") {
      void store.inspectKit(SAMPLE_IMPORT, "law-school.json").then((inspection) => {
        if (inspection.ok) setSheet({ step: "review", kit: inspection.candidate.kit, candidate: inspection.candidate, answers: { group: new Set(["yes"]) } });
      });
    }
  }, [snapshotState, store]);

  const switchKit = (id: string, answers: KitAnswers) => {
    store.switchKit(id, answers);
    setMessage({ text: tr("Switched to %@.", store.activeKit?.name ?? tr("the kit")), warning: false });
  };

  const pickKit = (id: string) => {
    setMessage(undefined);
    const kit = store.kits.get(id);
    if (id === settings.kitID || kit === undefined) return;
    if (kit.onboarding.length === 0) switchKit(id, {});
    else setSheet({ step: "questions", kit, answers: {} });
  };

  const importKit = async () => {
    setMessage(undefined);
    const file = await host.pickKitFile().catch(() => null);
    if (file === null) return;
    const inspection = await store.inspectKit(file.text, file.fileName);
    if (!inspection.ok) {
      setMessage({ text: kitErrorDescription(inspection.error), warning: true });
      return;
    }
    const candidate = inspection.candidate;
    setSheet(candidate.kit.onboarding.length === 0 ? { step: "review", kit: candidate.kit, candidate, answers: {} } : { step: "questions", kit: candidate.kit, candidate, answers: {} });
  };

  const install = async (candidate: KitImportCandidate, answers: KitAnswers | undefined) => {
    setSheet(undefined);
    const kit = candidate.kit;
    try {
      await store.installKit(candidate, answers);
      let note: string;
      if (answers !== undefined) note = candidate.overwritesFile ? tr("Updated %@ and applied it.", kit.name) : tr("Imported %@ and switched to it.", kit.name);
      else if (kit.id === store.current.kitID) note = tr("Updated %@; your tabs are unchanged.", kit.name);
      else note = tr("Imported %@. Pick it under Kit to use it.", kit.name);
      setMessage({ text: note, warning: false });
    } catch (error) {
      setMessage({ text: tr("Couldn't import %@: %@", kit.name, error instanceof Error ? error.message : String(error)), warning: true });
    }
  };

  const removeKit = async () => {
    const name = store.activeKit?.name ?? tr("The kit");
    try {
      await store.removeActiveKit();
      setMessage({ text: tr("Removed %@.", name), warning: false });
    } catch (error) {
      setMessage({ text: tr("Couldn't remove %@: %@", name, error instanceof Error ? error.message : String(error)), warning: true });
    }
  };

  const undoSwitch = async (undone: KitSwitchUndo) => {
    await store.undoKitSwitch();
    if (!undone.switchedKit) setMessage({ text: tr("Took back the import of %@.", undone.kitName), warning: false });
    else setMessage({ text: tr("Back to %@.", store.activeKit?.name ?? tr("your previous kit")), warning: false });
  };

  const runSetup = () => {
    store.requestSetup();
    /* Setup runs in the island; Settings steps aside. */
    window.close();
  };

  const optionsModule = options === undefined ? undefined : app.modules.get(options);
  const OptionsPane = optionsModule?.SettingsPane;

  return (
    <SettingsPage>
      <SettingsGroup title={tr("Kit")} footer={tr("A kit is a ready-made set of tabs. Switching replaces your tabs and adds its starter tasks to Today.")}>
        <div className="kit-settings-row">
          <div className="kit-settings-row-text">
            <span className="kit-settings-row-label">{tr("Kit")}</span>
            {store.activeKit?.summary !== undefined && store.activeKit.summary !== "" && <span className="kit-settings-row-help kit-user-text">{store.activeKit.summary}</span>}
          </div>
          <div className="kit-settings-row-control">
            <Picker
              label={tr("Kit")}
              help={tr("Switching kits replaces your tabs with the kit's")}
              items={store.kits.kits.map((kit) => ({ id: kit.id, title: kit.name, symbol: kit.symbol }))}
              selected={store.activeKit?.id ?? settings.kitID}
              onSelect={pickKit}
              width={180}
            />
          </div>
        </div>
        {message !== undefined && (
          <div className="kit-settings-row">
            <SettingsMessage
              text={message.text}
              warning={message.warning}
              action={
                !message.warning && undo !== undefined ? (
                  <SettingsButton
                    title={tr("Undo")}
                    help={undo.switchedKit ? tr("Go back to the tabs and kit you had before %@", undo.kitName) : tr("Take back this import of %@", undo.kitName)}
                    onClick={() => void undoSwitch(undo)}
                  />
                ) : undefined
              }
            />
          </div>
        )}
        <KitMoreOptions
          open={snapshotState === "more"}
          canImport={store.canImportKits}
          canRemove={store.canRemoveActiveKit}
          usesKitDefaults={usesKitDefaults}
          kitName={kitName}
          onImport={() => void importKit()}
          onRemove={() => void removeKit()}
          onRunSetup={runSetup}
          onReset={() => store.resetToKitDefaults()}
        />
      </SettingsGroup>

      <SettingsGroup title={tr("Your tabs")} footer={tr("Drag to reorder, or select a tab and press Alt+Up or Alt+Down. At least one tab stays.")}>
        <TabReorderList
          app={app}
          layout={settings.modules}
          onChange={(change) => store.update((value) => ({ ...value, modules: change(value.modules.clone()) }))}
          onOptions={setOptions}
        />
      </SettingsGroup>

      <SettingsGroup title={tr("Add more")}>
        {settings.modules.available.length === 0 ? (
          <div className="kit-settings-row">
            <span className="kit-body kit-secondary">{tr("Every module is already a tab.")}</span>
          </div>
        ) : (
          settings.modules.available.map((id) => (
            <LibraryRow
              key={id}
              module={catalog.descriptor(id)}
              onAdd={() =>
                store.update((value) => {
                  const modules = value.modules.clone();
                  modules.add(id);
                  return { ...value, modules };
                })
              }
            />
          ))
        )}
      </SettingsGroup>

      {sheet?.step === "questions" && (
        <KitQuestionsSheet
          kit={sheet.kit}
          catalog={catalog}
          answers={sheet.answers}
          continueTitle={sheet.candidate === undefined ? undefined : tr("Continue")}
          onCancel={() => setSheet(undefined)}
          onContinue={(answers) => {
            if (sheet.candidate === undefined) {
              setSheet(undefined);
              switchKit(sheet.kit.id, answers);
            } else {
              setSheet({ step: "review", kit: sheet.kit, candidate: sheet.candidate, answers });
            }
          }}
        />
      )}
      {sheet?.step === "review" && (
        <KitImportReviewSheet
          candidate={sheet.candidate}
          preview={store.preview(sheet.candidate.kit, sheet.answers)}
          issues={store.issues(sheet.candidate.kit)}
          isActiveKit={sheet.candidate.kit.id === settings.kitID}
          catalog={catalog}
          onBack={sheet.kit.onboarding.length === 0 ? undefined : () => setSheet({ step: "questions", kit: sheet.kit, candidate: sheet.candidate, answers: sheet.answers })}
          onCancel={() => setSheet(undefined)}
          onAddOnly={() => void install(sheet.candidate, undefined)}
          onApply={() => void install(sheet.candidate, sheet.answers)}
        />
      )}
      {optionsModule !== undefined && OptionsPane !== undefined && (
        <Sheet
          title={optionsModule.descriptor.title}
          onCancel={() => setOptions(undefined)}
          width={560}
          className="settings-options-sheet"
          actions={
            <>
              <span className="kit-sheet-spacer" />
              <SettingsButton title={tr("Done")} help={tr("Close %@ settings", optionsModule.descriptor.title)} primary onClick={() => setOptions(undefined)} />
            </>
          }
        >
          <Suspense fallback={null}>
            <OptionsPane />
          </Suspense>
        </Sheet>
      )}
    </SettingsPage>
  );
}

interface KitMoreOptionsProps {
  readonly open: boolean;
  readonly canImport: boolean;
  readonly canRemove: boolean;
  readonly usesKitDefaults: boolean;
  readonly kitName: string;
  readonly onImport: () => void;
  readonly onRemove: () => void;
  readonly onRunSetup: () => void;
  readonly onReset: () => void;
}

/** The rare kit actions, folded inside the Kit group like the Mac's. */
function KitMoreOptions({ open: initial, canImport, canRemove, usesKitDefaults, kitName, onImport, onRemove, onRunSetup, onReset }: KitMoreOptionsProps) {
  const [open, setOpen] = useState(initial);
  const transition = useTransition("snappy", ["transform"]);
  return (
    <>
      <div className="kit-settings-row settings-kit-more">
        <Tooltip text={open ? tr("Hide the less common settings") : tr("Show the less common settings")}>
          <button type="button" className="kit-more-options-toggle" aria-expanded={open} onClick={() => setOpen((value) => !value)}>
            <Icon id="chevron-forward" size={12} className="kit-more-options-chevron" style={{ transition, transform: open ? "rotate(90deg)" : undefined }} />
            <span>{tr("More options")}</span>
          </button>
        </Tooltip>
      </div>
      {open && (
        <div className="kit-settings-row settings-kit-actions">
          <SettingsButton title={tr("Import Kit…")} help={tr("Add a kit someone shared as a .json file; you see what it changes first")} onClick={onImport} disabled={!canImport} />
          {canRemove && <SettingsButton title={tr("Remove Kit")} help={tr("Delete this imported kit and go back to the default kit")} destructive onClick={onRemove} />}
          <SettingsButton title={tr("Run Setup Again")} help={tr("Pick a kit, your tabs and what they need again, in the island")} onClick={onRunSetup} />
          <span className="kit-sheet-spacer" />
          <SettingsButton
            title={tr("Reset to Kit Defaults")}
            help={usesKitDefaults ? tr("Your setup already matches %@", kitName) : tr("Restore the tabs, previews and focus sound %@ ships with", kitName)}
            disabled={usesKitDefaults}
            onClick={onReset}
          />
        </div>
      )}
    </>
  );
}

const ROW_HEIGHT = 36;

interface TabReorderListProps {
  readonly app: AppServices;
  readonly layout: ModuleLayout;
  readonly onChange: (change: (layout: ModuleLayout) => ModuleLayout) => void;
  readonly onOptions: (id: ModuleID) => void;
}

/**
 * The user's tabs as rows that reorder by dragging, by Alt+Up and Alt+Down
 * on the focused row, and header shortcuts (the Closet's paw) last, which
 * don't drag. While a row is lifted the others slide aside live and an
 * outline marks where it will land; the move is saved on release.
 */
function TabReorderList({ app, layout, onChange, onOptions }: TabReorderListProps) {
  const catalog = app.settings.catalog;
  const tabs = layout.tabs;
  const [drag, setDrag] = useState<{ module: ModuleID; geometry: RowReorderDrag } | undefined>(undefined);
  const dragRef = useRef(drag);
  useEffect(() => {
    dragRef.current = drag;
  }, [drag]);
  const transition = useTransition("snappy", ["transform"]);

  const startDrag = (module: ModuleID, index: number) => (event: ReactPointerEvent<HTMLElement>) => {
    if (event.button !== 0 || (event.target instanceof HTMLElement && event.target.closest("button"))) return;
    const startY = event.clientY;
    let started = false;
    const onMove = (move: PointerEvent) => {
      const translation = move.clientY - startY;
      if (!started && Math.abs(translation) < 4) return;
      started = true;
      const geometry = new RowReorderDrag(index, tabs.length, ROW_HEIGHT, translation);
      setDrag({ module, geometry });
    };
    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      const finished = dragRef.current;
      setDrag(undefined);
      if (finished !== undefined && finished.geometry.movesRow) {
        onChange((value) => {
          value.moveTab(finished.module, finished.geometry.target);
          return value;
        });
      }
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  };

  const step = (module: ModuleID, by: number) => {
    if (!layout.canMoveTab(module, by)) return;
    onChange((value) => {
      value.moveTabBy(module, by);
      return value;
    });
  };

  const indicator = drag !== undefined && drag.geometry.movesRow ? drag.geometry.target : undefined;
  return (
    <div className="settings-tab-list" style={{ "--row-height": `${ROW_HEIGHT}px` } as CSSProperties}>
      {indicator !== undefined && <span className="settings-drop-indicator" style={{ top: indicator * ROW_HEIGHT, height: ROW_HEIGHT }} aria-hidden="true" />}
      {tabs.map((module, index) => (
        <TabRow
          key={module}
          module={catalog.descriptor(module)}
          layout={layout}
          hasOptions={app.modules.get(module)?.SettingsPane !== undefined}
          lifted={drag?.module === module}
          offset={drag?.geometry.offset(index) ?? 0}
          transition={drag?.module === module ? undefined : transition}
          separator={drag === undefined && index < tabs.length - 1}
          onPointerDown={startDrag(module, index)}
          onKeyDown={(event) => {
            if (!event.altKey || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) return;
            event.preventDefault();
            step(module, event.key === "ArrowUp" ? -1 : 1);
          }}
          onOptions={() => onOptions(module)}
          onRemove={() =>
            onChange((value) => {
              value.remove(module);
              return value;
            })
          }
        />
      ))}
      {layout.headerShortcuts.map((module) => (
        <TabRow
          key={module}
          module={catalog.descriptor(module)}
          layout={layout}
          hasOptions={app.modules.get(module)?.SettingsPane !== undefined}
          lifted={false}
          offset={0}
          separator={false}
          isHeaderShortcut
          onOptions={() => onOptions(module)}
          onRemove={() =>
            onChange((value) => {
              value.remove(module);
              return value;
            })
          }
        />
      ))}
    </div>
  );
}

interface TabRowProps {
  readonly module: ModuleDescriptor;
  readonly layout: ModuleLayout;
  readonly hasOptions: boolean;
  readonly lifted: boolean;
  readonly offset: number;
  readonly transition?: string;
  readonly separator: boolean;
  readonly isHeaderShortcut?: boolean;
  readonly onPointerDown?: (event: ReactPointerEvent<HTMLElement>) => void;
  readonly onKeyDown?: (event: ReactKeyboardEvent<HTMLElement>) => void;
  readonly onOptions: () => void;
  readonly onRemove: () => void;
}

/** One of the user's tabs: drag to reorder, open its own settings, or remove it to the library. */
function TabRow({ module, layout, hasOptions, lifted, offset, transition, separator, isHeaderShortcut = false, onPointerDown, onKeyDown, onOptions, onRemove }: TabRowProps) {
  const canRemove = layout.canDisable(module.id);
  const style: CSSProperties = { height: ROW_HEIGHT, transform: offset === 0 ? undefined : `translateY(${offset}px)`, transition, zIndex: lifted ? 1 : undefined };
  return (
    <div
      className="settings-tab-row"
      data-lifted={lifted}
      data-separator={separator}
      data-shortcut={isHeaderShortcut}
      style={style}
      tabIndex={isHeaderShortcut ? -1 : 0}
      onPointerDown={onPointerDown}
      onKeyDown={onKeyDown}
    >
      <Tooltip text={isHeaderShortcut ? "" : tr("Drag to reorder")}>
        <span className="settings-drag-handle" data-hidden={isHeaderShortcut} aria-hidden="true">
          <Icon id="line.3.horizontal" size={12} />
        </span>
      </Tooltip>
      <ModuleIcon module={module} />
      <span className="settings-tab-text">
        <span className="kit-body-emphasis">{module.title}</span>
        {isHeaderShortcut && <span className="kit-caption kit-secondary">{tr("A button at the far right of the tab bar")}</span>}
      </span>
      {hasOptions && <SettingsButton title={tr("Options…")} help={tr("%@ settings", module.title)} onClick={onOptions} className="settings-tab-options" />}
      <RemoveTabButton title={module.title} canRemove={canRemove} onClick={onRemove} />
    </div>
  );
}

/** The quiet minus at the end of a tab row; it turns red on hover so the list doesn't read as a column of buttons. */
function RemoveTabButton({ title, canRemove, onClick }: { title: string; canRemove: boolean; onClick: () => void }) {
  const tactile = useTactile({ disabled: !canRemove });
  const transition = useTransition("snappy", ["color"]);
  return (
    <Tooltip text={canRemove ? tr("Remove %@ from the island; it goes back to Add more", title) : tr("At least one tab must stay")}>
      <button
        type="button"
        className="settings-remove-tab"
        aria-label={tr("Remove %@", title)}
        disabled={!canRemove}
        {...tactile.data}
        {...tactile.handlers}
        style={{ ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", ") }}
        onClick={onClick}
      >
        <Icon id="minus.circle.fill" size={14} />
      </button>
    </Tooltip>
  );
}

/** A module in the Add more library: what it is, in one line, and a button that makes it the last tab. */
function LibraryRow({ module, onAdd }: { module: ModuleDescriptor; onAdd: () => void }) {
  const summary = module.summary ?? module.category.title;
  return (
    <div className="kit-settings-row settings-library-row">
      <ModuleIcon module={module} />
      <span className="settings-tab-text">
        <span className="kit-body-emphasis">{module.title}</span>
        <Tooltip text={summary}>
          <span className="kit-caption kit-secondary settings-library-summary">{summary}</span>
        </Tooltip>
      </span>
      <SettingsButton title={tr("Add")} help={tr("Add %@ as the last tab in the island", module.title)} onClick={onAdd} />
    </div>
  );
}
