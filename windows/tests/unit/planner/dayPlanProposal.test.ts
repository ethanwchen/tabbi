import { describe, expect, it } from "vitest";
import { MAXIMUM_BLOCKS, planBlock } from "../../../src/core/planner/dayPlan";
import {
  DayPlanProposal,
  sampleDayPlanProposal,
  type PlanCalendarWriting,
  type PlannedCalendarEvent,
} from "../../../src/core/planner/dayPlanProposal";
import { sampleEvents } from "../../../src/core/planner/plannerSampleData";
import { upcomingEvent } from "../../../src/core/planner/upcomingEvent";

/* Port of DayPlanProposalTests. */

/** Records what it was asked to write, or fails like a denied calendar. */
class RecordingWriter implements PlanCalendarWriting {
  written: PlannedCalendarEvent[][] = [];
  fails = false;

  write(events: readonly PlannedCalendarEvent[]): void {
    if (this.fails) throw new Error("Denied");
    this.written.push([...events]);
  }
}

/* Swift's reference date plus 800,000,100 seconds, on a five-minute mark. */
const BASE = 800_000_100 + 978_307_200;
const at = (minutes: number) => BASE + minutes * 60;

const first = planBlock({ start: at(60), end: at(120), title: "Ship planner beta" });
const second = planBlock({ start: at(0), end: at(45), title: "Write release notes" });
const third = planBlock({ start: at(150), end: at(180), title: "Inbox" });

describe("DayPlanProposal", () => {
  it("keeps pending blocks in time order", () => {
    const proposal = new DayPlanProposal([first, second, third]);
    expect(proposal.pending.map((block) => block.title)).toEqual(["Write release notes", "Ship planner beta", "Inbox"]);
    expect(proposal.isSettled).toBe(false);
  });

  it("shows breaks between blocks still on offer", async () => {
    const study = planBlock({ start: at(0), end: at(25), title: "Study block", kind: "study" });
    const next = planBlock({ start: at(30), end: at(55), title: "Study block", kind: "study" });
    const last = planBlock({ start: at(90), end: at(115), title: "Anki reviews", kind: "reviews" });
    const rest = { start: at(25), end: at(30) };
    const proposal = DayPlanProposal.fromStudyPlan({ blocks: [last, next, study], breaks: [rest] });

    expect(proposal.breakAfter(study)).toEqual(rest);
    /* An event or free time, not a break, follows. */
    expect(proposal.breakAfter(next)).toBeUndefined();
    expect(proposal.breakAfter(last)).toBeUndefined();

    proposal.dismiss(next.id);
    /* No break before a dismissed block. */
    expect(proposal.breakAfter(study)).toBeUndefined();

    await proposal.add(new Set([study.id]), at(-10), [], new RecordingWriter());
    /* Added blocks leave the proposal. */
    expect(proposal.breakAfter(study)).toBeUndefined();
  });

  it("gives AI plans no breaks", () => {
    const proposal = new DayPlanProposal([second, first]);
    expect(proposal.breaks).toEqual([]);
    expect(proposal.breakAfter(second)).toBeUndefined();
  });

  it("writes one added block with the note and removes it", async () => {
    const proposal = new DayPlanProposal([first, second]);
    const writer = new RecordingWriter();
    await proposal.add(new Set([first.id]), at(-10), [], writer);
    expect(writer.written).toEqual([[{ title: "Ship planner beta", start: at(60), end: at(120), notes: "Planned with Tabbi" }]]);
    expect(proposal.pending.map((block) => block.id)).toEqual([second.id]);
    expect(proposal.addedCount).toBe(1);
  });

  it("writes every pending block in one batch on add all", async () => {
    const proposal = new DayPlanProposal([first, second, third]);
    proposal.dismiss(third.id);
    const writer = new RecordingWriter();
    await proposal.add(undefined, at(-10), [], writer);
    expect(writer.written.length).toBe(1);
    expect(writer.written[0]?.map((event) => event.title)).toEqual(["Write release notes", "Ship planner beta"]);
    expect(proposal.isSettled).toBe(true);
    expect(proposal.addedCount).toBe(2);
  });

  it("trims or drops blocks that slipped into the past", async () => {
    const proposal = new DayPlanProposal([first, second, third]);
    /* Just past 72 minutes in: the earliest block is over and the next resumes on the next five-minute mark. */
    const written = await proposal.add(undefined, at(72) + 23, [], new RecordingWriter());
    expect(written.map((event) => event.title)).toEqual(["Ship planner beta", "Inbox"]);
    expect(written[0]?.start).toBe(at(75));
    expect(written[0]?.end).toBe(at(120));
    /* A dropped block is no longer pending either. */
    expect(proposal.isSettled).toBe(true);
    expect(proposal.addedCount).toBe(2);
    expect(proposal.skippedCount).toBe(1);
  });

  it("rechecks blocks against meetings added since the proposal", async () => {
    const proposal = new DayPlanProposal([first, second, third]);
    const events = [
      /* Takes the first 20 minutes of "Ship planner beta"; the rest stays. */
      upcomingEvent({ id: "sync", title: "Sync", start: at(50), end: at(80) }),
      /* Swallows "Inbox" whole. */
      upcomingEvent({ id: "call", title: "Call", start: at(140), end: at(190) }),
      /* All-day events never block time. */
      upcomingEvent({ id: "holiday", title: "Holiday", start: at(-600), end: at(800), isAllDay: true }),
    ];
    const written = await proposal.add(undefined, at(-10), events, new RecordingWriter());
    expect(written.map((event) => event.title)).toEqual(["Write release notes", "Ship planner beta"]);
    expect(written.at(-1)?.start).toBe(at(80));
    expect(written.at(-1)?.end).toBe(at(120));
    expect(proposal.addedCount).toBe(2);
    expect(proposal.skippedCount).toBe(1);
    expect(proposal.isSettled).toBe(true);
  });

  it("keeps the longest free piece around a meeting in the middle", async () => {
    const proposal = new DayPlanProposal([first]);
    const events = [upcomingEvent({ id: "chat", title: "Chat", start: at(75), end: at(85) })];
    const written = await proposal.add(undefined, at(-10), events, new RecordingWriter());
    expect(written[0]?.start).toBe(at(85));
    expect(written[0]?.end).toBe(at(120));
  });

  it("leaves the proposal untouched when the write fails", async () => {
    const proposal = new DayPlanProposal([first, second]);
    const writer = new RecordingWriter();
    writer.fails = true;
    await expect(proposal.add(undefined, at(-10), [], writer)).rejects.toThrow();
    expect(proposal.pending.length).toBe(2);
    expect(proposal.addedCount).toBe(0);
  });

  it("skips the writer when nothing is left to write", async () => {
    const proposal = new DayPlanProposal([second]);
    const writer = new RecordingWriter();
    writer.fails = true;
    expect(await proposal.add(undefined, at(40), [], writer)).toEqual([]);
    expect(proposal.isSettled).toBe(true);
    expect(proposal.skippedCount).toBe(1);
  });

  it("keeps the sample proposal clear of the sample events and in the future", () => {
    for (const now of [BASE + 17, BASE + 9 * 3600 + 1234, BASE + 20 * 3600 + 299]) {
      const blocks = sampleDayPlanProposal(now);
      const events = sampleEvents(now);
      expect(blocks.length).toBeGreaterThan(0);
      expect(blocks.length).toBeLessThanOrEqual(MAXIMUM_BLOCKS);
      for (const block of blocks) {
        expect(block.start).toBeGreaterThan(now);
        expect(events.some((event) => event.start < block.end && block.start < event.end)).toBe(false);
      }
    }
  });
});
