// GET /suggest: the static page with the app facts Tabbi passed in the query
// filled into the form (see ../_suggest_prefill.mjs).

import { suggestResponse } from '../_suggest_prefill.mjs';

export function onRequestGet(context) {
  return suggestResponse(context.request, () => context.next());
}
