/*
 * Port of ConnectionsSettingsPane: the AI choice first (which provider
 * answers Ask, Plan my day and Refine, and the key it needs, kept in
 * Credential Manager), then one row per app or setting the current tabs
 * use, each with a live light and the one button that fixes its state, a
 * "Something not working?" troubleshooter, and under More options the AI
 * model. The Calendar row's Set up adds and removes ICS feeds by name and
 * color; Do not disturb opens Windows' notification settings, since
 * Windows lets no app switch it.
 */

import { useEffect, useMemo, useState } from "react";
import { aiService } from "../../../../app/aiService";
import { ModuleContext } from "../../../../app/context";
import { useStore } from "../../../../app/useStore";
import { type AIProviderID, consentMessage, consentTitle, defaultModel, displayName, isCommandLineTool, requiresAPIKey, setupPage, setupPageTitle, setupSummary, vendorName } from "../../../../core/ai/aiProviderID";
import { type AISetupState } from "../../../../core/ai/aiProviderFactory";
import { activeProvider, choose, modelFor, needsConsent, setModel } from "../../../../core/ai/aiSettings";
import type { CalendarSubscription } from "../../../../core/calendar/calendarSource";
import { feedURL, safeSubscriptionID } from "../../../../core/calendar/calendarSource";
import { connectionTitle, connectionSymbol, connectionUnlocks, type ConnectionKind } from "../../../../core/connections/connectionKind";
import { diagnosisDetails, diagnosisVerdict, type ConnectionDiagnosis } from "../../../../core/connections/connectionDiagnosis";
import { actionTitle, isConnected, lightTitle, settingsURL, type ConnectionAction, type ConnectionGuide, type ConnectionLight, type ConnectionStatus } from "../../../../core/connections/connectionStatus";
import { guideWalkthrough, stepActionTitle, walkthroughWaiting, type ConnectionStepAction } from "../../../../core/connections/connectionWalkthrough";
import { joinSentences } from "../../../../core/formatting/sentences";
import { tr } from "../../../../core/localization/tr";
import { MODULE_IDS } from "../../../../core/modules/moduleId";
import type { EventColor } from "../../../../core/planner/upcomingEvent";
import { calendarSource } from "../../../../modules/planner/calendarServices";
import { partyState } from "../../../../modules/party/partyServices";
import { Icon } from "../../../kit/Icon";
import { Spinner } from "../../../kit/Loading";
import { Picker } from "../../../kit/Picker";
import { SettingsGroup, SettingsRow } from "../../../kit/SettingsGroup";
import { Sheet } from "../../../kit/Sheet";
import { TextField } from "../../../kit/TextField";
import { Tooltip } from "../../../kit/Tooltip";
import { SettingsButton, SettingsMessage } from "../parts";
import type { SettingsSectionProps } from "../sections";
import { SettingsPage } from "../SettingsWindow";
import { ConnectionsStore, windowsConnections } from "./connectionsStore";

export const CONNECTIONS_SNAPSHOT_STATES = ["troubleshoot", "calendar", "walkthrough", "consent", "more"] as const;

/** The tabs with AI features; Connections shows the AI choice while one is on. */
const AI_FEATURE_MODULES: readonly string[] = [MODULE_IDS.claudeAsk, MODULE_IDS.planner, MODULE_IDS.schedule];

/* The colors a new calendar can take, as Today draws its events. */
const CALENDAR_COLORS: readonly { id: string; color: EventColor }[] = [
  { id: "blue", color: { red: 0.3, green: 0.6, blue: 1 } },
  { id: "purple", color: { red: 0.66, green: 0.55, blue: 1 } },
  { id: "pink", color: { red: 1, green: 0.5, blue: 0.7 } },
  { id: "orange", color: { red: 1, green: 0.62, blue: 0.26 } },
  { id: "green", color: { red: 0.3, green: 0.8, blue: 0.5 } },
  { id: "teal", color: { red: 0.3, green: 0.8, blue: 0.85 } },
];

