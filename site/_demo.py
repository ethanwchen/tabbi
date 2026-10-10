"""The home page's interactive notch demo: its markup and the pet data block.

The page carries the whole panel as HTML, so without JavaScript it is still a
showcase: the panel stands open and its tabs switch with radio buttons and
CSS alone. js/demo.js then closes it, opens it on hover or tap, and makes the
controls work. Sizes in demo.css are in em, where 1em is 10 of the app's
points, so the panel keeps the app's proportions at any scale.
"""

import json
import pathlib

from _partials import download_button

HERE = pathlib.Path(__file__).parent

# The icons the panel draws, as symbols each control <use>s. They are drawn
# for this page on a 24 unit grid, in the spirit of the app's symbols.
ICONS = {
    'timer': '<g fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="13.5" r="7.8"/><path d="M12 13.5l3.2-3.2M9.6 2.8h4.8"/></g>',
    'play': '<path fill="currentColor" d="M8.2 4.9c-.8-.5-1.8.1-1.8 1v12.2c0 .9 1 1.5 1.8 1l9.8-6.1c.7-.5.7-1.5 0-2z"/>',
    'pause': '<g fill="currentColor"><rect x="6.2" y="5" width="4" height="14" rx="1.3"/><rect x="13.8" y="5" width="4" height="14" rx="1.3"/></g>',
    'stop': '<rect fill="currentColor" x="6" y="6" width="12" height="12" rx="2.4"/>',
    'moon': '<path fill="currentColor" d="M14.6 3.2a8.8 8.8 0 1 0 6.2 12.4A7.4 7.4 0 0 1 14.6 3.2z"/>',
    'star': '<path fill="currentColor" d="M12 2.8l2.7 5.6 6.1.8-4.5 4.3 1.1 6.1L12 16.7l-5.4 2.9 1.1-6.1-4.5-4.3 6.1-.8z"/>',
    'clock': '<g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.6"/><path d="M12 7.4V12l3 1.8"/></g>',
    'done': '<g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.6"/><path d="M8.3 12.2l2.5 2.5 4.9-5"/></g>',
    'checklist': '<g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.6" cy="6.4" r="2.9"/><path d="M4.4 6.5l1 1 1.6-1.8M11.6 6.4h9.2M11.6 17.6h9.2"/><circle cx="5.6" cy="17.6" r="2.9"/></g>',
    'chev-l': '<path fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" d="M14.5 5.5L8 12l6.5 6.5"/>',
    'chev-r': '<path fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" d="M9.5 5.5L16 12l-6.5 6.5"/>',
    'plus': '<path fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" d="M12 5v14M5 12h14"/>',
    'check-fill': '<path fill="currentColor" fill-rule="evenodd" d="M12 2.4a9.6 9.6 0 1 1 0 19.2 9.6 9.6 0 0 1 0-19.2zm4.2 6.3a1.2 1.2 0 0 0-1.7.1l-3.6 4.1-1.5-1.5a1.2 1.2 0 1 0-1.7 1.7l2.4 2.4a1.2 1.2 0 0 0 1.7-.1l4.5-5a1.2 1.2 0 0 0-.1-1.7z"/>',
    'updown': '<path fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>',
}

SPRITE = ('<svg class="demo-icons" aria-hidden="true">'
          + ''.join(f'<symbol id="i-{name}" viewBox="0 0 24 24">{body}</symbol>' for name, body in ICONS.items())
          + '</svg>')


def icon(name, cls='ico'):
    return f'<svg class="{cls}" aria-hidden="true"><use href="#i-{name}"/></svg>'


# The ring's arc is drawn with pathLength 100, so demo.js sets how much of it
# shows as a plain percentage of time left.
def ring(cls, size, stroke):
    r = (size - stroke) / 2
    c = size / 2
    return (f'<svg class="{cls}" viewBox="0 0 {size} {size}" aria-hidden="true">'
            f'<circle class="ring-track" cx="{c:g}" cy="{c:g}" r="{r:g}" stroke-width="{stroke}"/>'
            f'<circle class="ring-arc" cx="{c:g}" cy="{c:g}" r="{r:g}" stroke-width="{stroke}" pathLength="100"/></svg>')


