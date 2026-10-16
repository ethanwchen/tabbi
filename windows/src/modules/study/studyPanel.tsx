/*
 * Port of StudyPanel: the Study tab. A countdown dial on the left (the
 * panel's primary element), and on the right the method in use and the
 * timer controls. Tapping the method swaps the panel for an in-island
 * method picker, and each method's (i) for its info view, since a system
 * menu or popover would pop outside the island.
 */

import { useEffect, type ReactNode } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { durationMinutes, durationProgress } from "../../core/formatting/durationFormat";
import { currentLanguage, tr } from "../../core/localization/tr";
import { MODULE_IDS } from "../../core/modules/moduleId";
import type { ProvidedPartySession } from "../../core/providers/providedParty";
import { presetMethod } from "../../core/studyMethods/studyCustomRhythm";
import { isBreakPhase, type StudyMethodKind } from "../../core/studyMethods/studyMethod";
import { methodInfo, nameIsRhythm } from "../../core/studyMethods/studyMethodInfo";
import { studyClock, studyPoints, studyPrimaryAction, studyReadout, studyRoundLabel } from "../../core/studyMethods/studyTimerFormat";
import { StudyTimerLength } from "../../core/studyMethods/studyTimerLength";
import type { ModuleAccent } from "../../core/themes/themeColor";
import { CapsuleToggle } from "../../ui/kit/CapsuleToggle";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { ProgressRing } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { PetView } from "../../ui/kit/PetView";
import { PrimaryPill } from "../../ui/kit/PrimaryPill";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { FocusController } from "../focus/focusController";
import { PanelCelebrations } from "../focus/panelCelebrations";
import { StudyCustomEditor, StudyEditButton } from "./studyCustomEditor";
import { StudyInfoButton, StudyMethodInfoView } from "./studyMethodInfoView";
import { StudyMethodTile } from "./studyMethodTile";
import { andList, StudySoundButton, StudySoundMixer } from "./studySoundViews";
import type { StudyPanelOverlay, StudyStore } from "./studyStore";
import "./study.css";

export interface StudyPanelProps {
  readonly store: StudyStore;
  /** Focus mode, whose sound deep focus blocks use. */
  readonly focusMode: FocusController;
  readonly context: ModuleContext;
  readonly accent: ModuleAccent;
}

export function StudyPanel({ store, focusMode, context, accent }: StudyPanelProps) {
  const state = useStore(store);
  useEffect(() => {
    store.setVisible(true);
    return () => store.setVisible(false);
  }, [store]);
  const show = (next: StudyPanelOverlay | undefined) => store.show(next);
  const overlay = state.overlay;
  let content: ReactNode;
  switch (overlay?.kind) {
    case "picker":
      content = (
        <StudyMethodPicker
          store={store}
          info={(kind) => show({ kind: "info", method: kind, from: overlay })}
          done={(kind) => {
            if (kind !== undefined) store.choose(kind);
            /* Custom opens its lengths right away, so picking it is never a guess. */
            show(kind === "custom" ? { kind: "custom" } : undefined);
          }}
        />
      );
      break;
    case "info":
      content = (
        <StudyMethodInfoView
          method={presetMethod(overlay.method, state.custom, state.timer)}
          isCurrent={overlay.method === state.session.method.kind}
          use={() => {
            store.choose(overlay.method);
            show(undefined);
          }}
          close={() => show(overlay.from)}
        />
      );
      break;
    case "sounds":
      content = <StudySoundMixer focus={focusMode} close={() => show(undefined)} />;
      break;
    case "custom":
      content = <StudyCustomEditor store={store} close={() => show(undefined)} />;
      break;
    case undefined:
      content =
        state.partySession !== undefined ? (
          <StudyPartySessionView store={store} session={state.partySession} />
        ) : (
          <div className="study-timer">
            <StudyDial store={store} />
            <div className="study-column">
              <StudyMethodCard
                store={store}
                focusMode={focusMode}
                choose={() => show({ kind: "picker" })}
                info={() => show({ kind: "info", method: state.session.method.kind, from: undefined })}
                sounds={() => show({ kind: "sounds" })}
                edit={() => show({ kind: "custom" })}
              />
              <StudyControls store={store} />
            </div>
          </div>
        );
  }
  return (
    <PanelCelebrations
      className="study-panel"
      requests={(play) => store.celebrations.on(() => play("pawPrints"))}
      accent={accent}
      source={MODULE_IDS.study}
      now={() => context.now()}
      timeZone={() => context.timeZone()}
    >
      {content}
    </PanelCelebrations>
  );
}

