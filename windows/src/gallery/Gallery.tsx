/*
 * Every kit component in every state, laid out for review: tokens, icons,
 * the controls at rest, hovered, pressed, selected and disabled, loaders
 * and celebrations as frame strips, the pets, and the panel-level pieces
 * on the hardware-black 560 x 236 canvas. Nothing here is product UI.
 */

import { useState, type CSSProperties, type ReactNode } from "react";
import { tr } from "../core/localization/tr";
import { CELEBRATION_STYLES, type CelebrationStyle, type CelebrationTier } from "../core/motion/celebration";
import { motionPaceCaption, motionPaceTitle, MOTION_PACES, type MotionPace } from "../core/motion/motionPace";
import { PetProfile } from "../core/pets/petProfile";
import { DEFAULT_HOTKEY, HOTKEY_MODIFIERS, type Hotkey } from "../core/settings/hotkey";
import { paletteRoles, type ThemeID } from "../core/themes/appTheme";
import { allThemes } from "../core/themes/themeCatalog";
import type { ModuleAccent } from "../core/themes/themeColor";
import { Card } from "../ui/kit/Card";
import { CelebrationBurstView, CelebrationGlow, makeCelebration } from "../ui/kit/Celebration";
import { CheckGlyph } from "../ui/kit/CheckGlyph";
import { KitProvider, useTheme } from "../ui/kit/context";
import { EdgeFade } from "../ui/kit/EdgeFade";
import { FoundingBadge } from "../ui/kit/FoundingBadge";
import { HotkeyRecorder } from "../ui/kit/HotkeyRecorder";
import { ICON_IDS, Icon } from "../ui/kit/Icon";
import { IconButton } from "../ui/kit/IconButton";
import { PawLoader, Placeholder, ProgressRing, Shimmer, SkeletonLine, Spinner } from "../ui/kit/Loading";
import { MarqueeText } from "../ui/kit/MarqueeText";
import { ModulePlaceholder } from "../ui/kit/ModulePlaceholder";
import { ModulePreview } from "../ui/kit/ModulePreview";
import { PetSprite, PetView } from "../ui/kit/PetView";
import { Picker } from "../ui/kit/Picker";
import { ContextMenu } from "../ui/kit/ContextMenu";
import { Pill } from "../ui/kit/Pill";
import { ProgressBar } from "../ui/kit/ProgressBar";
import { RowsThatFit } from "../ui/kit/RowsThatFit";
import { SegmentedControl } from "../ui/kit/SegmentedControl";
import { MoreOptions, SettingsGroup, SettingsRow } from "../ui/kit/SettingsGroup";
import { StatusMessage } from "../ui/kit/StatusMessage";
import { Stepper } from "../ui/kit/Stepper";
import { TextField } from "../ui/kit/TextField";
import { ThemePreview } from "../ui/kit/ThemePreview";
import { Toggle } from "../ui/kit/Toggle";
import { Tooltip } from "../ui/kit/Tooltip";
import { TrackSlider } from "../ui/kit/TrackSlider";
import { accentCss, accentVariables, cssColor, type SpringToken, SPRING_TOKENS, themedSpring } from "../ui/kit/tokens";

const ACCENTS: Record<string, ModuleAccent> = {
  study: { red: 1.0, green: 0.62, blue: 0.26 },
  planner: { red: 0.66, green: 0.55, blue: 1.0 },
  spotify: { red: 0.12, green: 0.84, blue: 0.38 },
  claude: { red: 0.85, green: 0.47, blue: 0.34 },
  closet: { red: 0.98, green: 0.8, blue: 0.3 },
  anki: { red: 0.3, green: 0.66, blue: 1.0 },
};

const LONG_LINE = () =>
  tr("In the open notch, arrow keys or a two-finger swipe switch tabs, 1-9 jump to a tab, and Esc or a swipe up closes. On the closed notch, swipe down or middle-click to see the next live activity.");

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="gallery-section">
      <h2 className="gallery-section-title">{title}</h2>
      <div className="gallery-section-body">{children}</div>
    </section>
  );
}

function Row({ children, align }: { children: ReactNode; align?: "start" | "center" }) {
  return (
    <div className="gallery-row" data-align={align}>
      {children}
    </div>
  );
}

