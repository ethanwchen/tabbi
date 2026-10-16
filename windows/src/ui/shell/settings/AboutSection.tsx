/*
 * Port of AboutSettingsPane: the app glyph, the version, what Tabbi is,
 * the GitHub and support links, the Suggest link with the app and Windows
 * versions filled in, Check for Updates with its opt-in automatic check
 * (Windows only, the Mac has Sparkle), the crash report choice (an "always send" switch
 * exists, but this build sends nothing yet), the licenses, and the pricing
 * sentence, word for word.
 */

import { useCallback, useEffect, useState } from "react";
import { useStore } from "../../../app/useStore";
import { CRASH_REPORT_CONSENTS, crashReportConsentTitle, type CrashReportConsent } from "../../../core/feedback/crashReporting";
import { DiagnosticEnvironment } from "../../../core/feedback/diagnosticEnvironment";
import { feedbackLinkTitle, feedbackLinkURL } from "../../../core/feedback/feedbackLink";
import { tr } from "../../../core/localization/tr";
import { MODULE_IDS } from "../../../core/modules/moduleId";
import { SupportContact } from "../../../core/party/partyModeration";
import { Icon } from "../../kit/Icon";
import { Picker } from "../../kit/Picker";
import { SettingsGroup, SettingsRow } from "../../kit/SettingsGroup";
import { Sheet } from "../../kit/Sheet";
import { Toggle } from "../../kit/Toggle";
import { Tooltip } from "../../kit/Tooltip";
import glyph from "../../../../../docs/brand/assets/tabbi-glyph-256.png";
import { SettingsButton } from "./parts";
import type { UpdateInfo } from "../../../host/host";
import type { SettingsSectionProps } from "./sections";
import { SettingsPage } from "./SettingsWindow";

export const ABOUT_SNAPSHOT_STATES = ["licenses"] as const;

const REPOSITORY = "https://github.com/ethanwchen/tabbi";

/** The pricing promise, exactly as every Tabbi surface states it. */
export const PRICING_SENTENCE = "Tabbi is free. Optional extras may come later, and the core will stay free.";

/* What ships in this build besides Tabbi's own code, with each license. */
const LICENSES: readonly { name: string; license: string; url: string }[] = [
  { name: "Tabbi", license: "MIT License", url: `${REPOSITORY}/blob/main/LICENSE` },
  { name: "Tabbi art (pets, outfits, icons)", license: "Assets license", url: `${REPOSITORY}/blob/main/ASSETS-LICENSE.md` },
  { name: "Tauri", license: "MIT or Apache-2.0", url: "https://github.com/tauri-apps/tauri" },
  { name: "React", license: "MIT License", url: "https://github.com/facebook/react" },
  { name: "Ajv", license: "MIT License", url: "https://github.com/ajv-validator/ajv" },
  { name: "windows-rs", license: "MIT or Apache-2.0", url: "https://github.com/microsoft/windows-rs" },
  { name: "serde", license: "MIT or Apache-2.0", url: "https://github.com/serde-rs/serde" },
];