/** The time (or cards) inside a progress ring, with the phase underneath, and the pet in the corner. */
function StudyDial({ store }: { store: StudyStore }) {
  const { session, now } = useStore(store);
  const readout = studyReadout(session, now);
  const progress = session.progress(now);
  const waitsForCards = session.phase === "focus" && session.method.cardGoal !== undefined && !store.canCountCards;
  const petName = store.pet.profile.name;
  const petHelp = !session.isRunning
    ? tr("%@ naps until the timer runs", petName)
    : isBreakPhase(session.phase)
      ? tr("%@ is taking the break with you", petName)
      : tr("%@ is studying with you", petName);
  return (
    <Tooltip text={readout.caption === "" ? tr("Timer: %@", readout.value) : `${readout.caption}: ${readout.value}`}>
      <Card padding={0} className="study-dial">
        {/* Open-ended Flowtime has no finish line, so its ring stays a quiet track. */}
        <ProgressRing progress={progress} size={128} lineWidth={6} tint={progress === undefined ? "var(--tertiary-text)" : "var(--accent)"}>
          <div className="study-dial-center">
            <span className="study-dial-value" data-long={readout.value.length > 5 || undefined} data-running={session.isRunning}>
              {readout.value}
            </span>
            {readout.caption !== "" && (
              <span className="kit-caption" style={{ color: isBreakPhase(session.phase) ? "var(--accent)" : "var(--tertiary-text)" }}>
                {readout.caption}
              </span>
            )}
            {waitsForCards && (
              <Tooltip text={tr("Turn on the Anki tab with Anki open so the sprint can count your cards")}>
                <span className="kit-caption study-dial-waiting">{tr("Waiting for Anki")}</span>
              </Tooltip>
            )}
          </div>
        </ProgressRing>
        <Tooltip text={petHelp}>
          <div className="study-dial-pet">
            <PetView player={store.pet} />
          </div>
        </Tooltip>
      </Card>
    </Tooltip>
  );
}

/** A party's shared session in place of the user's own timer. Port of StudyPartySessionView. */
function StudyPartySessionView({ store, session }: { store: StudyStore; session: ProvidedPartySession }) {
  const { now, goal } = useStore(store);
  const remaining = session.remaining(now);
  const clock = studyClock(remaining);
  const petName = store.pet.profile.name;
  const endsAt = new Intl.DateTimeFormat(currentLanguage(), { hour: "numeric", minute: "2-digit" }).format(new Date(session.endsAt * 1000));
  const startedBy = session.hostName === undefined ? tr("You started it for the party") : tr("%@ started it for the party", session.hostName);
  return (
    <div className="study-timer">
      <Tooltip text={tr("Shared focus: %@ left", clock)}>
        <Card padding={0} className="study-dial">
          <ProgressRing progress={session.length > 0 ? 1 - remaining / session.length : 0} size={128} lineWidth={6}>
            <div className="study-dial-center">
              <span className="study-dial-value" data-running>
                {clock}
              </span>
              <span className="kit-caption kit-tertiary">{tr("Focus")}</span>
            </div>
          </ProgressRing>
          <Tooltip text={tr("%@ is studying with the party", petName)}>
            <div className="study-dial-pet">
              <PetView player={store.pet} />
            </div>
          </Tooltip>
        </Card>
      </Tooltip>
      <div className="study-column">
        <Card className="study-card">
          <div className="study-caption-row kit-caption kit-tertiary">
            <span>{tr("Party session")}</span>
            <span className="study-spacer" />
            <Tooltip text={session.friendCount === 0 ? tr("Everyone else has stepped out") : tr("Friends in this session now")}>
              <span className="study-label">
                <Icon id="person.2.fill" size={9} />
                <span>{session.companyLine}</span>
              </span>
            </Tooltip>
          </div>
          <MarqueeText className="kit-title" text={session.methodName} />
          <MarqueeText className="kit-caption kit-secondary" text={startedBy} userText />
          <MarqueeText className="kit-caption kit-tertiary study-tabular" text={tr("Ends at %@", endsAt)} />
          <span className="study-spacer" />
          <StudyTodayRow today={store.today} goalMinutes={goal.minutes} />
        </Card>
        <Tooltip
          text={
            session.isHost
              ? tr("The session runs for the whole party until it ends or you end it")
              : tr("Stepping out keeps the session going for the others; your own timer comes back here")
          }
        >
          <div className="study-party-note kit-caption kit-tertiary">
            <Icon id="person.3.fill" size={10} className="study-accent" />
            <MarqueeText text={session.isHost ? tr("End it for everyone in the Party tab") : tr("Step out in the Party tab anytime")} />
          </div>
        </Tooltip>
      </div>
    </div>
  );
}