type Sheet =
  | { readonly kind: "troubleshoot"; readonly connection: ConnectionKind }
  | { readonly kind: "walkthrough"; readonly guide: ConnectionGuide }
  | { readonly kind: "calendar" }
  | { readonly kind: "consent"; readonly provider: AIProviderID };

function lightTint(light: ConnectionLight): string {
  switch (light) {
    case "connected":
      return "var(--success)";
    case "needsStep":
      return "var(--warning)";
    case "notSetUp":
      return "rgb(80 150 255)";
    case "checking":
    case "notInstalled":
    case "unavailable":
      return "var(--tertiary-text)";
  }
}

function lightHelp(light: ConnectionLight): string {
  switch (light) {
    case "checking":
      return tr("Tabbi is checking this right now");
    case "connected":
      return tr("This works. Nothing to do.");
    case "needsStep":
      return tr("Almost there: one thing left to do");
    case "notSetUp":
      return tr("Not connected to Tabbi yet");
    case "notInstalled":
      return tr("The app this needs isn't on this PC");
    case "unavailable":
      return tr("Windows has no way for Tabbi to do this");
  }
}

function actionHelp(action: ConnectionAction, kind: ConnectionKind): string {
  switch (action.kind) {
    case "download":
      return tr("Open the official page to download %@", action.app.name);
    case "openApp":
      return tr("Open %@, then Tabbi checks again", action.app.name);
    case "showGuide":
      return tr("Walk through the steps to connect %@", connectionTitle(kind));
    case "openSettings":
      return tr("Open the right page in Windows Settings");
    case "checkAgain":
      return tr("Check %@ again", connectionTitle(kind));
    case "setUp":
      return tr("Set up %@", connectionTitle(kind));
    case "copyFriendCode":
      return tr("Copy your friend code to send to a friend");
  }
}