function Cell({ label, children, width, accent, column }: { label: string; children: ReactNode; width?: number; accent?: string; column?: boolean }) {
  const theme = useTheme();
  const vars = accent ? accentVariables(theme, ACCENTS[accent] ?? ACCENTS.study ?? { red: 1, green: 1, blue: 1 }) : {};
  return (
    <div className="gallery-cell" style={{ width, ...vars } as CSSProperties}>
      <div className="gallery-cell-body" data-column={column || undefined}>
        {children}
      </div>
      <div className="gallery-cell-label">{label}</div>
    </div>
  );
}

/** The open panel's canvas: 560 x 236, hardware black with the theme's glow, content inset 20 px from the sides. */
function Panel({ label, children, accent = "study" }: { label: string; children: ReactNode; accent?: string }) {
  const theme = useTheme();
  const vars = accentVariables(theme, ACCENTS[accent] ?? { red: 1, green: 1, blue: 1 });
  return (
    <div className="gallery-cell">
      <div className="gallery-panel" style={vars as CSSProperties}>
        <div className="gallery-panel-body">{children}</div>
      </div>
      <div className="gallery-cell-label">{label}</div>
    </div>
  );
}

function Swatch({ name, color }: { name: string; color: string }) {
  return (
    <div className="gallery-swatch">
      <span className="gallery-swatch-color" style={{ background: color }} />
      <span className="gallery-swatch-name">{name}</span>
    </div>
  );
}

