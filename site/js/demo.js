// The home page's notch demo: hover or tap the notch and Tabbi's panel
// springs open, the Timer counts down a short focus round, and the pet
// cheers beside the closed notch when it is done. Today keeps a checklist
// for yesterday, today and tomorrow, Now Playing plays made-up songs
// (silently), and the Closet dresses the pet.
//
// The page already holds the whole panel as HTML, open, with tabs that
// switch through radio buttons, so it works as a showcase without this
// file. This script closes it, opens it the way the app does and makes the
// controls work. It runs no strings as code, builds markup only from the
// page's own templates and talks to no server: the pet's frames, the
// days' lists and the songs come from JSON data blocks.
(() => {
  'use strict';

  const demo = document.querySelector('.demo');
  const data = document.getElementById('demo-pets');
  const daysData = document.getElementById('demo-days');
  const tracksData = document.getElementById('demo-tracks');
  if (!demo || !data || !daysData || !tracksData) return;

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
    roundFinished();
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

  // --- the Closet -----------------------------------------------------------

  // Every tile tries its item on the big pet: hover or focus it, or tap it
  // on a phone. An owned item wears for real on click, in the notch and on
  // the Timer too, and a click on the worn one takes it off. Points from
  // the Timer can unlock the wardrobe, and the demo's limited cap is earned
  // by finishing a round.
  const closetPet = players.closet;
  const petSub = demo.querySelector('[data-pet-sub]');
  const tiles = [...demo.querySelectorAll('.tile')];
  const balanceText = demo.querySelector('[data-balance]');
  const toGo = demo.querySelector('[data-to-go]');
  const nextName = toGo.previousElementSibling;
  const earnedText = demo.querySelector('[data-earned]');
  const feet = {};
  demo.querySelectorAll('[data-foot]').forEach((foot) => { feet[foot.dataset.foot] = { el: foot, rest: [...foot.childNodes] }; });
  let balance = Number(balanceText.textContent);
  let worn = 'plain';
  let trying = null;

  /** Restarts a pet's clip in its new look. */
  function restyle(pet, look) {
    if (pet.el.dataset.look === look) return;
    pet.el.dataset.look = look;
    if (pet === players.dial && timer.run === 'running') pet.play('typing');
    else pet.idle();
  }

  function renderCloset() {
    const shown = trying || tiles.find((tile) => tile.dataset.look === worn);
    restyle(closetPet, shown ? shown.dataset.look : 'plain');
    restyle(players.notch, worn);
    restyle(players.dial, worn);
    if (trying) petSub.dataset.trying = '';
    else delete petSub.dataset.trying;
    petSub.textContent = trying ? `Trying on ${trying.dataset.name}` : 'British Shorthair';
    tiles.forEach((tile) => {
      const pressed = tile === trying || ('owned' in tile.dataset && tile.dataset.look === worn);
      tile.setAttribute('aria-pressed', String(pressed));
    });
    // The footer names the item tried on, or points to the next unlock.
    Object.entries(feet).forEach(([section, foot]) => {
      if (trying && trying.closest(`.sec-${section}`)) {
        const name = document.createElement('b');
        name.textContent = trying.dataset.name;
        const detail = document.createElement('span');
        detail.textContent = trying.dataset.detail;
        foot.el.replaceChildren(name, detail);
      } else {
        foot.el.replaceChildren(...foot.rest);
      }
    });
    balanceText.textContent = String(balance);
    const next = tiles.filter((tile) => tile.dataset.cost && !('owned' in tile.dataset))
      .sort((a, b) => a.dataset.cost - b.dataset.cost)[0];
    if (next) {
      nextName.textContent = next.dataset.name;
      const missing = next.dataset.cost - balance;
      toGo.textContent = missing > 0 ? `${missing} pts to go` : 'ready to unlock';
    } else {
      feet.wardrobe.rest = [document.createTextNode('Everything unlocked. Dress up as you like.')];
      if (!trying) feet.wardrobe.el.replaceChildren(...feet.wardrobe.rest);
    }
    const limited = tiles.filter((tile) => tile.classList.contains('tile-limited'));
    earnedText.textContent = `${limited.filter((tile) => 'owned' in tile.dataset).length} of ${limited.length} earned`;
  }

  function own(tile, detail) {
    tile.dataset.owned = '';
    tile.dataset.detail = detail;
    tile.title = `${tile.dataset.name}: ${detail}. Click to wear it`;
  }

  function tryOn(tile) {
    if (trying === tile) return;
    trying = tile;
    renderCloset();
  }

  tiles.forEach((tile) => {
    tile.addEventListener('pointerenter', (event) => { if (event.pointerType === 'mouse') tryOn(tile); });
    tile.addEventListener('focus', () => tryOn(tile));
    tile.addEventListener('click', () => {
      const { name, look, cost } = tile.dataset;
      if (!('owned' in tile.dataset) && cost && balance >= Number(cost)) {
        balance -= Number(cost);
        own(tile, 'Owned');
      }
      if ('owned' in tile.dataset) {
        const wearing = worn !== look;
        worn = wearing ? look : 'plain';
        trying = null;
        renderCloset();
        if (wearing) closetPet.play('celebrate');
        announce(wearing ? `${PET} wears the ${name}.` : `Took off the ${name}.`);
      } else {
        trying = tile;
        renderCloset();
        announce(`Trying on the ${name}: ${tile.dataset.detail}.`);
      }
    });
  });
  // Leaving the tiles, by pointer or by keyboard, ends the try-on.
  demo.querySelectorAll('.tiles').forEach((grid) => {
    grid.addEventListener('pointerleave', (event) => { if (event.pointerType === 'mouse') tryOn(null); });
    grid.addEventListener('focusout', (event) => { if (!grid.contains(event.relatedTarget)) tryOn(null); });
  });
  demo.querySelectorAll('input[name="closet-sec"]').forEach((section) => {
    section.addEventListener('change', () => tryOn(null));
  });

  /** A finished round pays its points and earns the limited cap. */
  function roundFinished() {
    balance += POINTS;
    const cap = tiles.find((tile) => tile.dataset.look === 'cap' && !('owned' in tile.dataset));
    if (cap) own(cap, 'Earned in the Timer');
    renderCloset();
  }

  // --- Now Playing ---------------------------------------------------------

  // A pretend player: play and pause, skip back and forward through four
  // made-up songs, like, shuffle, repeat and seek. Nothing makes a sound;
  // the song's time moves on a half-second tick while it plays, and the
  // closed notch shows the equalizer then.
  const tracks = JSON.parse(tracksData.textContent);
  const music = { index: 0, at: 0, playing: false, timer: 0, last: 0, shuffle: false, repeat: false };
  const cover = demo.querySelector('[data-cover]');
  const trackText = demo.querySelector('[data-track-text]');
  const trackTitle = demo.querySelector('[data-track-title]');
  const trackSub = demo.querySelector('[data-track-sub]');
  const trackAt = demo.querySelector('[data-track-at]');
  const trackLeft = demo.querySelector('[data-track-left]');
  const scrub = demo.querySelector('[data-scrub]');
  const like = demo.querySelector('[data-action="like"]');
  const playButton = demo.querySelector('[data-action="play"]');
  const playIcon = playButton.querySelector('use');
  const shuffleButton = demo.querySelector('[data-action="shuffle"]');
  const repeatButton = demo.querySelector('[data-action="repeat"]');
  music.at = Number(scrub.value);

  const mmss = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
  const song = () => tracks[music.index];
  const byLine = (track) => `${track.artist} \u00b7 ${track.album}`;

  function renderPosition() {
    const { length } = song();
    const at = Math.floor(music.at);
    scrub.value = String(at);
    scrub.style.setProperty('--f', String(music.at / length));
    trackAt.textContent = mmss(at);
    trackLeft.textContent = `-${mmss(length - at)}`;
    scrub.setAttribute('aria-valuetext', `${mmss(at)} of ${mmss(length)}`);
  }

  function renderSong() {
    const track = song();
    cover.style.setProperty('--h1', String(track.hues[0]));
    cover.style.setProperty('--h2', String(track.hues[1]));
    trackTitle.textContent = track.title;
    trackSub.textContent = byLine(track);
    trackText.title = `${track.title}\n${byLine(track)}`;
    like.setAttribute('aria-pressed', String(track.liked));
    like.title = track.liked ? 'Unlike' : 'Like';
    scrub.max = String(track.length);
    renderPosition();
  }

  function renderPlaying() {
    const { playing } = music;
    playIcon.setAttribute('href', playing ? '#i-pause' : '#i-play');
    playButton.setAttribute('aria-label', playing ? 'Pause' : 'Play');
    playButton.title = playing ? 'Pause' : 'Play';
    if (playing) notch.dataset.music = '';
    else delete notch.dataset.music;
  }

  function tickSong() {
    const now = performance.now();
    music.at += (now - music.last) / 1000;
    music.last = now;
    if (music.at >= song().length) {
      if (music.repeat) {
        music.at = 0;
      } else {
        skip(1, false);
        return;
      }
    }
    renderPosition();
  }

  function setPlaying(playing) {
    window.clearInterval(music.timer);
    music.playing = playing;
    if (playing) {
      music.last = performance.now();
      music.timer = window.setInterval(tickSong, 500);
    }
    renderPlaying();
  }

  /** The next or previous song; shuffle picks any other one. Going back
      past the first seconds restarts the song first, like a player does. */
  function skip(step, speak) {
    if (step < 0 && music.at >= 3) {
      music.at = 0;
      renderPosition();
      return;
    }
    if (music.shuffle && step > 0) {
      music.index = (music.index + 1 + Math.floor(Math.random() * (tracks.length - 1))) % tracks.length;
    } else {
      music.index = (music.index + step + tracks.length) % tracks.length;
    }
    music.at = 0;
    music.last = performance.now();
    renderSong();
    if (speak) announce(`${song().title} by ${song().artist}.`);
  }

  playButton.addEventListener('click', () => {
    setPlaying(!music.playing);
    announce(music.playing ? `Playing ${song().title} by ${song().artist}.` : 'Paused.');
  });
  demo.querySelector('[data-action="prev"]').addEventListener('click', () => skip(-1, true));
  demo.querySelector('[data-action="next"]').addEventListener('click', () => skip(1, true));
  like.addEventListener('click', () => {
    const track = song();
    track.liked = !track.liked;
    renderSong();
    announce(track.liked ? `Liked ${track.title}.` : `Removed the like from ${track.title}.`);
  });
  scrub.addEventListener('input', () => {
    music.at = Number(scrub.value);
    music.last = performance.now();
    renderPosition();
  });
  [[shuffleButton, 'shuffle', 'Turn shuffle off', 'Turn shuffle on'],
    [repeatButton, 'repeat', 'Turn repeat off', 'Repeat this song']].forEach(([button, key, onTitle, offTitle]) => {
    button.addEventListener('click', () => {
      music[key] = !music[key];
      button.setAttribute('aria-pressed', String(music[key]));
      button.title = music[key] ? onTitle : offTitle;
    });
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
  renderSong();
  renderPlaying();
  renderCloset();
  render();
  renderControls();
  setState('closed');
  delete demo.dataset.tried;
  demo.dataset.live = '';
})();
