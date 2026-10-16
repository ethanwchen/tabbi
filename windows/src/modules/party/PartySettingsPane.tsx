/*
 * Port of PartySettingsPane: Settings > Tabs > Party > Options: the profile
 * friends see, going invisible, the Blocked list, the friends server, the
 * Party data, and (on Windows, where Settings > General has no Apple
 * account row of its own yet) the Sign in with Apple account that owns
 * that data once signed in. Text fields edit a draft and commit on Enter or
 * when they lose focus, so a half-typed server address never reconnects.
 */

import { useEffect, useState } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import { MINIMUM_AGE, opensText } from "../../core/party/partyAgeCheck";
import { partyErrorMessage } from "../../core/party/partyError";
import { SupportContact, refusalMessage, type PartyBlockedUser } from "../../core/party/partyModeration";
import { PARTY_PRODUCTION_URL } from "../../core/party/partyServer";
import { PARTY_MAX_NAME_LENGTH, partySettings, refusedNames, usesDefaultServer } from "../../core/party/partySettings";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { Spinner } from "../../ui/kit/Loading";
import { Pill } from "../../ui/kit/Pill";
import { SettingsGroup, SettingsRow } from "../../ui/kit/SettingsGroup";
import { TextField } from "../../ui/kit/TextField";
import { Toggle } from "../../ui/kit/Toggle";
import { Agreement } from "./PartyAgeCheckView";
import { copyText, displayCode, partyLocale } from "./PartyComponents";
import type { PartyStore } from "./partyStore";
import type { SyncService } from "./syncService";
import "./party.css";

const FIELD_WIDTH = 240;

