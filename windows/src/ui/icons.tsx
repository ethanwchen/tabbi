/*
 * The phase 1 icon entry point, kept for the island shell: `Icon({symbol,
 * size})` takes an SF Symbol name and draws the kit's original icon for it
 * (ui/kit/Icon.tsx, one drawing per id in core/symbols/symbols.ts, with the
 * dashed placeholder for an unknown name). New code imports the kit's
 * `Icon` with its `id` prop directly.
 */

import { Icon as KitIcon } from "./kit/Icon";

export function Icon({ symbol, size }: { symbol: string; size: number }) {
  return <KitIcon id={symbol} size={size} />;
}

export { ICON_IDS, resolveIconId } from "./kit/Icon";
