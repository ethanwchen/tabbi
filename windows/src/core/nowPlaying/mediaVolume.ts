/*
 * Port of MediaVolume: volume math for a player's own 0 to 100 level. A
 * Windows media session reports no volume, so the panel only shows a
 * slider when a source does (the host may add the app's audio session).
 */

export const VOLUME_MIN = 0;
export const VOLUME_MAX = 100;
/** Where unmuting lands when there's no earlier level to restore, so the click is always audible. */
export const UNMUTE_FALLBACK = 50;

export function clampedVolume(volume: number): number {
  return Math.min(Math.max(volume, VOLUME_MIN), VOLUME_MAX);
}

/** Volume for a slider at `fraction` (0 to 1) of its track. */
export function volumeAt(fraction: number): number {
  if (!Number.isFinite(fraction)) return 0;
  return clampedVolume(Math.round(fraction * 100));
}

/** 0 when muted, else 1 to 3 by loudness; picks the speaker glyph. */
export function volumeLevel(volume: number): number {
  const value = clampedVolume(volume);
  if (value === 0) return 0;
  if (value < 34) return 1;
  if (value < 67) return 2;
  return 3;
}

/** The speaker button: mutes an audible volume, or restores `previous` when already silent. */
export function togglingMute(volume: number, previous: number | undefined): number {
  if (volume > 0) return 0;
  if (previous === undefined || previous <= 0) return UNMUTE_FALLBACK;
  return clampedVolume(previous);
}
