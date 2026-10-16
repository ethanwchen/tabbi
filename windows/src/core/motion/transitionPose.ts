/*
 * Port of TransitionPose: how a view looks while it enters or leaves (scale,
 * offset and opacity). A view fades while it moves at most 8 px or shrinks to
 * at most 80%, so a changing list never sends rows flying across the canvas.
 * Under Reduce Motion a transition only fades.
 */

export type TransitionEdge = "top" | "bottom" | "leading" | "trailing";

/** What the view shows: neutral once inserted, the pose while outside. */
export interface ResolvedPose {
  readonly scale: number;
  readonly offsetX: number;
  readonly offsetY: number;
  readonly opacity: number;
}

/** Port of TransitionPose. Offsets are in pixels, anchors are unit points (0.5, 0.5 is the center). */
export class TransitionPose {
  readonly scale: number;
  readonly offsetX: number;
  readonly offsetY: number;
  readonly anchorX: number;
  readonly anchorY: number;

  constructor({ scale = 1, offsetX = 0, offsetY = 0, anchorX = 0.5, anchorY = 0.5 } = {}) {
    this.scale = scale;
    this.offsetX = offsetX;
    this.offsetY = offsetY;
    this.anchorX = anchorX;
    this.anchorY = anchorY;
  }

  /** A small control or badge appearing in place: hover buttons, a clear button, a swapping pill. */
  static readonly pop = new TransitionPose({ scale: 0.8 });
  /** One content state replacing another in the same space: a slight grow from the top edge. */
  static readonly swap = new TransitionPose({ scale: 0.98, anchorY: 0 });

  /** A list row arriving from or leaving toward `edge`. */
  static row(edge: TransitionEdge): TransitionPose {
    const distance = 8;
    switch (edge) {
      case "top":
        return new TransitionPose({ offsetY: -distance });
      case "bottom":
        return new TransitionPose({ offsetY: distance });
      case "leading":
        return new TransitionPose({ offsetX: -distance });
      case "trailing":
        return new TransitionPose({ offsetX: distance });
    }
  }

  /** The pose to draw; Reduce Motion drops the scale and offset and keeps only the fade. */
  resolved(isIdentity: boolean, reduceMotion: boolean): ResolvedPose {
    if (isIdentity) return { scale: 1, offsetX: 0, offsetY: 0, opacity: 1 };
    if (reduceMotion) return { scale: 1, offsetX: 0, offsetY: 0, opacity: 0 };
    return { scale: this.scale, offsetX: this.offsetX, offsetY: this.offsetY, opacity: 0 };
  }
}
