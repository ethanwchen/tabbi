/*
 * The Mac's `ModulePreview`: a designed stand-in for a module that is
 * registered but still being built. The module's identity and pitch on the
 * left (a 44 px accent tile with the symbol, the pitch as a title, an "In
 * development" capsule), what it will do on the right (a card of feature
 * rows: a 24 px accent tile, a title and a caption). Kits can list a module
 * before its feature lands, so its tab still looks intentional.
 */

import type { CSSProperties } from "react";
import { tr } from "../../core/localization/tr";
import { Card } from "./Card";
import { Icon } from "./Icon";
import { MarqueeText } from "./MarqueeText";
import { Tooltip } from "./Tooltip";

export interface ModulePreviewFeature {
  readonly symbol: string;
  readonly title: string;
  readonly detail: string;
}

export interface ModulePreviewProps {
  readonly symbol: string;
  readonly title: string;
  /** The module accent, as CSS; `var(--accent)` by default. */
  readonly accent?: string;
  readonly pitch: string;
  readonly features: readonly ModulePreviewFeature[];
}

export function ModulePreview({ symbol, title, accent = "var(--accent)", pitch, features }: ModulePreviewProps) {
  const help = tr("%@ is part of this kit and arrives in an upcoming update", title);
  return (
    <div className="kit-module-preview" style={{ "--preview-accent": accent } as CSSProperties}>
      <div className="kit-module-preview-hero">
        <div className="kit-module-preview-tile">
          <Icon id={symbol} size={20} />
        </div>
        <div className="kit-module-preview-pitch">{pitch}</div>
        <Tooltip text={help}>
          <span className="kit-module-preview-status" tabIndex={0}>
            {tr("In development")}
          </span>
        </Tooltip>
      </div>
      <Card className="kit-module-preview-card">
        {features.map((feature) => (
          <div key={feature.title} className="kit-module-preview-row">
            <div className="kit-module-preview-row-tile">
              <Icon id={feature.symbol} size={12} />
            </div>
            <div className="kit-module-preview-row-text">
              <MarqueeText text={feature.title} className="kit-module-preview-row-title" />
              <MarqueeText text={feature.detail} className="kit-module-preview-row-detail" />
            </div>
          </div>
        ))}
      </Card>
    </div>
  );
}
