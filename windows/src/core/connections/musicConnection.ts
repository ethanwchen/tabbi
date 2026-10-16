import { tr } from "../localization/tr";
import { chainChecks, connectionDiagnosis, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { CONNECTION_APPS, ConnectionActions, connectionStatus, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of MusicConnection.swift for Windows. The Mac controls Spotify and
 * Apple Music over AppleScript, which macOS gates behind an Automation
 * prompt per app. Windows has no such prompt: Now Playing follows the
 * system media controls (GlobalSystemMediaTransportControlsSessionManager),
 * which every player that shares what it plays is part of. So the Spotify
 * row only asks whether Spotify is installed, and the `music` row, "Media
 * apps", asks whether Windows' media controls answer at all (they can be
 * missing on N editions without the Media Feature Pack).
 */

/** Where the Spotify row stands. */
export interface SpotifyConnectionState {
  readonly isInstalled: boolean;
}

const spotify = CONNECTION_APPS.spotify;

export function spotifyConnectionStatus(state: SpotifyConnectionState): ConnectionStatus {
  if (!state.isInstalled) {
    return connectionStatus("notInstalled", tr("%@ isn't on this PC", spotify.name), tr("Get %@ to control your music from Tabbi.", spotify.name), {
      action: ConnectionActions.download(spotify),
    });
  }
  return connectionStatus("connected", tr("%@ is connected", spotify.name), tr("Play, pause and skip songs from Tabbi."));
}

export function spotifyDiagnosis(state: SpotifyConnectionState): ConnectionDiagnosis {
  const checks = chainChecks([
    {
      question: tr("Is %@ on this PC?", spotify.name),
      outcome: state.isInstalled ? "passed" : "failed",
      answer: state.isInstalled ? tr("Yes, %@ is installed.", spotify.name) : tr("No. Get %@ to control your music from Tabbi.", spotify.name),
    },
  ]);
  return connectionDiagnosis({
    kind: "spotify",
    status: spotifyConnectionStatus(state),
    checks,
    technical: `spotify.installed=${state.isInstalled}`,
  });
}

/** Where the media apps row stands: whether Windows' media controls answered, undefined while asking. */
export interface MediaAppsConnectionState {
  readonly available: boolean | undefined;
}

export function mediaAppsConnectionStatus(state: MediaAppsConnectionState): ConnectionStatus {
  switch (state.available) {
    case undefined:
      return connectionStatus("checking", tr("Looking for media apps"), tr("This takes a second."));
    case false:
      return connectionStatus("needsStep", tr("Media controls didn't answer"), tr("Windows may still be starting them. Check again in a moment."), {
        action: ConnectionActions.checkAgain,
      });
    case true:
      return connectionStatus("connected", tr("Media controls are on"), tr("Tabbi follows whatever app is playing."));
  }
}

export function mediaAppsDiagnosis(state: MediaAppsConnectionState): ConnectionDiagnosis {
  const checks = chainChecks([
    {
      question: tr("Can Tabbi see what's playing?"),
      outcome: state.available === undefined ? undefined : state.available ? "passed" : "failed",
      answer: state.available === true ? tr("Yes.") : tr("No. Windows didn't answer this time."),
    },
  ]);
  const technical = state.available === undefined ? "checking" : state.available ? "available" : "unavailable";
  return connectionDiagnosis({ kind: "music", status: mediaAppsConnectionStatus(state), checks, technical: `music.mediaControls=${technical}` });
}
