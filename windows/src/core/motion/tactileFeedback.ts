/*
 * Port of TactileFeedback: how a control answers the pointer. It sinks a
 * little while pressed and, if it asks to, lifts a little while hovered. A
 * press shrinks a control by about 2 to 3 px, so it reads as a push without
 * moving its neighbors' edges. Under Reduce Motion a press dims instead.
 */
export class TactileFeedback {
  constructor(
    /** Scale while the pointer holds the control down. */
    readonly pressedScale: number,
    /** Scale while hovered, for controls that lift. */
    readonly hoverScale: number,
    /** Opacity while pressed under Reduce Motion, which replaces the scale. */
    readonly reducedPressedOpacity = 0.7,
  ) {}

  /** Small round controls: icon buttons, transport buttons, tabs. */
  static readonly control = new TactileFeedback(0.92, 1.06);
  /** Wider controls: pills with a label, artwork, rows. */
  static readonly pill = new TactileFeedback(0.97, 1.03);

  /** Pressing wins over hovering, and a control only lifts on hover when it `lifts`. */
  scale(pressed: boolean, hovering: boolean, lifts: boolean, reduceMotion: boolean): number {
    if (reduceMotion) return 1;
    if (pressed) return this.pressedScale;
    return hovering && lifts ? this.hoverScale : 1;
  }

  /** Only a press under Reduce Motion dims the control. */
  opacity(pressed: boolean, reduceMotion: boolean): number {
    return pressed && reduceMotion ? this.reducedPressedOpacity : 1;
  }
}
