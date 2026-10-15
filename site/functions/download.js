// GET /download: the header's Download link. Sends Windows visitors the
// Windows installer and everyone else the Mac download (see ../_download.mjs).

import { downloadResponse } from '../_download.mjs';

export function onRequestGet(context) {
  return downloadResponse(context.request);
}