export function ConnectionsSection({ app, host, snapshotState }: SettingsSectionProps) {
  const settings = useStore(app.settings.settings);
  const context = useMemo(() => new ModuleContext("app", app.environment), [app]);
  const store = useMemo(
    () =>
      new ConnectionsStore({
        host,
        context,
        calendar: calendarSource(new ModuleContext(MODULE_IDS.planner, app.environment)),
        party: partyState(new ModuleContext(MODULE_IDS.party, app.environment)),
        isDemo: app.environment.runMode.isDemo || app.environment.runMode.isSnapshot,
      }),
    [app, host, context],
  );
  const state = useStore(store);
  const enabled = settings.modules.enabled;
  const kinds = useMemo(() => windowsConnections(enabled), [enabled]);
  const showsAI = enabled.some((id) => AI_FEATURE_MODULES.includes(id));
  const [sheet, setSheet] = useState<Sheet | undefined>(() => {
    switch (snapshotState) {
      case "troubleshoot":
        return { kind: "troubleshoot", connection: "anki" };
      case "calendar":
        return { kind: "calendar" };
      case "walkthrough":
        return { kind: "walkthrough", guide: "ankiAddOn" };
      case "consent":
        return { kind: "consent", provider: "anthropic" };
      default:
        return undefined;
    }
  });

  useEffect(() => {
    store.beginWatching(kinds);
    return () => store.endWatching(kinds);
  }, [store, kinds]);

  /* A fix made in another app turns green on return. */
  useEffect(() => {
    const onFocus = () => store.refresh(kinds);
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [store, kinds]);

  const perform = (action: ConnectionAction, kind: ConnectionKind) => {
    switch (action.kind) {
      case "download":
        if (action.app.downloadPage !== undefined) void host.openURL(action.app.downloadPage);
        return;
      case "openApp":
        void host.openApp(action.app.id).then(() => window.setTimeout(() => store.refresh([kind]), 3000));
        return;
      case "showGuide":
        setSheet({ kind: "walkthrough", guide: action.guide });
        return;
      case "openSettings":
        void host.openURL(settingsURL(action.link));
        return;
      case "checkAgain":
        store.refresh([kind]);
        return;
      case "setUp":
        if (kind === "calendar") setSheet({ kind: "calendar" });
        else store.refresh([kind]);
        return;
      case "copyFriendCode":
        void navigator.clipboard?.writeText(action.code);
        return;
    }
  };

  const status = (kind: ConnectionKind): ConnectionStatus =>
    state.diagnoses[kind]?.status ?? { light: "checking", headline: tr("Checking %@", connectionTitle(kind)), detail: tr("This takes a second.") };
  const aiProvider = showsAI ? activeProvider(settings.ai, true) : undefined;

  return (
    <SettingsPage
      moreOpen={snapshotState === "more"}
      moreOptions={aiProvider === undefined ? undefined : <AIModelGroup app={app} provider={aiProvider} />}
    >
      {showsAI && <AIGroup app={app} host={host} onConsent={(provider) => setSheet({ kind: "consent", provider })} />}
      <SettingsGroup title={tr("Apps and permissions")} footer={tr("Fixed something in another app? Come back here and the light updates by itself.")}>
        {kinds.length === 0 ? (
          <div className="kit-settings-row">
            <span className="kit-body kit-secondary">{tr("None of your tabs need another app right now.")}</span>
          </div>
        ) : (
          kinds.map((kind) => (
            <ConnectionRow key={kind} kind={kind} status={status(kind)} perform={(action) => perform(action, kind)} troubleshoot={() => setSheet({ kind: "troubleshoot", connection: kind })} />
          ))
        )}
      </SettingsGroup>

      {sheet?.kind === "troubleshoot" && (
        <TroubleshootSheet
          kind={sheet.connection}
          diagnosis={state.diagnoses[sheet.connection]}
          checkedAt={state.checkedAt[sheet.connection]}
          app={app}
          onCancel={() => setSheet(undefined)}
          onAction={(action) => {
            setSheet(undefined);
            perform(action, sheet.connection);
          }}
        />
      )}
      {sheet?.kind === "walkthrough" && (
        <WalkthroughSheet
          guide={sheet.guide}
          executable={state.diagnoses.claude?.executable}
          onCancel={() => setSheet(undefined)}
          onStart={(action) => {
            if (action.kind === "openPage") void host.openURL(action.url);
            else {
              if (action.kind === "copyAndOpen") void navigator.clipboard?.writeText(action.text);
              void host.openApp(action.app.id);
            }
          }}
        />
      )}
      {sheet?.kind === "calendar" && <CalendarSheet store={store} onCancel={() => setSheet(undefined)} />}
      {sheet?.kind === "consent" && (
        <Sheet
          title={consentTitle(sheet.provider)}
          onCancel={() => setSheet(undefined)}
          width={440}
          actions={
            <>
              <SettingsButton title={tr("Cancel")} help={tr("Keep sending nothing")} onClick={() => setSheet(undefined)} />
              <span className="kit-sheet-spacer" />
              <SettingsButton
                title={tr("Allow")}
                help={tr("Let %@ answer your AI requests", vendorName(sheet.provider) ?? displayName(sheet.provider))}
                primary
                onClick={() => {
                  app.settings.update((value) => ({ ...value, ai: choose(value.ai, sheet.provider) }));
                  setSheet(undefined);
                }}
              />
            </>
          }
        >
          <div className="settings-consent kit-body">
            {consentMessage(sheet.provider, app.environment.edition.name)
              .split("\n")
              .map((line, index) => (
                <p key={index}>{line}</p>
              ))}
          </div>
        </Sheet>
      )}
    </SettingsPage>
  );
}

interface RowProps {
  readonly kind: ConnectionKind;
  readonly status: ConnectionStatus;
  readonly perform: (action: ConnectionAction) => void;
  readonly troubleshoot: () => void;
}

/** One connection: what it unlocks, its light, where it stands and the button for the next step. */
function ConnectionRow({ kind, status, perform, troubleshoot }: RowProps) {
  const tint = lightTint(status.light);
  const button = status.action ?? status.suggestion;
  return (
    <div className="settings-connection">
      <span className="settings-connection-symbol" style={{ background: tint }} aria-hidden="true">
        <Icon id={connectionSymbol(kind)} size={14} />
      </span>
      <div className="settings-connection-text">
        <div className="settings-connection-head">
          <span className="kit-body-emphasis">{connectionTitle(kind)}</span>
          <Tooltip text={lightHelp(status.light)}>
            <span className="settings-light" style={{ color: status.light === "connected" ? tint : "var(--secondary-text)", background: `color-mix(in srgb, ${tint} 14%, transparent)` }}>
              {status.light === "checking" ? <Spinner size={8} lineWidth={1.5} /> : <span className="settings-light-dot" style={{ background: tint }} />}
              <span>{lightTitle(status.light)}</span>
            </span>
          </Tooltip>
        </div>
        <span className="kit-caption kit-secondary">{connectionUnlocks(kind)}</span>
        {!isConnected(status) && (
          <span className="kit-caption settings-connection-detail">
            <span className="settings-connection-headline">{status.headline}</span>. {status.detail}
          </span>
        )}
        {isConnected(status) && status.suggestion?.kind === "copyFriendCode" && (
          <span className="kit-caption settings-connection-detail">
            {tr("Your friend code: %@", "")}
            <span className="settings-friend-code">{status.suggestion.code}</span>
          </span>
        )}
        <Tooltip text={tr("Run a checkup on %@ and see what's wrong, in plain words", connectionTitle(kind))}>
          <button type="button" className="settings-link kit-caption" onClick={troubleshoot}>
            {tr("Something not working?")}
          </button>
        </Tooltip>
      </div>
      {button !== undefined && <SettingsButton title={actionTitle(button)} help={actionHelp(button, kind)} primary={status.action !== undefined} onClick={() => perform(button)} className="settings-connection-action" />}
    </div>
  );
}

interface TroubleshootProps {
  readonly kind: ConnectionKind;
  readonly diagnosis: ConnectionDiagnosis | undefined;
  readonly checkedAt: number | undefined;
  readonly app: SettingsSectionProps["app"];
  readonly onCancel: () => void;
  readonly onAction: (action: ConnectionAction) => void;
}

/** The "Something not working?" troubleshooter: the verdict, every check in plain words, Copy details and the row's button. */
function TroubleshootSheet({ kind, diagnosis, checkedAt, app, onCancel, onAction }: TroubleshootProps) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    if (diagnosis === undefined) return;
    const text = diagnosisDetails(diagnosis, {
      appVersion: app.environment.startup.appVersion,
      systemVersion: app.environment.startup.systemVersion,
      checkedAt: checkedAt ?? app.environment.now(),
      timeZone: app.environment.timeZone(),
    });
    void navigator.clipboard?.writeText(text);
    setCopied(true);
  };
  const action = diagnosis?.status.action;
  return (
    <Sheet
      title={connectionTitle(kind)}
      intro={diagnosis === undefined ? tr("Tabbi is still checking. This takes a second.") : diagnosisVerdict(diagnosis)}
      onCancel={onCancel}
      width={480}
      actions={
        <>
          <SettingsButton title={copied ? tr("Copied") : tr("Copy details")} help={tr("Copy these checks to paste into a message to support")} onClick={copy} disabled={diagnosis === undefined} />
          <span className="kit-sheet-spacer" />
          <SettingsButton title={tr("Done")} help={tr("Close the checkup")} onClick={onCancel} primary={action === undefined} />
          {action !== undefined && <SettingsButton title={actionTitle(action)} help={actionHelp(action, kind)} primary onClick={() => onAction(action)} />}
        </>
      }
    >
      <div className="settings-checks kit-card">
        {(diagnosis?.checks ?? []).map((check, index) => (
          <div key={index} className="settings-check" data-outcome={check.outcome}>
            <span className="settings-check-mark">
              <Icon id={check.outcome === "passed" ? "checkmark.circle.fill" : check.outcome === "failed" ? "exclamationmark.triangle.fill" : check.outcome === "note" ? "info.circle" : "circle"} size={14} />
            </span>
            <span className="settings-check-text">
              <span className="kit-body-emphasis">{check.question}</span>
              <span className="kit-caption kit-secondary">{check.answer}</span>
            </span>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

/** A walkthrough for a step Tabbi can't do by itself, with the one button that starts it. */
function WalkthroughSheet({ guide, executable, onCancel, onStart }: { guide: ConnectionGuide; executable: string | undefined; onCancel: () => void; onStart: (action: ConnectionStepAction) => void }) {
  const walkthrough = guideWalkthrough(guide, executable);
  return (
    <Sheet
      title={walkthrough.title}
      intro={walkthrough.intro}
      onCancel={onCancel}
      width={480}
      actions={
        <>
          {walkthrough.learnMore !== undefined && (
            <Tooltip text={walkthrough.learnMore}>
              <a className="settings-link kit-caption" href={walkthrough.learnMore} target="_blank" rel="noreferrer">
                {tr("Learn more")}
              </a>
            </Tooltip>
          )}
          <span className="kit-sheet-spacer" />
          <SettingsButton title={tr("Done")} help={tr("Close the walkthrough")} onClick={onCancel} />
          <SettingsButton title={stepActionTitle(walkthrough.start)} help={walkthroughWaiting()} primary onClick={() => onStart(walkthrough.start)} />
        </>
      }
    >
      <ol className="settings-steps">
        {walkthrough.steps.map((step, index) => (
          <li key={index} className="settings-step">
            <span className="settings-step-number kit-caption">{index + 1}</span>
            <span className="settings-step-text">
              <span className="kit-body">{step.text}</span>
              {step.copyable !== undefined && <code className="settings-step-copyable kit-caption">{step.copyable}</code>}
            </span>
          </li>
        ))}
      </ol>
      <p className="kit-caption kit-tertiary">{walkthroughWaiting()}</p>
    </Sheet>
  );
}

/** The Calendar row's sheet: the saved ICS feeds, each removable, and a form to add one by name, link and color. */
function CalendarSheet({ store, onCancel }: { store: ConnectionsStore; onCancel: () => void }) {
  const demo = store.isDemo;
  const [subscriptions, setSubscriptions] = useState<CalendarSubscription[] | undefined>(() =>
    demo
      ? [
          { id: "classes", name: "Classes", url: "https://calendar.google.com/calendar/ical/classes/basic.ics", color: CALENDAR_COLORS[0]?.color ?? { red: 1, green: 1, blue: 1 } },
          { id: "holidays", name: "Holidays", url: "https://example.com/holidays.ics", color: CALENDAR_COLORS[4]?.color ?? { red: 1, green: 1, blue: 1 } },
        ]
      : undefined,
  );
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [color, setColor] = useState(0);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (demo) return;
    let live = true;
    void store.subscriptions().then((list) => {
      if (live) setSubscriptions(list);
    });
    return () => {
      live = false;
    };
  }, [store, demo]);

  const save = async (next: CalendarSubscription[]) => {
    setSubscriptions(next);
    if (!demo) await store.setSubscriptions(next);
  };
  const add = () => {
    const url = feedURL(address);
    const cleaned = name.trim();
    if (url === undefined) {
      setProblem(tr("Not a calendar link. Copy the iCal or ICS address from your calendar's settings."));
      return;
    }
    if (cleaned === "") {
      setProblem(tr("Give the calendar a name."));
      return;
    }
    setProblem(undefined);
    const id = safeSubscriptionID(`${cleaned.toLowerCase().replace(/\s+/g, "-")}-${Date.now().toString(36)}`);
    void save([...(subscriptions ?? []), { id, name: cleaned, url, color: CALENDAR_COLORS[color]?.color ?? { red: 1, green: 1, blue: 1 } }]);
    setName("");
    setAddress("");
  };
  const cssColor = (value: EventColor) => `rgb(${Math.round(value.red * 255)} ${Math.round(value.green * 255)} ${Math.round(value.blue * 255)})`;
  return (
    <Sheet
      title={tr("Calendar")}
      intro={tr("Tabbi reads calendars from their links. Copy the iCal or ICS address from Google, Outlook or iCloud and paste it here.")}
      onCancel={onCancel}
      width={500}
      actions={
        <>
          <span className="kit-sheet-spacer" />
          <SettingsButton title={tr("Done")} help={tr("Close the calendar list")} primary onClick={onCancel} />
        </>
      }
    >
      {subscriptions !== undefined && subscriptions.length > 0 && (
        <div className="settings-feeds kit-card">
          {subscriptions.map((feed) => (
            <div key={feed.id} className="settings-feed">
              <span className="settings-feed-color" style={{ background: cssColor(feed.color) }} />
              <span className="settings-feed-text">
                <span className="kit-body-emphasis">{feed.name}</span>
                <Tooltip text={feed.url}>
                  <span className="kit-caption kit-tertiary settings-feed-url">{feed.url}</span>
                </Tooltip>
              </span>
              <SettingsButton title={tr("Remove")} help={tr("Remove %@ from Tabbi", feed.name)} destructive onClick={() => void save(subscriptions.filter((other) => other.id !== feed.id))} />
            </div>
          ))}
        </div>
      )}
      <div className="settings-feed-form">
        <TextField value={name} onChange={setName} label={tr("Calendar name")} placeholder={tr("Calendar name")} width={140} />
        <TextField value={address} onChange={setAddress} onSubmit={add} label={tr("Calendar link")} placeholder="https://calendar.google.com/calendar/ical/.../basic.ics" symbol="link" width={240} />
        <span className="settings-feed-colors" role="radiogroup" aria-label={tr("Color")}>
          {CALENDAR_COLORS.map((entry, index) => (
            <Tooltip key={entry.id} text={tr("Color")}>
              <button type="button" role="radio" aria-checked={index === color} className="settings-feed-swatch" data-selected={index === color} style={{ background: cssColor(entry.color) }} onClick={() => setColor(index)} />
            </Tooltip>
          ))}
        </span>
        <SettingsButton title={tr("Add")} help={tr("Add this calendar to Tabbi")} primary onClick={add} />
      </div>
      {problem !== undefined && <SettingsMessage text={problem} warning />}
    </Sheet>
  );
}

/** Settings > Connections > AI: which provider answers, and the one thing it still needs (a key). */
function AIGroup({ app, host, onConsent }: { app: SettingsSectionProps["app"]; host: SettingsSectionProps["host"]; onConsent: (provider: AIProviderID) => void }) {
  const store = app.settings;
  const settings = useStore(store.settings);
  const ai = useMemo(() => aiService(new ModuleContext("app", app.environment)), [app]);
  const [setup, setSetup] = useState<AISetupState>({ kind: "notChosen" });
  const [draft, setDraft] = useState("");
  const [saveFailed, setSaveFailed] = useState(false);
  const [generation, setGeneration] = useState(0);
  const appName = app.environment.edition.name;
  useEffect(() => {
    let live = true;
    void ai.setupState().then((state) => {
      if (live) setSetup(state);
    });
    return () => {
      live = false;
    };
  }, [ai, settings.ai, generation]);
  const provider = setup.kind === "notChosen" ? undefined : setup.provider;
  const pick = (id: AIProviderID | "none") => {
    const next = id === "none" ? undefined : id;
    if (next !== undefined && needsConsent(settings.ai, next)) onConsent(next);
    else store.update((value) => ({ ...value, ai: choose(value.ai, next) }));
  };
  const saveKey = async (key: string | undefined) => {
    if (provider === undefined) return;
    try {
      await ai.keys.setKey(key, provider);
      setDraft("");
      setSaveFailed(false);
    } catch {
      setSaveFailed(true);
    }
    setGeneration((value) => value + 1);
  };
  let footer: string;
  if (provider === undefined) {
    const saved = settings.ai.provider;
    footer =
      saved !== undefined && ai.availableProviders.includes(saved) && needsConsent(settings.ai, saved)
        ? tr("Pick %@ again to allow it to receive your AI requests. %@ sends nothing until you do.", displayName(saved), appName)
        : tr("Pick one to use Ask, Plan my day and Refine. %@ sends nothing until you do.", appName);
  } else {
    const hint = requiresAPIKey(provider) ? tr("Your key stays in Windows Credential Manager.") : provider === "ollama" ? tr("With Ollama open, run ollama pull %@ in PowerShell once.", modelFor(settings.ai, provider)) : "";
    const vendor = vendorName(provider);
    const recipient = vendor === undefined ? "" : tr("Sends what you ask to %@.", vendor);
    footer = joinSentences([provider === "ollama" ? tr("Free and offline: runs a model on this PC.") : setupSummary(provider), recipient, hint]);
  }
  const page = provider === undefined ? undefined : setupPage(provider);
  const pageButton =
    provider === undefined || page === undefined ? null : (
      <SettingsButton title={setupPageTitle(provider)} help={tr("Open %@ in your browser", new URL(page).host)} onClick={() => void host.openURL(page)} />
    );
  return (
    <SettingsGroup title={tr("AI")} footer={footer}>
      <SettingsRow label={tr("Answers from")}>
        <Picker<AIProviderID | "none">
          label={tr("Answers from")}
          help={tr("The AI that answers Ask, Plan my day and Refine")}
          items={[{ id: "none", title: tr("None") }, ...ai.availableProviders.map((id) => ({ id, title: displayName(id), caption: id === "ollama" ? tr("Free and offline: runs a model on this PC.") : setupSummary(id) }))]}
          selected={provider ?? "none"}
          onSelect={pick}
          width={180}
        />
      </SettingsRow>
      {provider !== undefined && requiresAPIKey(provider) && (
        <SettingsRow label={tr("API key")} help={saveFailed ? tr("Credential Manager didn't save the key. Try again.") : undefined}>
          {setup.kind === "ready" ? (
            <>
              <span className="settings-status kit-caption kit-secondary">
                <Icon id="checkmark.circle.fill" size={12} style={{ color: "var(--success)" }} />
                <span>{tr("Saved in Credential Manager")}</span>
              </span>
              <SettingsButton title={tr("Remove")} help={tr("Delete this key from Credential Manager")} destructive onClick={() => void saveKey(undefined)} />
            </>
          ) : (
            <>
              <TextField value={draft} onChange={setDraft} onSubmit={() => void saveKey(draft)} label={tr("API key")} placeholder={tr("Paste your key")} help={tr("Your %@ key. It is kept in Credential Manager.", displayName(provider))} secure width={160} symbol="key" />
              <SettingsButton title={tr("Save")} help={tr("Save this key in Credential Manager")} primary disabled={draft.trim() === ""} onClick={() => void saveKey(draft)} />
              {pageButton}
            </>
          )}
        </SettingsRow>
      )}
      {provider !== undefined && !requiresAPIKey(provider) && !isCommandLineTool(provider) && (
        <SettingsRow label={tr("App")}>
          <span className="kit-body kit-secondary">{tr("Runs on this PC")}</span>
          {pageButton}
        </SettingsRow>
      )}
    </SettingsGroup>
  );
}

/** Settings > Connections > More options: the model the chosen provider uses. Blank means the default. */
function AIModelGroup({ app, provider }: { app: SettingsSectionProps["app"]; provider: AIProviderID }) {
  const store = app.settings;
  const settings = useStore(store.settings);
  const [draft, setDraft] = useState(settings.ai.models[provider] ?? "");
  const commit = () => store.update((value) => ({ ...value, ai: setModel(value.ai, draft, provider) }));
  const fallback = defaultModel(provider);
  return (
    <SettingsGroup title={tr("AI model")} footer={tr("Leave empty for the default, which is quick and inexpensive.")}>
      <SettingsRow label={tr("Model")}>
        <TextField
          value={draft}
          onChange={setDraft}
          onSubmit={commit}
          onBlur={commit}
          label={tr("Model")}
          placeholder={fallback === "" ? tr("The tool's own default") : fallback}
          help={tr("The model %@ uses. Leave empty for the default.", displayName(provider))}
          width={220}
        />
      </SettingsRow>
    </SettingsGroup>
  );
}