export function PartySettingsPane({ store, account }: { store: PartyStore; account: SyncService }) {
  const state = useStore(store);
  const sync = useStore(account);
  /* The drafts follow the saved values on the render that changes them (the island or General may have saved meanwhile). */
  const [draft, setDraft] = useState({ saved: state.settings, name: state.settings.name, server: state.settings.serverText });
  if (draft.saved !== state.settings) setDraft({ saved: state.settings, name: state.settings.name, server: state.settings.serverText });
  const name = draft.name;
  const server = draft.server;
  const setName = (value: string) => setDraft((current) => ({ ...current, name: value }));
  const setServer = (value: string) => setDraft((current) => ({ ...current, server: value }));
  const [confirmsDelete, setConfirmsDelete] = useState(false);
  const [confirmsAccountDelete, setConfirmsAccountDelete] = useState(false);
  useEffect(() => {
    store.loadBlocked();
    account.refreshAgeStatus();
  }, [store, account]);

  const commitName = () => {
    const value = [...name].slice(0, PARTY_MAX_NAME_LENGTH * 2).join("");
    store.update({ ...state.settings, name: value });
    setName(value);
  };
  const commitServer = (value = server) => {
    const trimmed = value.trim();
    store.update({ ...state.settings, serverText: trimmed });
    setServer(trimmed);
  };
  const nameIssue = (() => {
    let refused = store.refusedNames;
    if (name !== state.settings.name) refused = { ...refused, name: refusedNames(partySettings({ name }), state.pet).name };
    return refusalMessage(refused);
  })();
  const friendCode = state.party.friendCode;
  const status = connectionStatus(store);
  const canReconnect = !store.isDemo && (state.party.connection.kind === "unreachable" || state.party.connection.kind === "connected");
  const host = (() => {
    try {
      return new URL(store.serverURL ?? PARTY_PRODUCTION_URL).host;
    } catch {
      return "";
    }
  })();

  return (
    <div className="party-settings">
      <SettingsGroup title={tr("Profile")} footer={nameIssue ?? tr("Friends see this name and the pet you dress in the Closet. Share your code so they can add you.")}>
        <SettingsRow label={tr("Name")}>
          <TextField
            value={name}
            onChange={setName}
            onSubmit={commitName}
            onBlur={commitName}
            label={tr("Name")}
            placeholder={state.party.profile?.name ?? tr("Your name")}
            help={tr("The name friends see, up to %lld characters", PARTY_MAX_NAME_LENGTH)}
            width={FIELD_WIDTH}
          />
        </SettingsRow>
        <SettingsRow label={tr("Friend code")}>
          <span className={friendCode === undefined ? "kit-body kit-secondary" : "party-code kit-body"}>{friendCode === undefined ? tr("Not connected yet") : displayCode(friendCode)}</span>
          <Pill title={tr("Copy")} help={tr("Copy your friend code to share it")} disabled={friendCode === undefined} onClick={() => void copyText(displayCode(friendCode ?? ""))} />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup title={tr("Privacy")} footer={tr("Only your name, pet, study status and minutes are shared. Nothing about your cards, decks or what you study ever leaves your PC.")}>
        <SettingsRow label={tr("Go invisible")} help={tr("Friends see you as offline. Your study minutes still count.")}>
          <Toggle isOn={state.settings.invisible} onChange={(invisible) => store.update({ ...state.settings, invisible })} label={tr("Go invisible")} help={tr("Hide your status from friends")} />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup title={tr("Blocked")} footer={tr("Blocked people can't see you, add you or join your parties. To block or report someone, right-click them in Party.")}>
        {state.blocked !== undefined && state.blocked.length > 0 ? (
          state.blocked.map((user) => <BlockedRow key={user.code} user={user} store={store} />)
        ) : (
          <SettingsRow
            label={
              state.blocked === undefined
                ? state.party.connection.kind === "connected"
                  ? tr("Loading…")
                  : tr("Connect to the friends server to see who you blocked.")
                : tr("No one is blocked.")
            }
          />
        )}
        <SettingsRow label={SupportContact.reportLine()}>
          <Pill title={tr("Email Support")} symbol="envelope" help={tr("Copy the support address, %@", SupportContact.email)} onClick={() => store.openURL(SupportContact.mailURL)} />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup title={tr("Friends server")} footer={tr("Friends only see each other on the same server. Change it only to run your own.")}>
        <SettingsRow label={tr("Server")}>
          {!usesDefaultServer(state.settings) && (
            <IconButton symbol="arrow.counterclockwise" size={24} help={tr("Use the default %@ server", "Tabbi")} onClick={() => commitServer("")} />
          )}
          <TextField
            value={server}
            onChange={setServer}
            onSubmit={() => commitServer()}
            onBlur={() => commitServer()}
            label={tr("Server")}
            placeholder={tr("Default server")}
            help={tr("A friends server address. Leave empty for %@.", new URL(PARTY_PRODUCTION_URL).host)}
            width={FIELD_WIDTH}
          />
        </SettingsRow>
        <SettingsRow label={status.title} help={status.detail === "" ? host : status.detail} tooltip={status.detail}>
          <span className="party-status-glyph">{status.symbol === undefined ? <Spinner size={12} /> : <Icon id={status.symbol} size={14} style={{ color: status.color }} />}</span>
          <Pill title={tr("Reconnect")} help={tr("Try the server again now")} disabled={!canReconnect} onClick={() => store.retry()} />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup title={tr("Account")} footer={sync.phase === "signedOut" && sync.notice === undefined && sync.ageStatus.kind === "passed" ? undefined : undefined}>
        <SettingsRow label={accountTitle(sync)} help={accountCaption(sync, store)} className={sync.notice === undefined ? undefined : "party-settings-warning"}>
          {sync.phase === "signedOut" && sync.ageStatus.kind === "unanswered" && (
            <Pill title={tr("Sign In…")} help={tr("Sign in with your Apple Account to sync your pet across your devices")} onClick={() => store.askAgeFirst()} />
          )}
          {sync.phase === "signedOut" && sync.ageStatus.kind === "passed" && (
            <Pill title={tr("Sign in with Apple")} help={tr("Sign in with your Apple Account to sync your pet across your devices")} className="party-apple-button" onClick={() => void account.signInOnWeb()} />
          )}
          {sync.phase === "signingIn" && <Pill title={tr("Cancel")} help={tr("Stop waiting for the browser")} onClick={() => account.cancelSignIn()} />}
          {(sync.phase === "signedIn" || sync.phase === "deleting") && (
            <>
              <Pill title={tr("Sign Out")} help={tr("Stop syncing on this PC. Your pet and progress stay here.")} disabled={sync.phase === "deleting"} onClick={() => account.signOut()} />
              <Pill
                title={tr("Delete Account")}
                help={tr("Delete the account and its synced data from the server")}
                disabled={sync.phase === "deleting"}
                className="party-destructive"
                onClick={() => setConfirmsAccountDelete(true)}
              />
            </>
          )}
        </SettingsRow>
        {sync.phase === "signedOut" && sync.ageStatus.kind === "passed" && sync.notice === undefined && (
          <SettingsRow label="" className="party-settings-agreement">
            <span className="kit-caption kit-tertiary party-agreement">
              <Agreement signingIn onOpen={(url) => store.openURL(url)} />
            </span>
          </SettingsRow>
        )}
        {confirmsAccountDelete && (
          <Confirmation
            title={tr("Delete your %@ account?", "Tabbi")}
            message={tr(
              "This deletes your account and everything the server keeps for it: the synced copy of your pet and points, your friend code, friends and parties. Your pet stays on this PC. This can't be undone.",
            )}
            confirm={tr("Delete Account")}
            onConfirm={() => {
              setConfirmsAccountDelete(false);
              void account.deleteAccount();
            }}
            onCancel={() => setConfirmsAccountDelete(false)}
          />
        )}
      </SettingsGroup>

      <SettingsGroup title={tr("Your data")}>
        {account.isSignedIn ? (
          <SettingsRow label={tr("Your Party data")} help={tr("It belongs to your Apple Account. Delete Account above removes it.")} />
        ) : (
          <SettingsRow
            label={tr("Delete my Party data")}
            help={state.pending?.kind === "deleteData" ? tr("Deleting…") : (state.deletionNotice ?? tr("Removes your profile, friends and parties from the server."))}
          >
            <Pill
              title={tr("Delete…")}
              help={tr("Delete your friend code, friends and parties from the friends server")}
              disabled={state.pending !== undefined || store.isDemo}
              className="party-destructive"
              onClick={() => setConfirmsDelete(true)}
            />
          </SettingsRow>
        )}
        {confirmsDelete && (
          <Confirmation
            title={tr("Delete your Party data?")}
            message={tr(
              "This deletes your friend code, your profile and pet as friends see them, your friends list, your party memberships and your study streak from the friends server. Friends will no longer see you. Your pet and points stay on this PC. If Party stays on, you get a new friend code.",
            )}
            confirm={tr("Delete")}
            onConfirm={() => {
              setConfirmsDelete(false);
              store.deletePartyData();
            }}
            onCancel={() => setConfirmsDelete(false)}
          />
        )}
      </SettingsGroup>
    </div>
  );
}