export function Gallery({ themeId, language }: { themeId: ThemeID; language: string }) {
  const theme = useTheme();
  const [sliderValue, setSlider] = useState(0.62);
  const [toggle, setToggle] = useState(true);
  const [pace, setPace] = useState<MotionPace>("smooth");
  const [picked, setPicked] = useState<ThemeID>(themeId);
  const [text, setText] = useState("Mochi");
  const [minutes, setMinutes] = useState(25);
  const [hotkey, setHotkey] = useState<Hotkey>(DEFAULT_HOTKEY);
  const cat = PetProfile.starter("cat");
  const dog = PetProfile.starter("dog");
  const dressed = new PetProfile("Mochi", "orangeTabby", { outfit: "cozyHoodie", accessories: ["roundGlasses", "scarf"] });
  const rows = Array.from({ length: 6 }, (_, i) => ({ id: i, title: `${tr("Today")} ${i + 1}` }));
  const winL: Hotkey = { keyCode: 37, modifiers: HOTKEY_MODIFIERS.command };
  const studyAccent = accentCss(theme, ACCENTS.study ?? { red: 1, green: 1, blue: 1 });
  const closetAccent = accentCss(theme, ACCENTS.closet ?? { red: 1, green: 1, blue: 1 });

  return (
    <main className="gallery">
      <header className="gallery-header">
        <h1 className="gallery-title">Tabbi kit</h1>
        <span className="gallery-meta">
          {theme.name} ({theme.id}), {language}
        </span>
      </header>

      <Section title="Tokens">
        <Row>
          {paletteRoles(theme.palette).map(([role, color]) => (
            <Swatch key={role} name={role} color={cssColor(color)} />
          ))}
        </Row>
        <Row>
          {Object.entries(ACCENTS).map(([id, accent]) => (
            <Swatch key={id} name={`accent ${id}`} color={accentCss(theme, accent)} />
          ))}
        </Row>
        <Row align="start">
          <Cell label="title 13 / 600">
            <span className="kit-title">{tr("Start focus")}</span>
          </Cell>
          <Cell label="body 12 / 400">
            <span className="kit-body">{tr("Nothing playing")}</span>
          </Cell>
          <Cell label="bodyEmphasis 12 / 500">
            <span className="kit-body-emphasis">{tr("Saved chats")}</span>
          </Cell>
          <Cell label="caption 10.5 / 500">
            <span className="kit-caption kit-tertiary">{tr("More options")}</span>
          </Cell>
          <Cell label="metric 22 / 600 tabular">
            <span className="kit-metric">24:59</span>
          </Cell>
          <Cell label="metricSmall 13 / 600">
            <span className="kit-metric-small">5h 86%</span>
          </Cell>
        </Row>
        <Row>
          {[2, 4, 8, 12, 16, 24].map((s) => (
            <Cell key={s} label={`spacing ${s}`}>
              <span className="gallery-spacing" style={{ width: s }} />
            </Cell>
          ))}
          {[6, 10, 14].map((r) => (
            <Cell key={r} label={`radius ${r}`}>
              <span className="gallery-radius" style={{ borderRadius: r }} />
            </Cell>
          ))}
        </Row>
        <Row>
          {SPRING_TOKENS.map((token: SpringToken) => {
            const spec = themedSpring(theme, "smooth", token);
            return (
              <Cell key={token} label={`spring ${token}`}>
                <span className="kit-caption kit-secondary" dir="ltr">
                  {spec ? `${spec.duration.toFixed(2)} s, bounce ${spec.bounce.toFixed(2)}` : "instant"}
                </span>
              </Cell>
            );
          })}
        </Row>
      </Section>

      <Section title="Icons">
        <div className="gallery-icons">
          {ICON_IDS.map((id) => (
            <div key={id} className="gallery-icon">
              <Icon id={id} size={16} />
              <span className="gallery-icon-name">{id}</span>
            </div>
          ))}
          <div className="gallery-icon">
            <Icon id="not.a.symbol" size={16} />
            <span className="gallery-icon-name">unknown</span>
          </div>
        </div>
        <Row>
          <Cell label="12 px">
            <Row>
              {["timer", "checklist", "music-note", "sparkles", "paw-filled", "settings", "play-filled", "heart-filled"].map((id) => (
                <Icon key={id} id={id} size={12} />
              ))}
            </Row>
          </Cell>
          <Cell label="20 px">
            <Row>
              {["timer", "checklist", "music-note", "sparkles", "paw-filled", "settings", "play-filled", "heart-filled"].map((id) => (
                <Icon key={id} id={id} size={20} />
              ))}
            </Row>
          </Cell>
        </Row>
      </Section>

      <Section title="Card, IconButton, Pill">
        <Row align="start">
          <Cell label="Card">
            <Card style={{ width: 180 }}>
              <div className="kit-title">{tr("Today")}</div>
              <div className="kit-body kit-secondary">{tr("Nothing playing")}</div>
            </Card>
          </Cell>
          <Cell label="Card, padding 8" accent="planner">
            <Card padding={8} style={{ width: 180 }}>
              <div className="kit-body-emphasis">{tr("Saved chats")}</div>
              <div className="kit-caption kit-tertiary">{tr("Loading")}</div>
            </Card>
          </Cell>
        </Row>
        <Row>
          <Cell label="rest" accent="study">
            <IconButton symbol="settings" help={tr("Look")} />
          </Cell>
          <Cell label="hover">
            <IconButton symbol="settings" help={tr("Look")} preview="hover" />
          </Cell>
          <Cell label="pressed">
            <IconButton symbol="settings" help={tr("Look")} preview="pressed" />
          </Cell>
          <Cell label="selected" accent="closet">
            <IconButton symbol="paw-filled" help={tr("Closet")} selected tint={closetAccent} />
          </Cell>
          <Cell label="disabled">
            <IconButton symbol="settings" help={tr("Look")} disabled />
          </Cell>
          <Cell label="spinning">
            <IconButton symbol="refresh" help={tr("Try again")} spinning />
          </Cell>
          <Cell label="tooltip">
            <IconButton symbol="play-filled" help={tr("Start focus")} tooltipOpen lifts />
          </Cell>
          <Cell label="20 px">
            <IconButton symbol="close" size={20} help={tr("Cancel")} />
          </Cell>
          <Cell label="36 px, lifts">
            <IconButton symbol="play-filled" size={36} help={tr("Start focus")} lifts preview="hover" />
          </Cell>
        </Row>
        <Row>
          <Cell label="Pill" accent="study">
            <Pill title={tr("Start focus")} symbol="play-filled" />
          </Cell>
          <Cell label="hover" accent="study">
            <Pill title={tr("Start focus")} symbol="play-filled" preview="hover" />
          </Cell>
          <Cell label="accent, lifts" accent="study">
            <Pill title={tr("Start focus")} symbol="play-filled" accent lifts preview="hover" />
          </Cell>
          <Cell label="pressed" accent="study">
            <Pill title={tr("Try again")} preview="pressed" />
          </Cell>
          <Cell label="disabled" accent="study">
            <Pill title={tr("Try again")} disabled />
          </Cell>
          <Cell label="Pill prominent, badge, busy, icon only" accent="anki">
            <Pill title={tr("Study %@", "Biology")} symbol="play-filled" prominent badge={92} height={28} lifts />
            <Pill title={tr("Study %@", "Biology")} symbol="play-filled" prominent badge={92} height={28} preview="hover" />
            <Pill title={tr("Join")} prominent height={20} />
            <Pill title={tr("Leave")} busy />
            <Pill title="" help={tr("Start a party")} symbol="plus" prominent />
          </Cell>
        </Row>
      </Section>

      <Section title="ContextMenu">
        <Row align="start">
          <Cell label="A friend row's menu, open" accent="study" width={240}>
            <div style={{ position: "relative", height: 112 }}>
              <ContextMenu
                items={[
                  { title: tr("Remove %@", "Maya"), symbol: "minus.circle.fill", destructive: true, onSelect: () => {} },
                  { title: tr("Report %@…", "Maya"), symbol: "exclamationmark.triangle", separator: true, onSelect: () => {} },
                  { title: tr("Block %@", "Maya"), symbol: "hand.raised.fill", destructive: true, onSelect: () => {} },
                ]}
                at={{ x: 0, y: 0 }}
                onClose={() => {}}
              />
            </div>
          </Cell>
        </Row>
      </Section>

      <Section title="TrackSlider">
        <Row>
          <Cell label="rest" accent="spotify" width={200}>
            <TrackSlider value={sliderValue} onChange={setSlider} help={`${Math.round(sliderValue * 100)}%`} label="Volume" />
          </Cell>
          <Cell label="hover: knob 1.25x, track 6" accent="spotify" width={200}>
            <TrackSlider value={0.35} onChange={() => {}} trackHeight={4} activeTrackHeight={6} help="35%" label="Volume" preview="hover" />
          </Cell>
          <Cell label="whileActive knob, idle tint" accent="spotify" width={200}>
            <TrackSlider value={0.5} onChange={() => {}} knobVisibility="whileActive" idleTint="var(--secondary-text)" help="1:30" label="Position" />
          </Cell>
          <Cell label="whileActive, hovered" accent="spotify" width={200}>
            <TrackSlider value={0.5} onChange={() => {}} knobVisibility="whileActive" idleTint="var(--secondary-text)" help="1:30" label="Position" preview="hover" />
          </Cell>
          <Cell label="disabled" accent="spotify" width={200}>
            <TrackSlider value={0.8} onChange={() => {}} help="80%" label="Volume" disabled />
          </Cell>
        </Row>
        <Row>
          <Cell label="ProgressBar: accent" accent="spotify" width={200}>
            <ProgressBar value={0.35} help="1:27" label="Playback position" />
          </Cell>
          <Cell label="ProgressBar: primary, 6 px" accent="spotify" width={200}>
            <ProgressBar value={0.35} tint="var(--primary-text)" height={6} help="1:27" label="Playback position" />
          </Cell>
          <Cell label="ProgressBar: success" width={200}>
            <ProgressBar value={0.7} tint="var(--success)" help={tr("Memory pressure: %@", "Normal")} label={tr("Memory")} />
          </Cell>
          <Cell label="ProgressBar: danger" width={200}>
            <ProgressBar value={0.95} tint="var(--danger)" help={tr("Memory pressure: %@", "Critical")} label={tr("Memory")} />
          </Cell>
        </Row>
      </Section>

      <Section title="MarqueeText, RowsThatFit, EdgeFade">
        <Row align="start">
          <Cell label="fits" width={220}>
            <MarqueeText text={tr("Nothing playing")} />
          </Cell>
          <Cell label="overflows, at rest" width={220} accent="study">
            <MarqueeText text={LONG_LINE()} />
          </Cell>
          <Cell label="overflows, half way" width={220}>
            <KitProvider themeId={themeId} still marqueeScrolled={0.5}>
              <MarqueeText text={LONG_LINE()} />
            </KitProvider>
          </Cell>
          <Cell label="overflows, at the end" width={220}>
            <KitProvider themeId={themeId} still marqueeScrolled={1}>
              <MarqueeText text={LONG_LINE()} />
            </KitProvider>
          </Cell>
        </Row>
        <Row align="start">
          <Cell label="RowsThatFit: 6 rows, 150 px" width={200}>
            <Card style={{ height: 150, display: "flex", flexDirection: "column" }}>
              <RowsThatFit data={rows} keyOf={(r) => r.id} spacing={4} style={{ flex: 1 }} row={(r) => <div className="gallery-list-row">{r.title}</div>} />
            </Card>
          </Cell>
          <Cell label="RowsThatFit: 6 rows, 80 px, header" width={200}>
            <Card style={{ height: 80, display: "flex", flexDirection: "column" }}>
              <RowsThatFit
                data={rows}
                keyOf={(r) => r.id}
                spacing={4}
                style={{ flex: 1 }}
                header={(shown) => (
                  <div className="kit-caption kit-tertiary">
                    {shown} / {rows.length}
                  </div>
                )}
                row={(r) => <div className="gallery-list-row">{r.title}</div>}
              />
            </Card>
          </Cell>
          <Cell label="EdgeFade bottom, 16 px" width={200}>
            <Card style={{ height: 80, display: "flex", flexDirection: "column" }}>
              <EdgeFade edge="bottom" style={{ flex: 1 }}>
                {rows.map((r) => (
                  <div key={r.id} className="gallery-list-row">
                    {r.title}
                  </div>
                ))}
              </EdgeFade>
            </Card>
          </Cell>
          <Cell label="EdgeFade end (inline)" width={200}>
            <Card style={{ width: 200 }}>
              <EdgeFade edge="end" style={{ whiteSpace: "nowrap" }}>
                {LONG_LINE()}
              </EdgeFade>
            </Card>
          </Cell>
        </Row>
      </Section>

      <Section title="StatusMessage (560 x 236)">
        <Row align="start">
          <Panel label="empty, with action" accent="spotify">
            <StatusMessage
              symbol="music-note"
              title={tr("No music app is open")}
              message={tr("Open Spotify or Music to see what is playing")}
              actions={<Pill title={tr("Open Spotify")} symbol="open-app" accent lifts />}
            />
          </Panel>
          <Panel label="loading" accent="claude">
            <StatusMessage symbol={null} title={tr("Thinking")} message={tr("Loading")} />
          </Panel>
        </Row>
        <Row align="start">
          <Panel label="error, with action" accent="anki">
            <StatusMessage
              symbol="warning"
              tint="var(--danger)"
              title={tr("Couldn't check your shortcuts")}
              message={tr("The Shortcuts app didn't answer in time. Try again in a moment.")}
              actions={<Pill title={tr("Try again")} symbol="refresh" />}
            />
          </Panel>
          <Panel label="empty, with the pet" accent="spotify">
            <StatusMessage symbol="music-note" title={tr("No music app is open")} message={tr("Nothing playing")} pet={cat} />
          </Panel>
        </Row>
      </Section>

      <Section title="ModulePlaceholder, ModulePreview (560 x 236)">
        <Row align="start">
          <Panel label="ModulePlaceholder" accent="planner">
            <ModulePlaceholder symbol="checklist" detail={tr("In development")} />
          </Panel>
          <Panel label="ModulePreview" accent="anki">
            <ModulePreview
              symbol="cards"
              title="Anki"
              pitch={tr("Review your cards from the notch")}
              features={[
                { symbol: "cards", title: tr("Cards due"), detail: tr("Loading") },
                { symbol: "flame", title: tr("Streak"), detail: LONG_LINE() },
                { symbol: "clock", title: tr("Today"), detail: tr("Nothing playing") },
              ]}
            />
          </Panel>
        </Row>
      </Section>

      <Section title="ThemePreview, FoundingBadge">
        <Row>
          {allThemes.map((t) => (
            <Cell key={t.id} label={t.name}>
              <ThemePreview theme={t} accents={[ACCENTS.study, ACCENTS.planner, ACCENTS.spotify, ACCENTS.claude].filter((a): a is ModuleAccent => a !== undefined)} />
            </Cell>
          ))}
        </Row>
        <Row>
          <Cell label="seal">
            <span className="kit-body">
              Ethan <FoundingBadge isMe />
            </span>
          </Cell>
          <Cell label="seal, tooltip">
            <span className="kit-body">
              Mochi <FoundingBadge isMe={false} tooltipOpen />
            </span>
          </Cell>
          <Cell label="label">
            <FoundingBadge style="label" isMe />
          </Cell>
        </Row>
      </Section>

      <Section title="Loading">
        <Row>
          <Cell label="Spinner 12">
            <Spinner />
          </Cell>
          <Cell label="Spinner 14, accent" accent="study">
            <Spinner tint="var(--accent)" size={14} lineWidth={2} />
          </Cell>
          <Cell label="Spinner 24" accent="claude">
            <Spinner tint="var(--accent)" size={24} time={0.4} />
          </Cell>
          <Cell label="Placeholder (redacted)">
            <span className="kit-metric">
              <Placeholder width={64} height={18} />
            </span>
          </Cell>
          <Cell label="Skeleton + shimmer" width={200}>
            <Shimmer time={0.5} style={{ width: 180 }}>
              <SkeletonLine fraction={0.9} />
              <SkeletonLine fraction={0.6} />
              <SkeletonLine width={48} />
            </Shimmer>
          </Cell>
        </Row>
        <Row>
          {[0, 0.25, 0.62, 1].map((p) => (
            <Cell key={p} label={`ProgressRing ${p}`} accent="study">
              <ProgressRing progress={p} size={44}>
                <span className="kit-metric-small">{Math.round(p * 100)}</span>
              </ProgressRing>
            </Cell>
          ))}
          <Cell label="ProgressRing 20, empty" accent="anki">
            <ProgressRing progress={undefined} size={20} lineWidth={2} />
          </Cell>
        </Row>
        <Row>
          {[0, 0.2, 0.5, 0.9, 1.3, 1.8].map((t) => (
            <Cell key={t} label={`PawLoader ${t.toFixed(1)} s`} accent="claude">
              <PawLoader time={t} size={16} />
            </Cell>
          ))}
          <Cell label="PawLoader 24, revealed" accent="closet">
            <PawLoader size={24} revealed time={0.4} />
          </Cell>
        </Row>
        <Row>
          {[0, 0.15, 0.3, 0.45, 0.6, 0.8, 1, 1.08].map((p) => (
            <Cell key={p} label={`CheckGlyph ${p}`} accent="planner">
              <CheckGlyph isOn={p > 0} progress={p} size={24} />
            </Cell>
          ))}
          <Cell label="CheckGlyph 16 on" accent="planner">
            <CheckGlyph isOn progress={1} />
          </Cell>
          <Cell label="CheckGlyph 16 off" accent="planner">
            <CheckGlyph isOn={false} progress={0} />
          </Cell>
        </Row>
      </Section>

      <Section title="Celebration (frames)">
        {(["burst", "milestone"] as CelebrationTier[]).map((tier) => (
          <Row key={tier} align="start">
            {CELEBRATION_STYLES.map((style: CelebrationStyle) => (
              <Cell key={style} label={`${style} ${tier}, 0.35 s`} accent="study">
                <div className="gallery-stage">
                  <CelebrationBurstView celebration={makeCelebration({ tier, style, accent: studyAccent, theme, startedAt: 0, seed: 7 })} elapsed={0.35} />
                </div>
              </Cell>
            ))}
            <Cell label={`confetti ${tier}, 0.9 s`} accent="study">
              <div className="gallery-stage">
                <CelebrationBurstView celebration={makeCelebration({ tier, style: "confetti", accent: studyAccent, theme, startedAt: 0, seed: 7 })} elapsed={0.9} />
              </div>
            </Cell>
          </Row>
        ))}
        <Row align="start">
          <Cell label="glow (Reduce Motion), 0.3 s" accent="study">
            <div className="gallery-stage">
              <CelebrationGlow celebration={makeCelebration({ tier: "burst", style: "confetti", accent: studyAccent, theme, startedAt: 0 })} elapsed={0.3} />
            </div>
          </Cell>
        </Row>
      </Section>

      <Section title="PetView">
        <Row align="start">
          <Cell label="cat, pixelSize 1 (32 px)">
            <PetView profile={cat} />
          </Cell>
          <Cell label="dog, pixelSize 1">
            <PetView profile={dog} />
          </Cell>
          <Cell label="dressed, pixelSize 2 (64 px)">
            <PetView profile={dressed} pixelSize={2} />
          </Cell>
          <Cell label="pixelSize 0.75 (24 px)">
            <PetView profile={cat} pixelSize={0.75} />
          </Cell>
          <Cell label="PetSprite (sitting), 2">
            <PetSprite profile={dressed} pixelSize={2} />
          </Cell>
          <Cell label="PetSprite dog, 3">
            <PetSprite profile={dog} pixelSize={3} />
          </Cell>
        </Row>
      </Section>

      <Section title="HotkeyRecorder">
        <Row align="start">
          <Cell label="rest">
            <HotkeyRecorder hotkey={hotkey} onRecord={setHotkey} />
          </Cell>
          <Cell label="hover">
            <HotkeyRecorder hotkey={DEFAULT_HOTKEY} onRecord={() => {}} preview="hover" />
          </Cell>
          <Cell label="recording">
            <HotkeyRecorder hotkey={DEFAULT_HOTKEY} onRecord={() => {}} recordingPreview />
          </Cell>
          <Cell label="conflict from the host">
            <HotkeyRecorder hotkey={DEFAULT_HOTKEY} onRecord={() => {}} conflict={tr("%@ is already used by another app. Record a different shortcut.", "Ctrl+Alt+Space")} />
          </Cell>
          <Cell label="reserved by Windows">
            <HotkeyRecorder hotkey={winL} onRecord={() => {}} />
          </Cell>
          <Cell label="disabled">
            <HotkeyRecorder hotkey={DEFAULT_HOTKEY} onRecord={() => {}} disabled />
          </Cell>
        </Row>
      </Section>

      <Section title="Settings controls">
        <Row>
          <Cell label="Toggle on" accent="planner">
            <Toggle isOn={toggle} onChange={setToggle} label={tr("Launch at login")} />
          </Cell>
          <Cell label="off" accent="planner">
            <Toggle isOn={false} onChange={() => {}} label={tr("Launch at login")} />
          </Cell>
          <Cell label="on, hover" accent="planner">
            <Toggle isOn onChange={() => {}} label={tr("Launch at login")} preview="hover" />
          </Cell>
          <Cell label="off, pressed" accent="planner">
            <Toggle isOn={false} onChange={() => {}} label={tr("Launch at login")} preview="pressed" />
          </Cell>
          <Cell label="disabled" accent="planner">
            <Toggle isOn onChange={() => {}} label={tr("Launch at login")} disabled />
          </Cell>
        </Row>
        <Row>
          <Cell label="SegmentedControl" accent="planner">
            <SegmentedControl
              label={tr("Smooth")}
              segments={MOTION_PACES.map((p) => ({ id: p, title: motionPaceTitle(p), help: motionPaceCaption(p) }))}
              selected={pace}
              onSelect={setPace}
            />
          </Cell>
          <Cell label="hover on a segment" accent="planner">
            <SegmentedControl
              label={tr("Smooth")}
              segments={MOTION_PACES.map((p) => ({ id: p, title: motionPaceTitle(p), help: motionPaceCaption(p) }))}
              selected="smooth"
              onSelect={() => {}}
              preview={{ id: "fast", state: "hover" }}
            />
          </Cell>
          <Cell label="with icons, disabled" accent="planner">
            <SegmentedControl
              label={tr("Look")}
              segments={[
                { id: "a", title: tr("Pet"), symbol: "paw-filled" },
                { id: "b", title: tr("Today"), symbol: "checklist" },
              ]}
              selected="a"
              onSelect={() => {}}
              disabled
            />
          </Cell>
        </Row>
        <Row align="start">
          <Cell label="Picker" accent="planner">
            <Picker label={tr("Look")} items={allThemes.map((t) => ({ id: t.id, title: t.name, caption: t.summary }))} selected={picked} onSelect={setPicked} />
          </Cell>
          <Cell label="Picker hover" accent="planner">
            <Picker label={tr("Look")} items={allThemes.map((t) => ({ id: t.id, title: t.name }))} selected={picked} onSelect={() => {}} preview="hover" />
          </Cell>
          <Cell label="Picker open" accent="planner" width={260}>
            <div style={{ height: 232 }}>
              <Picker
                label={tr("Look")}
                items={allThemes.slice(0, 5).map((t, i) => ({ id: t.id, title: t.name, caption: i === 1 ? t.summary : undefined, disabled: i === 4 }))}
                selected={allThemes[0]?.id ?? picked}
                onSelect={() => {}}
                open
              />
            </div>
          </Cell>
          <Cell label="disabled" accent="planner">
            <Picker label={tr("Look")} items={[{ id: "x", title: tr("Instant"), symbol: "moon" }]} selected="x" onSelect={() => {}} disabled />
          </Cell>
        </Row>
        <Row>
          <Cell label="TextField" accent="planner">
            <TextField value={text} onChange={setText} label={tr("Pet")} placeholder={tr("Pet")} />
          </Cell>
          <Cell label="empty, placeholder" accent="planner">
            <TextField value="" onChange={() => {}} label={tr("Add a task")} placeholder={tr("Add a task")} symbol="plus" />
          </Cell>
          <Cell label="hover" accent="planner">
            <TextField value="" onChange={() => {}} label={tr("Add a task")} placeholder={tr("Add a task")} preview="hover" />
          </Cell>
          <Cell label="focused" accent="planner">
            <TextField value={tr("Add a task")} onChange={() => {}} label={tr("Add a task")} preview="focus" />
          </Cell>
          <Cell label="secure, disabled" accent="planner">
            <TextField value="sk-ant-123456" onChange={() => {}} label="API key" secure disabled symbol="key" />
          </Cell>
        </Row>
        <Row>
          <Cell label="Stepper" accent="study">
            <Stepper value={minutes} onChange={setMinutes} min={1} max={180} step={5} label={tr("Timer")} format={(v) => `${v} min`} />
          </Cell>
          <Cell label="at min, plus hovered" accent="study">
            <Stepper value={1} onChange={() => {}} min={1} max={180} label={tr("Timer")} preview={{ button: "plus", state: "hover" }} />
          </Cell>
          <Cell label="disabled" accent="study">
            <Stepper value={25} onChange={() => {}} label={tr("Timer")} disabled />
          </Cell>
        </Row>
        <Row align="start">
          <Cell label="SettingsGroup" accent="planner" width={420} column>
            <SettingsGroup title={tr("General")} footer={tr("Choose when the notch is drawn. The shortcut always opens it.")}>
              <SettingsRow label={tr("Launch at login")} help={tr("Start with Windows")} tooltip={tr("Launch at login")}>
                <Toggle isOn={toggle} onChange={setToggle} label={tr("Launch at login")} />
              </SettingsRow>
              <SettingsRow label={tr("Shortcut")} symbol="timer" stacked>
                <HotkeyRecorder hotkey={hotkey} onRecord={setHotkey} />
              </SettingsRow>
              <SettingsRow label={tr("Look")} help={theme.summary}>
                <Picker label={tr("Look")} items={allThemes.map((t) => ({ id: t.id, title: t.name }))} selected={picked} onSelect={setPicked} />
              </SettingsRow>
              <SettingsRow label={tr("Smooth")} tooltip={motionPaceCaption(pace)}>
                <SegmentedControl label={tr("Smooth")} segments={MOTION_PACES.map((p) => ({ id: p, title: motionPaceTitle(p) }))} selected={pace} onSelect={setPace} />
              </SettingsRow>
            </SettingsGroup>
            <MoreOptions open>
              <SettingsRow label={tr("Timer")} help={LONG_LINE()}>
                <Stepper value={minutes} onChange={setMinutes} min={1} max={180} label={tr("Timer")} />
              </SettingsRow>
            </MoreOptions>
          </Cell>
          <Cell label="Tooltip placements" width={200}>
            <Row>
              <Tooltip text={tr("Loading")} open placement="above">
                <span className="kit-pill">{tr("More")}</span>
              </Tooltip>
            </Row>
          </Cell>
        </Row>
      </Section>
    </main>
  );
}

