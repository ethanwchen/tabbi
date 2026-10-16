/*
 * Port of RecapSharing: exports a weekly recap as a PNG in either shape,
 * copied to the clipboard (the Mac's share sheet has no Windows equivalent
 * the island can show) or saved into the user's Pictures folder under the
 * format's file name through the host. Nothing is uploaded anywhere.
 */

import { tr } from "../../../core/localization/tr";
import { recapShareFileName, type RecapShareFormat } from "../../../core/recap/recapShareFormat";
import type { Host } from "../../../host/host";
import { recapSharePNG, type RecapShareInput } from "./recapShareImage";

/** The blob's bytes as base64, for the host's picture command. */
export async function blobToBase64(blob: Blob): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

/** Draws `input` and puts the PNG on the clipboard; resolves to the line to show the user. */
export async function copyRecapImage(input: RecapShareInput): Promise<string> {
  const blob = await recapSharePNG(input);
  await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
  return tr("Copied to the clipboard");
}

/** Draws `input` and saves the PNG to Pictures under the format's file name; resolves to the line to show the user. */
export async function saveRecapImage(host: Host, input: RecapShareInput, format: RecapShareFormat): Promise<string> {
  const blob = await recapSharePNG(input);
  await host.savePicture(recapShareFileName(format, input.recap.week, input.locale, input.timeZone), await blobToBase64(blob));
  return tr("Saved to Pictures");
}