function LinkRow({ title, symbol, help, href, host, copies = false }: { title: string; symbol: string; help: string; href: string; host: SettingsSectionProps["host"]; copies?: boolean }) {
  /* The host opens https links only; a mail address is copied for the user's own mail app instead. */
  const open = () => (copies ? void navigator.clipboard?.writeText(href) : void host.openUrl(href));
  return (
    <Tooltip text={help}>
      <button type="button" className="settings-about-link" onClick={open}>
        <Icon id={symbol} size={13} />
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}

/* Where a check for updates stands. */
type UpdateState = { kind: "idle" } | { kind: "checking" } | { kind: "latest" } | { kind: "available"; update: UpdateInfo } | { kind: "installing" } | { kind: "failed" };

function updateStatus(state: UpdateState): string | undefined {
  switch (state.kind) {
    case "idle":
      return undefined;
    case "checking":
      return tr("Checking for updates...");
    case "latest":
      return tr("You have the latest version.");
    case "available":
      return tr("Version %@ is available.", state.update.version);
    case "installing":
      return tr("Installing the update. Tabbi restarts when it is done.");
    case "failed":
      return tr("Could not check for updates. Try again later.");
  }
}

/*
 * Check for Updates and the opt-in automatic check. A check contacts
 * GitHub, so nothing is checked until the user asks here or in the tray,
 * or turns on Check automatically (off by default).
 */
function UpdatesGroup({ host }: { host: SettingsSectionProps["host"] }) {
  const [state, setState] = useState<UpdateState>({ kind: "idle" });
  const [automatic, setAutomatic] = useState(false);

  const check = useCallback(() => {
    setState({ kind: "checking" });
    host.updateCheck().then(
      (update) => setState(update ? { kind: "available", update } : { kind: "latest" }),
      () => setState({ kind: "failed" }),
    );
  }, [host]);
  const install = () => {
    setState({ kind: "installing" });
    host.updateInstall().catch(() => setState({ kind: "failed" }));
  };

  useEffect(() => {
    let live = true;
    void host.updateAutoCheck().then((on) => live && setAutomatic(on));
    /* The tray's Check for Updates opens this page and asks it to check. */
    const take = () => void host.updateTakeRequest().then((asked) => asked && check());
    take();
    const stop = host.onUpdateRequest(take);
    return () => {
      live = false;
      stop();
    };
  }, [host, check]);

  const busy = state.kind === "checking" || state.kind === "installing";
  return (
    <SettingsGroup title={tr("Updates")} footer={tr("Checking for updates contacts GitHub. Tabbi checks only when you ask, unless Check automatically is on.")}>
      <SettingsRow label={tr("Updates")} help={updateStatus(state)}>
        {state.kind === "available" ? (
          <SettingsButton title={tr("Install and Restart")} help={tr("Download version %@, install it and restart Tabbi", state.update.version)} primary onClick={install} />
        ) : (
          <SettingsButton title={tr("Check for Updates")} help={tr("Ask GitHub whether a newer version of Tabbi is out")} disabled={busy} onClick={check} />
        )}
      </SettingsRow>
      <SettingsRow label={tr("Check automatically")} help={tr("Checks once each time Tabbi starts.")}>
        <Toggle
          isOn={automatic}
          onChange={(on) => {
            setAutomatic(on);
            host.setUpdateAutoCheck(on).catch(() => setAutomatic(!on));
          }}
          label={tr("Check automatically")}
          help={tr("Check GitHub for a newer version each time Tabbi starts")}
        />
      </SettingsRow>
    </SettingsGroup>
  );
}

export function AboutSection({ app, host, snapshotState }: SettingsSectionProps) {
  const consent = useStore(app.settings.crashReportConsent);
  const [licenses, setLicenses] = useState(snapshotState === "licenses");
  const startup = app.environment.startup;
  const edition = app.environment.edition;
  const environment = new DiagnosticEnvironment(startup.appVersion, startup.systemVersion, edition.id);
  const version = startup.appVersion === "development" ? tr("Development build") : tr("Version %@", startup.appVersion);
  const offersParty = app.settings.catalog.contains(MODULE_IDS.party);
  return (
    <SettingsPage>
      <div className="settings-about">
        <img className="settings-about-glyph" src={glyph} alt="" width={88} height={88} />
        <div className="settings-about-name">{edition.name}</div>
        <div className="settings-about-version kit-caption kit-secondary">{version}</div>
        <p className="settings-about-blurb kit-body kit-secondary">{tr("A cozy everyday companion: a cat at the top of your screen, with your tabs one click away.")}</p>
        <div className="settings-about-links">
          <LinkRow title={tr("View on GitHub")} symbol="arrow.up.forward.app" help={REPOSITORY} href={REPOSITORY} host={host} />
          <LinkRow
            title={SupportContact.reportLine()}
            symbol="envelope"
            help={offersParty ? tr("Copies the address. Email the %@ team about a bug, a person in Party or anything else", edition.name) : tr("Copies the address. Email the %@ team about a bug or anything else", edition.name)}
            href={SupportContact.email}
            host={host}
            copies
          />
          <LinkRow title={feedbackLinkTitle()} symbol="lightbulb" help={tr("Opens the Suggest page with your app version, Windows version and edition filled in")} href={feedbackLinkURL(environment)} host={host} />
        </div>
      </div>

      <UpdatesGroup host={host} />

      <SettingsGroup footer={tr("Nothing is sent in this build yet. When crash reports arrive, they go only with your say-so and never hold typed text, names or file paths.")}>
        <SettingsRow label={tr("Crash reports")}>
          <Picker<CrashReportConsent>
            label={tr("Crash reports")}
            help={tr("After %@ closes unexpectedly, ask before sending a crash report, send it without asking, or never send one", edition.name)}
            items={CRASH_REPORT_CONSENTS.map((choice) => ({ id: choice, title: crashReportConsentTitle(choice) }))}
            selected={consent}
            onSelect={(choice) => app.settings.setCrashReportConsent(choice)}
            width={170}
          />
        </SettingsRow>
        <SettingsRow label={tr("Licenses")} help={tr("Released under the MIT License.")}>
          <SettingsButton title={tr("Show Licenses")} help={tr("What ships in Tabbi and under which license")} onClick={() => setLicenses(true)} />
        </SettingsRow>
      </SettingsGroup>

      <div className="settings-about-foot">
        <p className="settings-about-pricing kit-body">{PRICING_SENTENCE}</p>
        <div className="settings-about-legal">
          <Tooltip text={SupportContact.privacyURL}>
            <button type="button" className="settings-link kit-caption" onClick={() => void host.openUrl(SupportContact.privacyURL)}>
              {tr("Privacy Policy")}
            </button>
          </Tooltip>
          <Tooltip text={SupportContact.termsURL}>
            <button type="button" className="settings-link kit-caption" onClick={() => void host.openUrl(SupportContact.termsURL)}>
              {tr("Terms of Use")}
            </button>
          </Tooltip>
        </div>
      </div>

      {licenses && (
        <Sheet
          title={tr("Licenses")}
          intro={tr("Released under the MIT License.")}
          onCancel={() => setLicenses(false)}
          width={460}
          actions={
            <>
              <span className="kit-sheet-spacer" />
              <SettingsButton title={tr("Done")} help={tr("Close the licenses")} primary onClick={() => setLicenses(false)} />
            </>
          }
        >
          <div className="settings-licenses kit-card">
            {LICENSES.map((entry) => (
              <Tooltip key={entry.name} text={entry.url}>
                <button type="button" className="settings-license" onClick={() => void host.openUrl(entry.url)}>
                  <span className="kit-body-emphasis">{entry.name}</span>
                  <span className="kit-caption kit-secondary">{entry.license}</span>
                </button>
              </Tooltip>
            ))}
          </div>
        </Sheet>
      )}
    </SettingsPage>
  );
}
