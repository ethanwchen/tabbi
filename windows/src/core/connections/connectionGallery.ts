import { AnkiErrors } from "../anki/ankiConnectError";
import type { AnkiConnectionState } from "../anki/ankiConnectionState";
import { ankiDiagnosis } from "./ankiConnection";
import { calendarDiagnosis, type CalendarFeedState } from "./calendarConnection";
import { claudeDiagnosis, type ClaudeConnectionState } from "./claudeConnection";
import type { ConnectionDiagnosis } from "./connectionDiagnosis";
import type { ConnectionKind } from "./connectionKind";
import { doNotDisturbDiagnosis } from "./doNotDisturbConnection";
import { mediaAppsDiagnosis, spotifyDiagnosis } from "./musicConnection";
import { notificationsDiagnosis, type NotificationSetting } from "./notificationsConnection";
import { partyDiagnosis, type PartyConnectionState } from "./partyConnection";

/*
 * Port of ConnectionGallery: every state a row can show, from nothing to
 * connected, so each one can be rendered and reviewed. The order follows
 * the path a new user walks: missing first, connected last. Do Not
 * Disturb has one state on Windows (not available), and toasts in a copy
 * without an app identity only happen in development, so they are left out
 * like the Mac's calendar in a bare `swift run`.
 */
export function everyConnectionState(kind: ConnectionKind): ConnectionDiagnosis[] {
  switch (kind) {
    case "calendar": {
      const feed = (name: string, fields: Partial<CalendarFeedState> = {}): CalendarFeedState => ({
        name,
        hasData: true,
        isGoogle: false,
        ...fields,
      });
      const states: (readonly CalendarFeedState[])[] = [
        [],
        [feed("Classes", { hasData: false })],
        [feed("Classes", { hasData: false, lastError: "invalidAddress" })],
        [feed("Classes", { hasData: false, lastError: "notACalendar" })],
        [feed("Classes", { lastError: "unreachable" })],
        [feed("Classes")],
        [feed("Classes", { isGoogle: true }), feed("Holidays")],
      ];
      return states.map((feeds) => calendarDiagnosis({ feeds }));
    }
    case "anki": {
      const states: AnkiConnectionState[] = [
        { kind: "checking" },
        { kind: "notInstalled" },
        { kind: "notRunning" },
        { kind: "starting" },
        { kind: "addOnMissing" },
        { kind: "needsPermission", error: AnkiErrors.permissionDenied },
        { kind: "needsPermission", error: AnkiErrors.apiKeyRequired },
        { kind: "addOnOutdated" },
        { kind: "problem", error: AnkiErrors.collectionUnavailable },
        { kind: "problem", error: AnkiErrors.timeout },
        { kind: "problem", error: AnkiErrors.anki("AnkiConnect.getDeckStats() missing 1 required positional argument: 'decks'") },
        { kind: "problem", error: AnkiErrors.invalidResponse("getNumCardsReviewedByDay: Bad day") },
        { kind: "ready" },
      ];
      return states.map(ankiDiagnosis);
    }
    case "spotify":
      return [spotifyDiagnosis({ isInstalled: false }), spotifyDiagnosis({ isInstalled: true })];
    case "music":
      return [mediaAppsDiagnosis({ available: undefined }), mediaAppsDiagnosis({ available: false }), mediaAppsDiagnosis({ available: true })];
    case "notifications": {
      const settings: NotificationSetting[] = ["disabledForUser", "disabledByGroupPolicy", "disabledForApplication", "enabled"];
      return settings.map(notificationsDiagnosis);
    }
    case "doNotDisturb":
      return [doNotDisturbDiagnosis()];
    case "claude": {
      const states: ClaudeConnectionState[] = ["checking", "notInstalled", "signedOut", "ready"];
      return states.map((state) => claudeDiagnosis(state));
    }
    case "party": {
      const states: PartyConnectionState[] = [
        { kind: "notSetUp" },
        { kind: "ageCheck", tooYoungUntil: undefined },
        { kind: "ageCheck", tooYoungUntil: 32_503_680_000 },
        { kind: "connecting" },
        { kind: "offline" },
        { kind: "connected", friendCode: "PUFF-42" },
      ];
      return states.map(partyDiagnosis);
    }
  }
}
