// GET /add/<code>: the Party invite page for that code (see ../../_invite.mjs).

import { inviteResponse } from '../../_invite.mjs';

export function onRequestGet(context) {
  return inviteResponse('add', context.request);
}
