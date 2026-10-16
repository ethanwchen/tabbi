/*
 * The Report and Block items in a friend's or party member's right-click
 * menu (the Mac's PartyModerationMenu), plus Remove, Accept, Decline and
 * Cancel Request for the row that has them.
 */

import { useCallback } from "react";
import { tr } from "../../core/localization/tr";
import type { PartyProfile } from "../../core/party/partyModels";
import { useContextMenu, type ContextMenuHandle, type ContextMenuItem } from "../../ui/kit/ContextMenu";
import type { PartyStore } from "./partyStore";

export function moderationItems(store: PartyStore, profile: PartyProfile): ContextMenuItem[] {
  return [
    { title: tr("Report %@…", profile.name), symbol: "exclamationmark.triangle", separator: true, onSelect: () => store.beginReport(profile) },
    { title: tr("Block %@", profile.name), symbol: "hand.raised.fill", destructive: true, onSelect: () => store.block(profile) },
  ];
}

/** A menu with `leading` items first, then Report and Block for `profile`; no menu at all for my own row. */
export function useModerationMenu(store: PartyStore, profile: PartyProfile | undefined, leading: () => ContextMenuItem[] = () => []): ContextMenuHandle {
  const items = useCallback(() => (profile === undefined ? [] : [...leading(), ...moderationItems(store, profile)]), [store, profile, leading]);
  return useContextMenu(items, profile?.name);
}
