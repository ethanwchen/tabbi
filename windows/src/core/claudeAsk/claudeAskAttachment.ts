/**
 * Port of ClaudeAskAttachment: a screenshot sent with an Ask question. The
 * image is a PNG file named after `id` that the host stores; the message
 * only records what the panel needs to find and lay out its thumbnail.
 */
export interface ClaudeAskAttachment {
  id: string;
  pixelWidth: number;
  pixelHeight: number;
}

export const ATTACHMENT_MEDIA_TYPE = "image/png";

/** The longest edge Claude reads at full detail; larger images only cost time and tokens. */
export const MAX_LONG_EDGE = 1568;

/** The image's file name, `<id>.png`. */
export function attachmentFileName(attachment: ClaudeAskAttachment): string {
  return `${attachment.id}.png`;
}

/**
 * The size to scale a capture of `width` x `height` pixels to before it is
 * attached: the same shape with the long edge at most `maxLongEdge`, never
 * scaled up, and at least 1 pixel on each side.
 */
export function fittedPixelSize(width: number, height: number, maxLongEdge = MAX_LONG_EDGE): { width: number; height: number } {
  const w = Math.max(width, 1);
  const h = Math.max(height, 1);
  const longEdge = Math.max(w, h);
  if (longEdge <= maxLongEdge) return { width: w, height: h };
  const scale = maxLongEdge / longEdge;
  return { width: Math.max(1, Math.round(w * scale)), height: Math.max(1, Math.round(h * scale)) };
}