/**
 * The method in use, its rhythm and round, the deep focus switch with the
 * sound button, and today's tally at the bottom. The name opens the picker,
 * the (i) the method's info view, and the sound button the mixer.
 */
function StudyMethodCard({
  store,
  focusMode,
  choose,
  info,
  sounds,
  edit,
}: {
  store: StudyStore;
  focusMode: FocusController;
  choose: () => void;
  info: () => void;
  sounds: () => void;
  edit: () => void;
}) {
  const { session, timer, goal } = useStore(store);
  const text = methodInfo(session.method);
  const round = studyRoundLabel(session);
  return (
    <Card className="study-card study-method-card">
      <div className="study-caption-row kit-caption kit-tertiary">
        <span>{tr("Method")}</span>
        <span className="study-spacer" />
        {round !== undefined && <span className="study-tabular">{round}</span>}
        {session.method.kind === "custom" && <StudyEditButton onClick={edit} />}
        <StudyInfoButton method={session.method.kind} onClick={info} />
      </div>
      <Tooltip text={tr("Change the timer method")}>
        <button type="button" className="study-method-name" onClick={choose}>
          <span className="study-method-title kit-title">
            <span>{text.displayName}</span>
            {/* The Timer's length row already shows its length. */}
            {!nameIsRhythm(session.method) && session.method.kind !== "timer" && <span className="study-accent study-rhythm">{session.method.rhythmLabel}</span>}
            <Icon id="chevron.up.chevron.down" size={9} className="study-method-chevron" />
          </span>
          {session.method.kind !== "timer" && <MarqueeText className="kit-caption kit-secondary study-method-tagline" text={text.displayTagline} userText />}
        </button>
      </Tooltip>
      {session.method.kind === "timer" && <StudyTimerLengthRow length={timer} isCounting={session.runState !== "idle"} set={(next) => store.setTimer(next)} start={(next) => store.startTimer(next)} />}
      <span className="study-spacer" />
      <StudyDeepFocusRow store={store} focus={focusMode} openMixer={sounds} />
      <span className="study-spacer" />
      <StudyTodayRow today={store.today} goalMinutes={goal.minutes} />
    </Card>
  );
}

/** The Timer's lengths: one click starts a common one, and a stepper sets any other, so a custom length needs no extra screen. */
function StudyTimerLengthRow({ length, isCounting, set, start }: { length: StudyTimerLength; isCounting: boolean; set: (length: StudyTimerLength) => void; start: (length: StudyTimerLength) => void }) {
  return (
    <div className="study-timer-lengths">
      {StudyTimerLength.presets.map((minutes) => (
        <CapsuleToggle
          key={minutes}
          className="study-timer-chip study-tabular"
          title={tr("%lld min", minutes)}
          isOn={length.minutes === minutes}
          outlined={false}
          height={22}
          help={
            isCounting
              ? tr("Change the countdown to %lld minutes, or to a minute from now if that time has passed", minutes)
              : tr("Start a %lld minute countdown", minutes)
          }
          onClick={() => start(new StudyTimerLength(minutes))}
        />
      ))}
      <span className="study-spacer" />
      <IconButton symbol="minus" help={tr("A shorter timer")} disabled={!length.canStep(false)} onClick={() => set(length.stepped(false))} />
      <IconButton symbol="plus" help={tr("A longer timer")} disabled={!length.canStep(true)} onClick={() => set(length.stepped(true))} />
    </div>
  );
}

/** The deep focus switch, and the focus sound study blocks play with it. */
function StudyDeepFocusRow({ store, focus, openMixer }: { store: StudyStore; focus: FocusController; openMixer: () => void }) {
  const { deepFocus } = useStore(store);
  const { settings } = useStore(focus);
  /* The focus mode effects that study blocks apply, e.g. "rain + fireplace and your playlist". */
  const parts: string[] = [];
  if (!settings.mix.isOff) parts.push(settings.mix.summary.toLowerCase());
  if (settings.playlist !== undefined) parts.push(tr("your playlist"));
  const summary = parts.length === 0 ? tr("nothing yet; pick a sound") : parts.length === 1 ? (parts[0] ?? "") : andList(parts);
  return (
    <div className="study-deep-focus">
      <CapsuleToggle
        className="study-deep-focus-switch"
        title={tr("Deep focus")}
        symbol="moon"
        isOn={deepFocus}
        help={deepFocus ? tr("Deep focus is on: focus blocks bring %@. Click to turn it off", summary) : tr("Turn on deep focus: focus blocks bring %@", summary)}
        onClick={() => store.setDeepFocus(!deepFocus)}
      />
      <span className="study-spacer" />
      <StudySoundButton focus={focus} isActive={deepFocus} openMixer={openMixer} />
    </div>
  );
}

