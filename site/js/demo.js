// The home page's notch demo: hover or tap the notch and Tabbi's panel
// springs open, the Timer counts down a short focus round, and the pet
// cheers beside the closed notch when it is done. Today keeps a checklist
// for yesterday, today and tomorrow.
//
// The page already holds the whole panel as HTML, open, with tabs that
// switch through radio buttons, so it works as a showcase without this
// file. This script closes it, opens it the way the app does and makes the
// controls work. It runs no strings as code, builds markup only from the
// page's own templates and talks to no server: the pet's frames and the
// days' lists come from JSON data blocks.
(() => {
  'use strict';

  const demo = document.querySelector('.demo');
  const data = document.getElementById('demo-pets');
  const daysData = document.getElementById('demo-days');
  if (!demo || !data || !daysData) return;

  const notch = demo.querySelector('.notch');
  const face = notch.querySelector('.notch-face');
  const panel = notch.querySelector('.panel');
  const scene = demo.querySelector('.scene');
  const burst = demo.querySelector('.burst');
  const status = demo.querySelector('[data-status]');
  const pets = JSON.parse(data.textContent);
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const PET = 'Mochi';

  /** Says something to screen readers through the polite live region. */
  function announce(text) {
    status.textContent = '';
    // A fresh node each time, so the same words are read again.
    window.setTimeout(() => { status.textContent = text; }, 30);
  }

  // --- the pet ------------------------------------------------------------

  /** Plays one look's clips on a sprite element, frame by frame, with the
      durations the app's PetComposer gives them. Idle loops with a blink
      now and then; under reduced motion the pet holds a single frame. */
  class PetPlayer {
    constructor(el) {
      this.el = el;
      this.timer = 0;
      this.clip = 'idle';
    }

    get look() { return pets.looks[this.el.dataset.look]; }

    frame(row, col) {
      this.el.style.backgroundPosition = `${-col * pets.frame}px ${-row * pets.frame}px`;
    }

    /** Plays `name` once (or in a loop, if it loops), then calls `done`. */
    play(name, done) {
      window.clearTimeout(this.timer);
      this.clip = name;
      const clip = this.look.clips[name];
      if (reduceMotion.matches) {
        this.frame(clip.row, name === 'celebrate' ? clip.durations.length - 1 : 0);
        if (done) this.timer = window.setTimeout(done, 1600);
        return;
      }
      let i = 0;
      const step = () => {
        this.frame(clip.row, i);
        const wait = clip.durations[i];
        i += 1;
        if (i < clip.durations.length) {
          this.timer = window.setTimeout(step, wait);
        } else if (clip.loops && !done) {
          i = 0;
          this.timer = window.setTimeout(name === 'idle' ? () => this.idle() : step, wait);
        } else {
          this.timer = window.setTimeout(done || (() => this.idle()), wait);
        }
      };
      step();
    }

    /** Idle, with a blink every few loops. */
    idle() {
      if (this.clip === 'idle' && Math.random() < 0.4) {
        this.play('blink', () => this.play('idle'));
      } else {
        this.play('idle');
      }
    }

    stop() {
      window.clearTimeout(this.timer);
    }
  }

  const players = {};
  demo.querySelectorAll('[data-pet]').forEach((el) => { players[el.dataset.pet] = new PetPlayer(el); });
  const allPets = () => Object.values(players);

  // --- open and close -------------------------------------------------------

  let hoverTimer = 0;
  let leaveTimer = 0;

  function setState(next) {
    notch.dataset.state = next;
    const open = next === 'open';
    face.setAttribute('aria-expanded', String(open));
    panel.inert = !open;
    if (open) demo.dataset.tried = '';
  }

  const isOpen = () => notch.dataset.state === 'open';

  function open(focusTab) {
    window.clearTimeout(hoverTimer);
    window.clearTimeout(leaveTimer);
    setState('open');
    if (focusTab) panel.querySelector('input[name="demo-tab"]:checked').focus();
  }

  function close() {
    window.clearTimeout(hoverTimer);
    window.clearTimeout(leaveTimer);
    if (!isOpen() && notch.dataset.state !== 'hover') return;
    // Keep keyboard focus on the page: back to the notch it came from.
    const hadFocus = panel.contains(document.activeElement);
    setState('closed');
    if (hadFocus) face.focus();
  }

  // A pointer resting on the notch grows it a little, then opens it, like
  // the app with Open on hover. Leaving closes it after a short grace.
  notch.addEventListener('pointerenter', (event) => {
    if (event.pointerType !== 'mouse') return;
    window.clearTimeout(leaveTimer);
    if (isOpen()) return;
    notch.dataset.state = 'hover';
    hoverTimer = window.setTimeout(() => open(false), 140);
  });
  notch.addEventListener('pointerleave', (event) => {
    if (event.pointerType !== 'mouse') return;
    window.clearTimeout(hoverTimer);
    if (notch.dataset.state === 'hover') {
      setState('closed');
      return;
    }
    // Like the app, the panel stays open while someone types in it.
    if (document.activeElement === addField) return;
    leaveTimer = window.setTimeout(close, 220);
  });

  // A click or tap opens it; from the keyboard, focus moves into the tabs.
  face.addEventListener('click', (event) => open(event.detail === 0));

  // Tapping or clicking anywhere else closes it, and so does Escape.
  document.addEventListener('pointerdown', (event) => {
    if (isOpen() && !notch.contains(event.target)) close();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && isOpen()) {
      face.focus();
      close();
    }
  });
  notch.addEventListener('focusout', (event) => {
    if (isOpen() && event.relatedTarget && !notch.contains(event.relatedTarget)) close();
  });

  // --- the Timer ----------------------------------------------------------

  // A real Pomodoro is 25 minutes; the demo's round is 20 seconds.
  const ROUND = 20000;
  const POINTS = 35;
  const timer = {
    run: 'idle',
    left: ROUND,
    endsAt: 0,
    frame: 0,
    shown: '',
    announced: 0,
  };
  const times = demo.querySelectorAll('[data-time]');
  const arcs = demo.querySelectorAll('.pane-timer .ring-arc, .mini-ring .ring-arc');
  const focusArc = demo.querySelector('.focus-dial .ring-arc');
  const focusSub = demo.querySelector('[data-focus-sub]');
  const primary = demo.querySelector('[data-action="primary"]');
  const primaryLabel = primary.querySelector('[data-primary-label]');
  const primaryIcon = primary.querySelector('use');
  const stopButton = demo.querySelector('[data-action="stop"]');
  const dial = demo.querySelector('.dial');
  const done = demo.querySelector('[data-done]');
  const points = demo.querySelector('[data-points]');
  let earned = 84;

  const clock = (ms) => {
    const seconds = Math.ceil(ms / 1000);
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  };

  function render() {
    const text = clock(timer.left);
    if (text !== timer.shown) {
      timer.shown = text;
      times.forEach((el) => { el.textContent = text; });
    }
    // The arc is what is left of the round, like the app's dial.
    const offset = String(100 - (100 * timer.left) / ROUND);
    arcs.forEach((arc) => { arc.style.strokeDashoffset = offset; });
    // Today's focus card fills with the time done instead.
    focusArc.style.strokeDashoffset = String((100 * timer.left) / ROUND);
  }

  function renderControls() {
    const { run } = timer;
    const running = run === 'running';
    primaryLabel.textContent = running ? 'Pause' : run === 'paused' ? 'Resume' : 'Start';
    primaryIcon.setAttribute('href', running ? '#i-pause' : '#i-play');
    primary.title = running ? 'Pause the timer' : run === 'paused' ? 'Resume the timer' : 'Start studying';
    stopButton.disabled = run === 'idle';
    if (run === 'idle') delete notch.dataset.running;
    else notch.dataset.running = '';
    if (run === 'paused') notch.dataset.paused = '';
    else delete notch.dataset.paused;
    focusSub.textContent = run === 'idle' ? 'Opens the Timer tab' : run === 'paused' ? 'Paused in Timer' : 'Running in Timer';
    dial.title = `Focus: ${clock(timer.left)}`;
    players.dial.el.title = running ? `${PET} is studying with you` : `${PET} naps until the timer runs`;
  }

  function tick() {
    timer.left = Math.max(0, timer.endsAt - performance.now());
    render();
    const seconds = Math.ceil(timer.left / 1000);
    if (seconds === 10 && timer.announced !== 10) {
      timer.announced = 10;
      announce('10 seconds left.');
    }
    if (timer.left <= 0) {
      finish();
    } else {
      timer.frame = window.requestAnimationFrame(tick);
    }
  }

  function start() {
    const resuming = timer.run === 'paused';
    timer.run = 'running';
    timer.endsAt = performance.now() + timer.left;
    renderControls();
    players.dial.play('typing');
    announce(resuming ? `Resumed, ${clock(timer.left)} left.` : 'Focus round started: 20 seconds.');
    tick();
  }

  function pause() {
    window.cancelAnimationFrame(timer.frame);
    timer.left = Math.max(0, timer.endsAt - performance.now());
    timer.run = 'paused';
    renderControls();
    players.dial.idle();
    announce(`Paused with ${clock(timer.left)} left.`);
  }

  function reset() {
    window.cancelAnimationFrame(timer.frame);
    timer.run = 'idle';
    timer.left = ROUND;
    timer.announced = 0;
    render();
    renderControls();
    players.dial.idle();
  }

  function finish() {
    reset();
    done.textContent = String(Number(done.textContent) + 1);
    earned += POINTS;
    points.textContent = `+${earned} pts`;
    close();
    cheer();
    announce(`Round done. ${PET} cheers: plus ${POINTS} points.`);
  }

  primary.addEventListener('click', () => (timer.run === 'running' ? pause() : start()));
  stopButton.addEventListener('click', () => {
    // The stop button goes away under the pointer, so focus stays nearby.
    if (document.activeElement === stopButton) primary.focus();
    reset();
    announce('Stopped.');
  });

  const deep = demo.querySelector('[data-action="deep"]');
  deep.addEventListener('click', () => {
    const on = deep.getAttribute('aria-pressed') !== 'true';
    deep.setAttribute('aria-pressed', String(on));
    deep.title = on ? 'Deep focus is on: focus blocks bring Do Not Disturb. Click to turn it off'
      : 'Turn on deep focus: focus blocks bring Do Not Disturb';
  });

  // --- Today --------------------------------------------------------------

  // Yesterday, today and tomorrow, each a list of [title, done] and its
  // calendar. Yesterday is done with, so it only looks back.
  const days = JSON.parse(daysData.textContent);
  const ORDER = ['yesterday', 'today', 'tomorrow'];
  const taskList = demo.querySelector('[data-tasks]');
  const taskTemplate = demo.querySelector('[data-task]').content.firstElementChild;
  const eventList = demo.querySelector('[data-events]');
  const eventTemplate = demo.querySelector('[data-event]').content.firstElementChild;
  const addForm = demo.querySelector('[data-add]');
  const addField = addForm.querySelector('input');
  const dayFoot = demo.querySelector('[data-day-foot]');
  const dayName = demo.querySelector('[data-day-name]');
  const dayDate = demo.querySelector('[data-day-date]');
  const dayCount = demo.querySelector('[data-day-count]');
  const dayArc = demo.querySelector('.day-ring .ring-arc');
  const calTitle = demo.querySelector('[data-cal-title]');
  const [backStep, nextStep] = demo.querySelectorAll('[data-step]');
  let viewing = 'today';

  /** The day's date the way the app's header writes it: "Fri, Oct 9" for
      today, "Oct 8" beside the word Yesterday. */
  function dateText(offset) {
    const day = new Date();
    day.setDate(day.getDate() + offset);
    const options = offset === 0 ? { weekday: 'short', month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric' };
    return day.toLocaleDateString('en-US', options);
  }

  function taskRow(title, isDone) {
    const row = taskTemplate.cloneNode(true);
    const box = row.querySelector('input');
    row.querySelector('label').title = title;
    row.querySelector('.task-title').textContent = title;
    box.checked = isDone;
    if (viewing === 'yesterday') {
      box.disabled = true;
      // An unfinished task of yesterday's already sits on today's list.
      if (!isDone) {
        const note = document.createElement('span');
        note.className = 'task-note';
        note.textContent = 'On today';
        row.querySelector('label').append(note);
      }
    }
    return row;
  }

  /** "3 of 5 done", or for tomorrow, which has not started, "2 planned". */
  function renderCount() {
    const tasks = days[viewing].tasks;
    const finished = tasks.filter(([, isDone]) => isDone).length;
    dayCount.textContent = viewing === 'tomorrow' && finished === 0 ? `${tasks.length} planned` : `${finished} of ${tasks.length} done`;
    dayArc.style.strokeDashoffset = String(tasks.length ? 100 - (100 * finished) / tasks.length : 100);
  }

  function renderDay() {
    const index = ORDER.indexOf(viewing);
    const offset = index - 1;
    dayName.textContent = offset === 0 ? dateText(0) : viewing === 'yesterday' ? 'Yesterday' : 'Tomorrow';
    dayDate.textContent = offset === 0 ? '' : dateText(offset);
    taskList.replaceChildren(...days[viewing].tasks.map(([title, isDone]) => taskRow(title, isDone)));
    taskList.setAttribute('aria-label', `${viewing === 'today' ? "Today's" : viewing === 'yesterday' ? "Yesterday's" : "Tomorrow's"} tasks`);
    eventList.replaceChildren(...days[viewing].events.map(([title, start, length, color]) => {
      const row = eventTemplate.cloneNode(true);
      row.querySelector('.dot').className = `dot dot-${color}`;
      row.querySelector('.event-title').textContent = title;
      const time = row.querySelector('.event-time');
      const span = time.querySelector('span');
      span.textContent = length;
      time.replaceChildren(start, span);
      return row;
    }));
    calTitle.textContent = { yesterday: "Yesterday's calendar", today: 'Up next', tomorrow: "Tomorrow's calendar" }[viewing];
    addForm.hidden = viewing === 'yesterday';
    dayFoot.hidden = viewing !== 'yesterday';
    addField.placeholder = viewing === 'tomorrow' ? 'Add a task for tomorrow…' : 'Add a task…';
    addField.setAttribute('aria-label', viewing === 'tomorrow' ? 'Add a task for tomorrow' : 'Add a task');
    // An arrow with nowhere to go stays in place, dimmed, so the title never shifts.
    backStep.disabled = index === 0;
    nextStep.disabled = index === ORDER.length - 1;
    backStep.title = viewing === 'tomorrow' ? 'Back to today' : "Show yesterday's list";
    nextStep.title = viewing === 'yesterday' ? 'Back to today' : 'Plan tomorrow';
    [backStep, nextStep].forEach((button) => button.setAttribute('aria-label', button.title));
    renderCount();
  }

  [backStep, nextStep].forEach((button) => {
    button.addEventListener('click', () => {
      viewing = ORDER[ORDER.indexOf(viewing) + Number(button.dataset.step)];
      renderDay();
      // The arrow at the end goes dim; keep focus on the one that can go back.
      if (button.disabled) (button === backStep ? nextStep : backStep).focus();
      announce(viewing === 'today' ? `Today, ${dayCount.textContent}.` : `${dayName.textContent}, ${dayCount.textContent}.`);
    });
  });

  taskList.addEventListener('change', (event) => {
    const rows = [...taskList.children];
    const index = rows.indexOf(event.target.closest('.task'));
    if (index < 0) return;
    days[viewing].tasks[index][1] = event.target.checked;
    renderCount();
  });

  addForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const title = addField.value.trim();
    if (!title) return;
    days[viewing].tasks.push([title, false]);
    const row = taskRow(title, false);
    taskList.append(row);
    row.scrollIntoView({ block: 'nearest' });
    addField.value = '';
    renderCount();
    announce(`Added ${title}.`);
  });

  // Esc clears the draft first; on an empty field it closes the notch.
  addField.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && addField.value) {
      event.stopPropagation();
      addField.value = '';
    }
  });

  // The focus card mirrors the Timer and opens its tab.
  const timerTab = demo.querySelector('input[name="demo-tab"][value="timer"]');
  demo.querySelector('[data-action="open-timer"]').addEventListener('click', () => {
    timerTab.checked = true;
    timerTab.focus();
  });

  // --- the celebration ------------------------------------------------------

  const CONFETTI = ['#FF9E42', '#F4D57E', '#F2A0A6', '#A88CFF', '#7FD6C2', '#FBF7F0'];
  let cheerTimer = 0;

  /** The pet's cheer dance in the closed notch, confetti beside it and
      the points it earned. Reduced motion keeps the points and drops the
      confetti and the dance. */
  function cheer() {
    window.clearTimeout(cheerTimer);
    burst.querySelectorAll('.confetti').forEach((piece) => piece.remove());
    delete demo.dataset.cheer;
    // Restart the points' entrance even if the last cheer is still showing.
    void burst.offsetWidth;
    demo.dataset.cheer = '';
    const pet = players.notch;
    pet.play('celebrate', () => pet.play('celebrate', () => pet.idle()));
    if (!reduceMotion.matches) {
      for (let i = 0; i < 22; i += 1) {
        const piece = document.createElement('span');
        piece.className = 'confetti';
        const angle = (Math.PI * (0.15 + 1.7 * Math.random())) - Math.PI * 0.9;
        const reach = 50 + Math.random() * 70;
        piece.style.setProperty('--dx', `${Math.cos(angle) * reach}px`);
        piece.style.setProperty('--dy', `${Math.abs(Math.sin(angle)) * reach + 30}px`);
        piece.style.setProperty('--spin', `${Math.round(Math.random() * 720 - 360)}deg`);
        piece.style.setProperty('--delay', `${Math.round(Math.random() * 120)}ms`);
        piece.style.background = CONFETTI[i % CONFETTI.length];
        burst.append(piece);
      }
    }
    cheerTimer = window.setTimeout(() => {
      delete demo.dataset.cheer;
      burst.querySelectorAll('.confetti').forEach((piece) => piece.remove());
    }, 2800);
  }

  // --- start ---------------------------------------------------------------

  // Pets only move while the demo is on screen.
  const watcher = new IntersectionObserver(([entry]) => {
    allPets().forEach((pet) => {
      if (!entry.isIntersecting) pet.stop();
      else if (pet === players.dial && timer.run === 'running') pet.play('typing');
      else pet.idle();
    });
  });
  watcher.observe(scene);

  demo.querySelectorAll('button:disabled, input:disabled').forEach((control) => { control.disabled = false; });
  renderDay();
  render();
  renderControls();
  setState('closed');
  delete demo.dataset.tried;
  demo.dataset.live = '';
})();