TIMER_PANE = f'''
              <div class="pane pane-timer" data-pane="timer">
                <div class="n-card dial" title="Focus: 0:20">
                  <div class="dial-ring">
                    {ring('ring', 128, 6)}
                    <p class="dial-read"><span class="dial-time" data-time>0:20</span><span class="dial-cap">Focus</span></p>
                  </div>
                  <span class="pet pet-corner" data-pet="dial" data-look="plain" title="Mochi naps until the timer runs"></span>
                </div>
                <div class="timer-side">
                  <div class="n-card method">
                    <p class="cap-row"><span>Method</span><span>Round 1 of 4</span></p>
                    <p class="method-name">Pomodoro <span class="accent">25/5</span>{icon('updown', 'ico updown')}</p>
                    <p class="method-tag">Shortened to 20 seconds for this demo</p>
                    <p class="deep-row">
                      <button type="button" class="capsule" data-action="deep" aria-pressed="true" title="Deep focus is on: focus blocks bring Do Not Disturb. Click to turn it off" disabled>{icon('moon')}<span>Deep focus</span></button>
                    </p>
                    <p class="today-row">
                      <span class="today-label">Today</span>
                      <span title="Focus time today, out of your daily goal">{icon('clock')}1h 4m of 2h</span>
                      <span title="Focus blocks finished today">{icon('done')}<span data-done>3</span> done</span>
                      <span class="pts" title="Points earned today; spend them on your pet's wardrobe">{icon('star')}<span data-points>+84 pts</span></span>
                    </p>
                  </div>
                  <div class="controls">
                    <button type="button" class="primary" data-action="primary" title="Start studying" disabled>{icon('play')}<span data-primary-label>Start</span></button>
                    <button type="button" class="icon-btn" data-action="stop" title="Stop and keep the time studied so far" aria-label="Stop" disabled>{icon('stop')}</button>
                  </div>
                </div>
              </div>'''

# Today's three days and their calendars, all made up. The page draws
# today's from here, and demo.js gets all three as a data block, so it
# steps to yesterday and tomorrow without a second copy of the lists.
DAYS = {
    'yesterday': {
        'tasks': [['Read chapter 3 of the novel', True], ['Finish the lab report', False],
                  ['Water the plants', True], ['Email the study group', True]],
        'events': [['Morning lecture', '9:30', '1h', 'blue'], ['Lunch with Maya', '12:30', '1h', 'orange'],
                   ['Lab session', '3:00', '2h', 'blue']],
    },
    'today': {
        'tasks': [['Review flashcards', True], ['Finish the lab report', False], ['Go for a short walk', True],
                  ['Call grandma', False], ['Plan the weekend hike', False]],
        'events': [['Study group', '4:00', '1h', 'blue'], ['Yoga class', '6:30', '45 min', 'orange'],
                   ['Movie night', '8:30', '2h', 'blue']],
    },
    'tomorrow': {
        'tasks': [['Pick up the library books', False], ['Sketch the poster draft', False]],
        'events': [['Library hour', '10:00', '1h', 'blue'], ['Poster review', '2:00', '30 min', 'orange'],
                   ['Dinner with friends', '7:00', '2h', 'blue']],
    },
}

# The app's CheckGlyph on a 16 pt box: a ring, an accent fill that pops in
# and a check that draws on from its short leg (pathLength 1, so demo.css
# draws it with one dash offset).
CHECK = ('<svg class="check" viewBox="0 0 16 16" aria-hidden="true">'
         '<circle class="check-ring" cx="8" cy="8" r="7.25"/><circle class="check-fill" cx="8" cy="8" r="8"/>'
         '<path class="check-mark" pathLength="1" d="M4.64 8.32 7.04 10.72 11.52 5.76"/></svg>')


def task(title, done):
    return (f'<li class="task"><label class="task-label" title="{title}"><input type="checkbox"{" checked" if done else ""}>'
            f'{CHECK}<span class="task-title">{title}</span></label></li>')


def event(title, start, length, color):
    return (f'<li class="event"><span class="dot dot-{color}"></span>'
            f'<span class="event-title">{title}</span><span class="event-time">{start}<span>{length}</span></span></li>')


TODAY = DAYS['today']
TODAY_DONE = sum(done for _, done in TODAY['tasks'])

