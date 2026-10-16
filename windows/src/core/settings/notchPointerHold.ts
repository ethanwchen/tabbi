/**
 * Port of NotchPointerHold: keeps the open panel open while the user works
 * in a menu it opened. A menu draws in a window of its own, usually below
 * the panel, so reaching for an item leaves the panel's shape, which on its
 * own closes it. From a menu opening until the pointer is back over the
 * panel, leaving no longer closes it.
 */
export class NotchPointerHold {
  /** Menus open right now that began on the open panel. */
  openMenus = 0;
  /** True from a menu opening until the pointer is back over the panel with no menu open. */
  holdsOpen = false;

  /** A menu began tracking. Only one on the open panel holds it. */
  menuBegan(notchIsOpen: boolean): void {
    if (!notchIsOpen) return;
    this.openMenus += 1;
    this.holdsOpen = true;
  }

  /** A menu stopped tracking; the hold stays until the pointer comes back. */
  menuEnded(): void {
    this.openMenus = Math.max(0, this.openMenus - 1);
  }

  /** The pointer is over the panel again: leaving closes it as usual, unless a menu is still open. */
  pointerEntered(): void {
    if (this.openMenus !== 0) return;
    this.holdsOpen = false;
  }

  /** The panel closed, which ends any hold. */
  notchClosed(): void {
    this.openMenus = 0;
    this.holdsOpen = false;
  }
}
