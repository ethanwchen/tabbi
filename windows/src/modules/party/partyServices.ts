/*
 * The party state, declared here because Party owns it: the Timer tab shows
 * a party's shared session and the closed island its pets, so both read one
 * PartyState. Demo and snapshot runs start from the demo party; live runs
 * start signed out until the Party port loads the settings and connects.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { Observable } from "../../app/store";
import { isEphemeral } from "../../core/modules/runMode";
import { partyDemoState } from "../../core/party/partyDemo";
import { DEFAULT_PARTY_SETTINGS } from "../../core/party/partySettings";
import { PartyState } from "../../core/party/partyState";

const PARTY_STATE = serviceKey<Observable<PartyState>>("party.state");

/** The one party state; replace it with a changed clone (PartyState has value semantics). */
export function partyState(context: ModuleContext): Observable<PartyState> {
  return context.shared.resolve(PARTY_STATE, () => {
    const now = context.now();
    const initial = isEphemeral(context.runMode)
      ? partyDemoState(now, context.timeZone())
      : new PartyState(DEFAULT_PARTY_SETTINGS, now);
    return new Observable(initial);
  });
}