/** The Mac's confirmation dialog, inline: the question, what it does, and Cancel beside the destructive button. */
function Confirmation({ title, message, confirm, onConfirm, onCancel }: { title: string; message: string; confirm: string; onConfirm: () => void; onCancel: () => void }) {
  return (
    <div className="party-confirm" role="alertdialog" aria-label={title}>
      <span className="kit-body-emphasis">{title}</span>
      <span className="kit-caption kit-secondary">{message}</span>
      <div className="party-confirm-buttons">
        <Pill title={tr("Cancel")} onClick={onCancel} />
        <Pill title={confirm} className="party-destructive" onClick={onConfirm} />
      </div>
    </div>
  );
}

/** Someone on the Blocked list: their name, their pet and when, with Unblock. */
function BlockedRow({ user, store }: { user: PartyBlockedUser; store: PartyStore }) {
  const pending = useStore(store, (state) => state.pending);
  const unblocking = pending?.kind === "unblock" && pending.code === user.code;
  const detail =
    user.since === undefined
      ? tr("With %@", user.petName)
      : tr("With %@, blocked %@", user.petName, new Intl.RelativeTimeFormat(partyLocale(), { numeric: "auto" }).format(-Math.max(1, Math.round((store.now() - user.since) / 86_400)), "day"));
  return (
    <SettingsRow label={user.name} help={detail} className="party-user-row">
      <Pill
        title={unblocking ? tr("Unblocking…") : tr("Unblock")}
        help={tr("Let %@ find you again. You won't be friends until one of you adds the other.", user.name)}
        disabled={pending !== undefined}
        onClick={() => store.unblock(user.code)}
      />
    </SettingsRow>
  );
}