# Without the script the checkboxes still check (they are real ones), the
# day reads "Today" and the arrows and the add field wait, disabled.
TODAY_PANE = f'''
              <div class="pane pane-today" data-pane="today">
                <div class="today-main">
                  <div class="day-head">
                    {ring('day-ring', 16, 1.5)}
                    <div class="day-stepper">
                      <button type="button" class="day-step" data-step="-1" title="Show yesterday's list" aria-label="Show yesterday's list" disabled>{icon('chev-l')}</button>
                      <p class="day-title"><span data-day-name>Today</span><span class="day-date" data-day-date></span></p>
                      <button type="button" class="day-step" data-step="1" title="Plan tomorrow" aria-label="Plan tomorrow" disabled>{icon('chev-r')}</button>
                    </div>
                    <span class="day-count" data-day-count>{TODAY_DONE} of {len(TODAY['tasks'])} done</span>
                  </div>
                  <ul class="tasks" data-tasks aria-label="Tasks">{''.join(task(t, d) for t, d in TODAY['tasks'])}</ul>
                  <form class="add-task" data-add>
                    {icon('plus')}<input type="text" name="task" maxlength="48" autocomplete="off" placeholder="Add a task…" aria-label="Add a task" title="Type a task and press Return to add it; Esc clears" disabled>
                  </form>
                  <p class="day-foot" data-day-foot hidden>{icon('check-fill')}<span>Everything unfinished is on today</span></p>
                  <template data-task>{task('', False)}</template>
                </div>
                <div class="today-side">
                  <div class="n-card upnext">
                    <p class="upnext-cap" data-cal-title>Up next</p>
                    <ul class="events" data-events>{''.join(event(*e) for e in TODAY['events'])}</ul>
                    <template data-event>{event('', '', '', 'blue')}</template>
                  </div>
                  <button type="button" class="n-card focus-card" data-action="open-timer" title="Open Timer to start, pause or stop" disabled>
                    <span class="focus-ring">{ring('focus-dial', 28, 2.5)}{icon('timer')}</span>
                    <span class="focus-text">
                      <span class="focus-top"><span class="focus-idle">Start a timer</span><span class="focus-time" data-time>0:20</span><span class="focus-cap">Focus</span></span>
                      <span class="focus-sub" data-focus-sub>Opens the Timer tab</span>
                    </span>
                  </button>
                </div>
              </div>'''

# (id, title, icon). The tab bar left of the camera, like the app's.
TABS = [
    ('timer', 'Timer', 'timer'),
    ('today', 'Today', 'checklist'),
]


def tab(tab_id, title, symbol, checked):
    return (f'<label class="tab tab-{tab_id}" title="{title}">'
            f'<input type="radio" name="demo-tab" value="{tab_id}" aria-label="{title}"{" checked" if checked else ""}>'
            f'{icon(symbol)}</label>')


DEMO = f'''
      <section class="demo" aria-labelledby="demo-title">
        <h2 id="demo-title" class="sr-only">Try Tabbi right here</h2>
        {SPRITE}
        <div class="scene">
          <div class="notch" data-state="open">
            <button type="button" class="notch-face" aria-expanded="true" aria-controls="demo-panel" aria-label="Open Tabbi">
              <span class="wing wing-l">
                <span class="pet" data-pet="notch" data-look="plain"></span>
                {ring('mini-ring', 20, 3)}
              </span>
              <span class="wing wing-r"><span class="mini-time" data-time>0:20</span></span>
            </button>
            <div class="panel" id="demo-panel" role="group" aria-label="Tabbi panel">
             <div class="panel-inner">
              <div class="panel-head">
                <div class="tab-bar" role="radiogroup" aria-label="Tabs">
                  {''.join(tab(t, title, symbol, i == 0) for i, (t, title, symbol) in enumerate(TABS))}
                </div>
                <p class="head-title"><span class="title-timer">Timer</span><span class="title-today">Today</span></p>
              </div>
{TIMER_PANE}
{TODAY_PANE}
             </div>
            </div>
          </div>
          <p class="hint" aria-hidden="true"><svg viewBox="0 0 40 32" width="40" height="32"><path d="M36 28C24 28 12 22 7 6m0 0L3 13m4-7 6 5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>Psst... try it</p>
          <p class="burst" aria-hidden="true"><span class="burst-pts">+35 pts</span></p>
        </div>
        <p class="sr-only" aria-live="polite" data-status></p>
        <div class="cta">{download_button()}</div>
        <p class="cta-note">No account. macOS 14 or later.</p>
      </section>
'''


def data_block(block_id, data):
    text = json.dumps(data, separators=(',', ':')).replace('<', '\\u003c')
    return f'\n  <script type="application/json" id="{block_id}">{text}</script>'


def demo_data():
    """pets.json and Today's days, minified, as data blocks for demo.js. The
    CSP lets the page load nothing but its own files, and a data block is
    never run, so they ride along in the page instead of a fetch the CSP
    would stop."""
    pets = json.loads((HERE / 'img' / 'demo' / 'pets.json').read_text())
    return data_block('demo-pets', pets) + data_block('demo-days', DAYS)
