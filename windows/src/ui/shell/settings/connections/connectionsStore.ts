/*
 * Port of ConnectionsStore for Windows: where every connection stands, and
 * the one button that moves each forward. It checks only while someone is
 * looking (between `beginWatching` and `endWatching`), and a state that
 * clears by itself (Anki starting or syncing) is checked again at the
 * AnkiRecovery pace while shown. Demo and snapshot runs show the demo
 * diagnoses and never look at the PC.
 *
 * The probes: the calendar from the saved ICS feeds and the shared source's
 * statuses, Anki over AnkiConnect through the host's HTTP, the media apps
 * from the host's media session, toasts from Windows' toast setting, Do
 * not disturb (which Windows can't switch) as a fixed note, and Party from
 * the shared party state. Spotify is not probed on Windows: the media
 * session covers any player, so its row stays out.
 */

import type { ModuleContext } from "../../../../app/context";
import { Store } from "../../../../app/store";
import { AnkiConnectClient, ANKI_CONNECT_ENDPOINT, type AnkiRequest } from "../../../../core/anki/ankiConnectClient";
import { AnkiRecovery, resolveAnkiConnectionState } from "../../../../core/anki/ankiConnectionState";
import { loadCalendarSubscriptions, saveCalendarSubscriptions, type CalendarSource, type CalendarSubscription } from "../../../../core/calendar/calendarSource";
import { ankiDiagnosis } from "../../../../core/connections/ankiConnection";
import { calendarConnectionState, calendarDiagnosis } from "../../../../core/connections/calendarConnection";
import type { ConnectionDiagnosis } from "../../../../core/connections/connectionDiagnosis";
import { demoDiagnosis, relevantConnections, type ConnectionKind } from "../../../../core/connections/connectionKind";
import { doNotDisturbDiagnosis } from "../../../../core/connections/doNotDisturbConnection";
import { mediaAppsDiagnosis } from "../../../../core/connections/musicConnection";
import { notificationsDiagnosis } from "../../../../core/connections/notificationsConnection";
import { partyDiagnosis, resolvePartyConnection } from "../../../../core/connections/partyConnection";
import type { ModuleID } from "../../../../core/modules/moduleId";
import type { PartyState } from "../../../../core/party/partyState";
import type { Instant } from "../../../../core/time";
import { isHostError, type Host } from "../../../../host/host";
import type { Readable } from "../../../../app/store";
import type { WindowChannel } from "../../../../app/windowChannel";
import { CALENDAR_SUBSCRIPTIONS_CHANGED } from "../../../../modules/planner/calendarServices";

export interface ConnectionsState {
  readonly diagnoses: Partial<Record<ConnectionKind, ConnectionDiagnosis>>;
  readonly checkedAt: Partial<Record<ConnectionKind, Instant>>;
  /** The rows with a check running right now. */
  readonly running: ReadonlySet<ConnectionKind>;
}

export interface ConnectionsStoreOptions {
  readonly host: Host;
  readonly context: ModuleContext;
  readonly calendar: CalendarSource;
  /** Today's "calendar" channel, which tells the island's Today the saved feeds changed. */
  readonly calendarFeeds: WindowChannel;
  readonly party: Readable<PartyState>;
  readonly isDemo: boolean;
}

/** The connections Windows can show for `enabled`: the Mac's list minus Spotify, which the media session covers. */
export function windowsConnections(enabled: Iterable<ModuleID>): ConnectionKind[] {
  return relevantConnections(enabled, { localTools: false, usesClaudeCode: false }).filter((kind) => kind !== "spotify");
}

/** The AnkiConnect transport over the host's HTTP: a POST with the envelope's exact bytes, no Origin header. */
function ankiTransport(host: Host) {
  return async (request: AnkiRequest): Promise<unknown> => {
    try {
      const response = await host.httpRequest({ method: "POST", url: ANKI_CONNECT_ENDPOINT, headers: [["content-type", "application/json"]], body: request.body });
      if (response.status < 200 || response.status >= 300) throw { kind: "status", status: response.status };
      try {
        return JSON.parse(response.body);
      } catch {
        return response.body;
      }
    } catch (error) {
      if (isHostError(error)) {
        if (error.code === "timeout") throw { kind: "timedOut" };
        if (error.code === "network") throw { kind: "connectionRefused" };
        throw { kind: "failed", message: error.message };
      }
      throw error;
    }
  };
}

export class ConnectionsStore extends Store<ConnectionsState> {
  private readonly watchers = new Map<ConnectionKind, number>();
  private readonly rechecks = new Map<ConnectionKind, number>();
  private readonly clearingSince = new Map<ConnectionKind, Instant>();
  private readonly checks = new Map<ConnectionKind, number>();
  private stopParty: (() => void) | undefined;

  constructor(private readonly options: ConnectionsStoreOptions) {
    super({ diagnoses: {}, checkedAt: {}, running: new Set() });
    if (options.isDemo) {
      const diagnoses: Partial<Record<ConnectionKind, ConnectionDiagnosis>> = {};
      for (const kind of windowsConnections(options.context.settings.catalog.ids)) diagnoses[kind] = demoDiagnosis(kind);
      this.setState({ diagnoses });
    }
  }

  get isDemo(): boolean {
    return this.options.isDemo;
  }

