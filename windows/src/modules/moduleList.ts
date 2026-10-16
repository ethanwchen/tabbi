/*
 * Port of ModuleList: every module this build has, one per line, in the
 * Mac's canonical order (the order Settings lists modules a kit doesn't
 * mention). Adding a module means adding its line here; titles, symbols,
 * accents, layouts and kit validation all read the catalog built from this
 * list, so nothing else hardcodes a module.
 */

import type { ModuleType } from "../app/module";
import { AnkiModule } from "./anki/ankiModule";
import { AskModule } from "./claudeAsk/askModule";
import { ClaudeUsageModule } from "./claudeUsage/claudeUsageModule";
import { ClosetModule } from "./closet/closetModule";
import { FocusModule } from "./focus/focusModule";
import { PartyModule } from "./party/partyModule";
import { TodayModule } from "./planner/todayModule";
import { ScheduleModule } from "./schedule/scheduleModule";
import { NowPlayingModule } from "./spotify/nowPlayingModule";
import { StudyModule } from "./study/studyModule";
import { SystemModule } from "./system/systemModule";

export const MODULE_LIST: readonly ModuleType[] = [
  NowPlayingModule,
  SystemModule,
  ClaudeUsageModule,
  TodayModule,
  AskModule,
  FocusModule,
  StudyModule,
  AnkiModule,
  PartyModule,
  ClosetModule,
  ScheduleModule,
];
