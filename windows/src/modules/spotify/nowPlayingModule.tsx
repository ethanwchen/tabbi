import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { mapped } from "../../app/store";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { moduleProvision } from "../../core/providers/moduleProvision";
import { MusicLeading, MusicTrailing } from "./MusicWings";
import { NowPlayingPanel } from "./NowPlayingPanel";
import { NOW_PLAYING_SNAPSHOT_STATES, NowPlayingStore } from "./nowPlayingStore";

/*
 * Port of NowPlayingModule: the music playing on the PC. Windows reads the
 * system media session (artwork arrives as a thumbnail from the host), so
 * unlike the Mac it asks for no Automation permission and fetches no
 * artwork from the network. The store also drives the closed pill's music
 * wings, and the session is read only while the tab is on.
 */
export const NOW_PLAYING_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.spotify,
    title: "Now Playing",
    symbol: "music.note",
    category: MODULE_CATEGORIES.media,
    accent: { red: 0.12, green: 0.84, blue: 0.38 },
  },
  {
    title: () => tr("Now Playing"),
    summary: () => tr("Control the music playing on your PC."),
  },
);

export const NowPlayingModule = defineModule(
  NOW_PLAYING_DESCRIPTOR,
  (context) => {
    const store = new NowPlayingStore(context);
    function Panel() {
      return <NowPlayingPanel store={store} />;
    }
    function Leading() {
      return <MusicLeading store={store} />;
    }
    function Trailing() {
      return <MusicTrailing store={store} />;
    }
    return {
      store,
      Panel,
      musicWings: { Leading, Trailing },
      /* Whether music is playing, so the closed pill shows the music wings. */
      provision: mapped(store, (state) => moduleProvision({ isPlaying: state.isPlaying })),
      start: () => store.start(),
      stop: () => store.stop(),
      showSnapshotState: (state: string) => store.showSnapshotState(state),
    };
  },
  { snapshotStates: NOW_PLAYING_SNAPSHOT_STATES },
);