  /** A view showing these connections appeared: check the ones nobody was showing yet. */
  beginWatching(kinds: readonly ConnectionKind[]): void {
    if (this.options.isDemo) return;
    const fresh = kinds.filter((kind) => !this.watchers.has(kind));
    for (const kind of kinds) this.watchers.set(kind, (this.watchers.get(kind) ?? 0) + 1);
    if (fresh.includes("party") && this.stopParty === undefined) {
      this.stopParty = this.options.party.subscribe(() => this.showParty());
    }
    this.refresh(fresh);
  }

  endWatching(kinds: readonly ConnectionKind[]): void {
    for (const kind of kinds) {
      const count = this.watchers.get(kind);
      if (count === undefined) continue;
      if (count > 1) this.watchers.set(kind, count - 1);
      else {
        this.watchers.delete(kind);
        window.clearTimeout(this.rechecks.get(kind));
        this.rechecks.delete(kind);
        this.clearingSince.delete(kind);
      }
    }
    if (!this.watchers.has("party") && this.stopParty !== undefined) {
      this.stopParty();
      this.stopParty = undefined;
    }
  }

  /** Checks the given connections again. A check already running for a row is replaced, so the newest answer always wins. */
  refresh(kinds: readonly ConnectionKind[]): void {
    if (this.options.isDemo) return;
    for (const kind of kinds) {
      if (kind === "party") {
        this.showParty();
        continue;
      }
      const token = (this.checks.get(kind) ?? 0) + 1;
      this.checks.set(kind, token);
      this.setState((state) => ({ running: new Set([...state.running, kind]) }));
      void this.diagnose(kind).then((diagnosis) => {
        if (this.checks.get(kind) !== token) return;
        this.record(kind, diagnosis);
        this.scheduleRecheck(kind, diagnosis);
      });
    }
  }

  /** The saved calendar feeds, for the Calendar row's sheet. */
  subscriptions(): Promise<CalendarSubscription[]> {
    return loadCalendarSubscriptions(this.options.context.storage.root());
  }

  /** Replaces the saved feeds, tells the shared source and the island, and checks the row again. */
  async setSubscriptions(subscriptions: readonly CalendarSubscription[]): Promise<void> {
    await saveCalendarSubscriptions(this.options.context.storage.root(), subscriptions);
    const source = this.options.calendar as CalendarSource & { setSubscriptions?: (list: readonly CalendarSubscription[]) => void };
    source.setSubscriptions?.(subscriptions);
    await this.options.calendar.reload().catch(() => undefined);
    /* Today's module in the island owns the live source; it hears the change on its own topic. */
    this.options.calendarFeeds.post(CALENDAR_SUBSCRIPTIONS_CHANGED);
    this.refresh(["calendar"]);
  }

  private record(kind: ConnectionKind, diagnosis: ConnectionDiagnosis): void {
    this.setState((state) => {
      const running = new Set(state.running);
      running.delete(kind);
      return { diagnoses: { ...state.diagnoses, [kind]: diagnosis }, checkedAt: { ...state.checkedAt, [kind]: this.options.context.now() }, running };
    });
  }

  private showParty(): void {
    const party = this.options.party.get();
    this.record("party", partyDiagnosis(resolvePartyConnection(party.connection, party.friendCode, party.profile?.name !== undefined)));
  }

  /** Checks a shown row again soon while its state usually clears by itself, quickly at first and less often the longer it lasts. */
  private scheduleRecheck(kind: ConnectionKind, diagnosis: ConnectionDiagnosis): void {
    window.clearTimeout(this.rechecks.get(kind));
    this.rechecks.delete(kind);
    if (!diagnosis.clearsBySelf || !this.watchers.has(kind)) {
      this.clearingSince.delete(kind);
      return;
    }
    const now = this.options.context.now();
    const since = this.clearingSince.get(kind) ?? now;
    this.clearingSince.set(kind, since);
    const delay = AnkiRecovery.interval(now - since);
    this.rechecks.set(
      kind,
      window.setTimeout(() => {
        if (this.watchers.has(kind)) this.refresh([kind]);
      }, delay * 1000),
    );
  }

  private async diagnose(kind: ConnectionKind): Promise<ConnectionDiagnosis> {
    const { host, context, calendar } = this.options;
    switch (kind) {
      case "calendar": {
        const subscriptions = await this.subscriptions();
        await calendar.events(context.now(), context.now() + 60).catch(() => []);
        return calendarDiagnosis(calendarConnectionState(subscriptions, calendar.status()));
      }
      case "anki": {
        const client = new AnkiConnectClient({ transport: ankiTransport(host) });
        const error = await client.checkAccess();
        /* Whether Anki is on disk is unknown from the webview; a refused connection reads as "not running", which the row's button still fixes. */
        return ankiDiagnosis(resolveAnkiConnectionState(error, true, undefined, context.now()));
      }
      case "music": {
        const available = await host
          .mediaSnapshot()
          .then(() => true)
          .catch(() => false);
        return mediaAppsDiagnosis({ available });
      }
      case "notifications":
        return notificationsDiagnosis(await host.notificationsSetting().catch(() => "enabled" as const));
      case "doNotDisturb":
        return doNotDisturbDiagnosis();
      case "party":
      case "spotify":
      case "claude":
        return demoDiagnosis(kind);
    }
  }
}
