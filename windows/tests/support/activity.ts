import { makeActivityRecord, type ActivityRecord, type ActivityRecordInput } from "../../src/core/activity/activityRecord";
import type { Instant } from "../../src/core/time";

/* An activity record for a test that only cares when it ended: it starts then too unless `start` says otherwise. */
export function activity(fields: Omit<ActivityRecordInput, "start"> & { end: Instant; start?: Instant }): ActivityRecord {
  return makeActivityRecord({ ...fields, start: fields.start ?? fields.end });
}
