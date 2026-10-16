import { durationMinutes } from "../formatting/durationFormat";
import { tr } from "../localization/tr";
import { recapCheerLine, type RecapCheer, type WeeklyRecap } from "./weeklyRecap";

/*
 * Port of RecapNotice: the words of the toast that says a weekly recap is
 * ready. Warm like the card: the week's line, the time focused when there
 * was any, and where to find the card, never a count of what was missed.
 * The Mac points at the notch; Windows points at Tabbi's island, with its
 * own catalog line.
 */
export interface RecapNotice {
  readonly title: string;
  readonly body: string;
}

export function recapNotice(recap: WeeklyRecap, cheer: RecapCheer): RecapNotice {
  const focus = recap.focusMinutes > 0 ? tr("%@ of focus.", durationMinutes(recap.focusMinutes)) : undefined;
  const parts = [recapCheerLine(cheer), focus, tr("Open Tabbi to see your recap.")];
  return {
    title: tr("Your week with Tabbi is ready"),
    body: parts.filter((part): part is string => part !== undefined).join(" "),
  };
}
