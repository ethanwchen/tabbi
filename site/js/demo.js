// The home page's notch demo: hover or tap the notch and Tabbi's panel
// springs open, the Timer counts down a short focus round, and the pet
// cheers beside the closed notch when it is done.
//
// The page already holds the whole panel as HTML, open, with tabs that
// switch through radio buttons, so it works as a showcase without this
// file. This script closes it, opens it the way the app does and makes the
// controls work. It runs no strings as code, adds no markup but confetti,
// and talks to no server: the pet's frames come from a JSON data block.
(() => {
  'use strict';

  const demo = document.querySelector('.demo');
  const data = document.getElementById('demo-pets');
  if (!demo || !data) return;

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

  panel.addEventListener('change', (event) => {
    if (event.target.name === 'demo-tab') notch.dataset.tab = event.target.value;
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
  const arcs = demo.querySelectorAll('.ring-arc');
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

  demo.querySelectorAll('.demo button:disabled').forEach((button) => { button.disabled = false; });
  render();
  renderControls();
  setState('closed');
  delete demo.dataset.tried;
  demo.dataset.live = '';
})();