/** Today's focus minutes, finished blocks and the points they earned for the pet. */
export function StudyTodayRow({ today, goalMinutes }: { today: { minutes: number; sessions: number; points: number }; goalMinutes: number }) {
  const metGoal = today.minutes >= goalMinutes;
  return (
    <div className="study-today kit-caption kit-secondary study-tabular">
      <span className="kit-tertiary">{tr("Today")}</span>
      <Tooltip text={metGoal ? tr("Daily focus goal met") : tr("Focus time today, out of your daily goal")}>
        <span className="study-label" data-met={metGoal || undefined}>
          <Icon id={metGoal ? "checkmark.seal.fill" : "clock"} size={9} />
          <span className="study-today-goal">{durationProgress(today.minutes, goalMinutes)}</span>
          <span className="study-today-plain">{durationMinutes(today.minutes)}</span>
        </span>
      </Tooltip>
      <Tooltip text={tr("Focus blocks finished today")}>
        <span className="study-label">
          <Icon id="checkmark.circle" size={9} />
          <span>{tr("%lld done", today.sessions)}</span>
        </span>
      </Tooltip>
      <span className="study-spacer" />
      <Tooltip text={tr("Points earned today; spend them on your pet's wardrobe")}>
        <span className="study-label" data-met={today.points > 0 || undefined} data-points>
          <Icon id="star.fill" size={9} />
          <span>{studyPoints(today.points)}</span>
        </span>
      </Tooltip>
    </div>
  );
}

/** Every method the kit offers as a tile; picking one starts a fresh session with it. */
function StudyMethodPicker({ store, info, done }: { store: StudyStore; info: (kind: StudyMethodKind) => void; done: (kind: StudyMethodKind | undefined) => void }) {
  const { session } = useStore(store);
  const current = session.method.kind;
  return (
    <div className="study-picker">
      <div className="study-caption-row kit-caption kit-tertiary">
        <span>{tr("Choose a method")}</span>
        <span className="study-spacer" />
        <IconButton symbol="xmark" help={tr("Keep the current method")} onClick={() => done(undefined)} />
      </div>
      <div className="study-picker-grid">
        {store.methods.map((method) => (
          <StudyMethodTile key={method.kind} method={method} isCurrent={method.kind === current} info={info} onPick={() => done(method.kind)} />
        ))}
      </div>
    </div>
  );
}

/** The primary action, then pause (Flowtime only), skip (not for the Timer, which has no breaks) and stop. */
function StudyControls({ store }: { store: StudyStore }) {
  const { session } = useStore(store);
  /* A fresh focus phase has nothing to skip or stop. */
  const isFresh = session.runState === "idle" && session.phase === "focus";
  const isFlowing = session.isRunning && session.phase === "focus" && session.method.focus.kind === "openEnded";
  const primarySymbol = !session.isRunning ? "play.fill" : isFlowing ? "cup.and.saucer.fill" : "pause.fill";
  const primaryHelp = (() => {
    switch (session.runState) {
      case "running":
        return isFlowing ? tr("End this stretch and take a sized break") : tr("Pause the timer");
      case "paused":
        return tr("Resume the timer");
      case "idle":
        if (session.method.kind === "timer") return tr("Start the countdown");
        return isBreakPhase(session.phase) ? tr("Start the break") : tr("Start studying");
    }
  })();
  const skipHelp = session.phase === "focus" ? tr("Skip to the break") : session.phase === "review" ? tr("Skip the review") : tr("Skip the break");
  return (
    <div className="study-controls">
      <PrimaryPill title={studyPrimaryAction(session)} symbol={primarySymbol} help={primaryHelp} onClick={() => store.primaryAction()} />
      <span className="study-spacer" />
      {isFlowing && <IconButton symbol="pause.fill" help={tr("Pause without ending the stretch")} onClick={() => store.pause()} />}
      {/* The Timer has nothing to skip to; Stop ends it. */}
      {session.method.hasBreaks && <IconButton symbol="forward.end.fill" help={skipHelp} disabled={isFresh} onClick={() => store.skip()} />}
      <IconButton symbol="stop.fill" help={tr("Stop and keep the time studied so far")} disabled={isFresh} onClick={() => store.stop()} />
    </div>
  );
}
