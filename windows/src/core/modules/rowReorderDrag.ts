/** Rounds half away from zero, as Swift's `rounded()` does. */
function round(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

/**
 * Port of RowReorderDrag: a row dragged through a list of equally tall rows,
 * as the Settings tab list draws it. The lifted row follows the pointer
 * without leaving the list, the rows it passes slide one slot toward the gap
 * it left, and the slot it would land in on release is the drop target.
 */
export class RowReorderDrag {
  constructor(
    /** The slot the row was picked up from. */
    readonly from: number,
    /** How many rows the list has. */
    readonly count: number,
    /** The height of one row, separators included. */
    readonly rowHeight: number,
    /** How far the pointer moved since the drag began, positive downward, before clamping. */
    public translation = 0,
  ) {}

  /** How far the lifted row is drawn from its slot, held inside the list. */
  get liftedOffset(): number {
    const up = -this.from * this.rowHeight;
    const down = Math.max(this.count - 1 - this.from, 0) * this.rowHeight;
    return Math.min(Math.max(this.translation, up), down);
  }

  /** The slot the row lands in on release: the one its center is over. */
  get target(): number {
    if (this.count <= 0 || !(this.rowHeight > 0)) return this.from;
    return Math.min(Math.max(this.from + round(this.liftedOffset / this.rowHeight), 0), this.count - 1);
  }

  /** Whether releasing now changes the order. */
  get movesRow(): boolean {
    return this.target !== this.from;
  }

  /** How far the row in slot `index` is drawn from its slot. */
  offset(index: number): number {
    const target = this.target;
    if (index === this.from) return this.liftedOffset;
    if (this.from < index && index <= target) return -this.rowHeight;
    if (target <= index && index < this.from) return this.rowHeight;
    return 0;
  }
}