/** The connection as one status row; no symbol shows a spinner. */
function connectionStatus(store: PartyStore): { title: string; detail: string; symbol: string | undefined; color: string } {
  const state = store.state;
  const connection = state.party.connection;
  switch (connection.kind) {
    case "invalidServer":
      return { title: tr("Can't use this server"), detail: connection.message, symbol: "exclamationmark.triangle.fill", color: "var(--warning)" };
    case "ageCheck":
      return connection.tooYoungUntil === undefined
        ? { title: tr("Not joined yet"), detail: tr("Open the Party tab to join."), symbol: "question", color: "var(--secondary-text)" }
        : {
            title: tr("Not available"),
            detail: tr("Party is for people %lld and older. It opens in %@.", MINIMUM_AGE, opensText(connection.tooYoungUntil, partyLocale(), store.timeZone())),
            symbol: "hand.raised.fill",
            color: "var(--secondary-text)",
          };
    case "connecting":
      return { title: tr("Connecting…"), detail: "", symbol: undefined, color: "var(--secondary-text)" };
    case "unreachable":
      return connection.error.kind === "banned"
        ? { title: tr("Not available"), detail: partyErrorMessage(connection.error), symbol: "hand.raised.fill", color: "var(--secondary-text)" }
        : { title: tr("Can't reach the server"), detail: partyErrorMessage(connection.error), symbol: "wifi.slash", color: "var(--warning)" };
    case "connected":
      if (state.party.staleError !== undefined) return { title: tr("Connection lost"), detail: partyErrorMessage(state.party.staleError), symbol: "wifi.slash", color: "var(--warning)" };
      return { title: tr("Connected"), detail: "", symbol: "checkmark.circle.fill", color: "var(--success)" };
  }
}

function accountTitle(sync: SyncService["state"]): string {
  switch (sync.phase) {
    case "signedOut":
    case "signingIn":
      return tr("Account");
    case "signedIn":
    case "deleting":
      return sync.name ?? tr("Signed in with Apple");
  }
}

function accountCaption(sync: SyncService["state"], store: PartyStore): string {
  if (sync.notice !== undefined) return sync.notice;
  switch (sync.phase) {
    case "signedOut":
      if (sync.ageStatus.kind === "tooYoung") return tr("Accounts are for people %lld and older. Signing in opens in %@.", MINIMUM_AGE, opensText(sync.ageStatus.until, partyLocale(), store.timeZone()));
      return tr("Sync your pet, points and streaks across your devices.");
    case "signingIn":
      return tr("Signing in… Finish in your browser, then come back here.");
    case "deleting":
      return tr("Deleting your account…");
    case "signedIn":
      if (sync.isSyncing) return tr("Syncing…");
      if (sync.lastSyncedAt === undefined) return tr("Not synced yet");
      return tr("Last synced %@", relative(sync.lastSyncedAt, store.now()));
  }
}

/** "just now" for the first minute, then "4 min. ago". */
function relative(date: number, now: number): string {
  const seconds = now - date;
  if (seconds < 60) return tr("just now");
  const format = new Intl.RelativeTimeFormat(partyLocale(), { style: "short", numeric: "always" });
  if (seconds < 3600) return format.format(-Math.round(seconds / 60), "minute");
  if (seconds < 86_400) return format.format(-Math.round(seconds / 3600), "hour");
  return format.format(-Math.round(seconds / 86_400), "day");
}
