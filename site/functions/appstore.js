// GET /appstore: the short link to Tabbi's Mac App Store page, for sharing
// and for print (see ../_download.mjs).

import { appStoreResponse } from '../_download.mjs';

export function onRequestGet() {
  return appStoreResponse();
}
