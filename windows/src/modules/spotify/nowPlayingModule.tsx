import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { placeholderPanel } from "../placeholderPanel";

/*
 * Port of NowPlayingModule: the music playing on the PC. Windows reads the
 * system media session (artwork arrives as a thumbnail from the host), so
 * unlike the Mac it asks for no Automation permission and fetches no
 * artwork from the network.
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

export const NowPlayingModule = defineModule(NOW_PLAYING_DESCRIPTOR, () => ({
  Panel: placeholderPanel(NOW_PLAYING_DESCRIPTOR),
}));
