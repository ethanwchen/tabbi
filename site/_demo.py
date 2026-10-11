"""The home page's interactive notch demo: its markup and the pet data block.

The page carries the whole panel as HTML, so without JavaScript it is still a
showcase: the panel stands open and its tabs switch with radio buttons and
CSS alone. js/demo.js then closes it, opens it on hover or tap, and makes the
controls work. Sizes in demo.css are in em, where 1em is 10 of the app's
points, so the panel keeps the app's proportions at any scale.
"""

import json
import pathlib


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
    'paw': '<g fill="currentColor"><ellipse cx="12" cy="16.4" rx="5" ry="4.2"/><ellipse cx="5.4" cy="10.6" rx="2.2" ry="2.8"/><ellipse cx="9.4" cy="6.2" rx="2.2" ry="2.9"/><ellipse cx="14.6" cy="6.2" rx="2.2" ry="2.9"/><ellipse cx="18.6" cy="10.6" rx="2.2" ry="2.8"/></g>',
    'shirt': '<path fill="currentColor" d="M8.6 3.4c.9 1.3 2 2 3.4 2s2.5-.7 3.4-2l5.5 2.5c.6.3.9 1 .6 1.6l-1.6 3.4c-.3.6-1 .8-1.6.5l-.8-.4v8.9c0 .7-.5 1.2-1.2 1.2H7.7c-.7 0-1.2-.5-1.2-1.2V11l-.8.4c-.6.3-1.3.1-1.6-.5L2.5 7.5c-.3-.6 0-1.3.6-1.6z"/>',
    'sparkles': '<path fill="currentColor" d="M10 3.5l1.7 4.8 4.8 1.7-4.8 1.7L10 16.5l-1.7-4.8L3.5 10l4.8-1.7zM17.6 13.4l.9 2.3 2.3.9-2.3.9-.9 2.3-.9-2.3-2.3-.9 2.3-.9z"/>',
    'lock': '<path fill="currentColor" fill-rule="evenodd" d="M12 2.8a5 5 0 0 1 5 5v2.4h.6c1 0 1.8.8 1.8 1.8v7.4c0 1-.8 1.8-1.8 1.8H6.4c-1 0-1.8-.8-1.8-1.8V12c0-1 .8-1.8 1.8-1.8H7V7.8a5 5 0 0 1 5-5zm0 2.6a2.4 2.4 0 0 0-2.4 2.4v2.4h4.8V7.8A2.4 2.4 0 0 0 12 5.4z"/>',
    'check': '<path fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" d="M5.5 12.5l4.2 4.2 8.8-9.4"/>',
    'note': '<path fill="currentColor" d="M18.6 3.1c.6-.1 1.1.3 1.1.9v3.3c0 .5-.3.9-.8 1l-6.9 1.4v8.1c0 2-1.7 3.3-3.6 3.3-1.8 0-3.1-1.1-3.1-2.6 0-1.7 1.5-2.9 3.5-2.9.6 0 1.1.1 1.5.3V5.5c0-.5.3-.9.8-1z"/>',
    'heart': '<path stroke="currentColor" stroke-width="2.2" stroke-linejoin="round" d="M12 20.2S3.4 15 3.4 9a4.6 4.6 0 0 1 8.6-2.3A4.6 4.6 0 0 1 20.6 9c0 6-8.6 11.2-8.6 11.2z"/>',
    'back': '<path fill="currentColor" d="M11.4 6.7c0-.8-.9-1.3-1.6-.8L2.9 11.2c-.6.4-.6 1.2 0 1.6l6.9 5.3c.7.5 1.6 0 1.6-.8zm10 0c0-.8-.9-1.3-1.6-.8l-6.9 5.3c-.6.4-.6 1.2 0 1.6l6.9 5.3c.7.5 1.6 0 1.6-.8z"/>',
    'forward': '<path fill="currentColor" d="M12.6 6.7c0-.8.9-1.3 1.6-.8l6.9 5.3c.6.4.6 1.2 0 1.6l-6.9 5.3c-.7.5-1.6 0-1.6-.8zm-10 0c0-.8.9-1.3 1.6-.8l6.9 5.3c.6.4.6 1.2 0 1.6l-6.9 5.3c-.7.5-1.6 0-1.6-.8z"/>',
    'shuffle': '<path fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" d="M3 7h3.4c2 0 3.2.9 4.3 2.6l2.6 4.8c1 1.7 2.3 2.6 4.3 2.6H21M3 17h3.4c1.6 0 2.7-.6 3.6-1.7M14 8.7c.9-1.1 2-1.7 3.6-1.7H21M18.4 4.4 21 7l-2.6 2.6M18.4 14.4 21 17l-2.6 2.6"/>',
    'repeat': '<path fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" d="M4 11.4V10a3 3 0 0 1 3-3h13M17.4 4.4 20 7l-2.6 2.6M20 12.6V14a3 3 0 0 1-3 3H4M6.6 19.6 4 17l2.6-2.6"/>',
    'party': '<g fill="currentColor"><circle cx="12" cy="7.4" r="3.2"/><circle cx="5.2" cy="9" r="2.4"/><circle cx="18.8" cy="9" r="2.4"/><path d="M6.6 19.2c0-3.4 2.4-6 5.4-6s5.4 2.6 5.4 6c0 .6-.4 1-1 1H7.6c-.6 0-1-.4-1-1z"/><path d="M5 19.8H2.6c-.6 0-1-.4-1-1 0-2.6 1.6-4.6 3.6-4.6.6 0 1.1.1 1.6.4A7.8 7.8 0 0 0 5 19.8zM19 19.8h2.4c.6 0 1-.4 1-1 0-2.6-1.6-4.6-3.6-4.6-.6 0-1.1.1-1.6.4.9 1.4 1.6 3.2 1.8 5.2z"/></g>',
    'gauge': '<g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="12" r="8.8"/><path d="M12 12l3.6-3.8"/><path d="M7.4 14.6h.01M6.8 11h.01M8.6 7.8h.01M12 6.6h.01" stroke-width="2.6"/></g>',
    'cards': '<g fill="currentColor"><rect x="7" y="2.6" width="10" height="2" rx="1"/><rect x="5" y="5.8" width="14" height="2.2" rx="1.1"/><rect x="3.4" y="9.2" width="17.2" height="12.2" rx="3"/></g>',
    'refresh': '<g fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M19.4 12a7.4 7.4 0 1 1-2.2-5.3"/><path d="M18 3.2v4.2h-4.2"/></g>',
    'flame': '<path fill="currentColor" d="M12.6 2.6c.4 3-1.6 4.6-3.2 6.6-1.4 1.7-2.6 3.6-2.6 6.1A5.2 5.2 0 0 0 12 20.6a5.2 5.2 0 0 0 5.2-5.3c0-2.2-1-3.6-2-4.8-.2 1.3-.9 2.3-1.9 2.6.6-3.6-.2-7.6-.7-10.5z"/>',
    'crown': '<path fill="currentColor" d="M3.2 7.6l4.6 3.6L12 4.6l4.2 6.6 4.6-3.6-1.8 10.2c-.1.6-.6 1-1.2 1H6.2c-.6 0-1.1-.4-1.2-1z"/>',
    'updown': '<path fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>',
}

SPRITE = ('<svg class="demo-icons" aria-hidden="true">'
          + ''.join(f'<symbol id="i-{name}" viewBox="0 0 24 24">{body}</symbol>' for name, body in ICONS.items())
          + '</svg>')


def icon(name, cls='ico'):
    return f'<svg class="{cls}" aria-hidden="true"><use href="#i-{name}"/></svg>'


# The ring's arc is drawn with pathLength 100, so demo.js sets how much of it
# shows as a plain percentage of time left. `filled` draws a ring that
# starts part way, as a percentage, through the SVG's own dash offset (the
# CSP refuses style attributes).
def ring(cls, size, stroke, filled=None):
    r = (size - stroke) / 2
    c = size / 2
    offset = '' if filled is None else f' stroke-dashoffset="{100 - filled:.1f}"'
    return (f'<svg class="{cls}" viewBox="0 0 {size} {size}" aria-hidden="true">'
            f'<circle class="ring-track" cx="{c:g}" cy="{c:g}" r="{r:g}" stroke-width="{stroke}"/>'
            f'<circle class="ring-arc" cx="{c:g}" cy="{c:g}" r="{r:g}" stroke-width="{stroke}" pathLength="100"{offset}/></svg>')


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

# The Closet's items, each one of the exported looks. Wardrobe items are
# bought with points; limited ones are earned by studying, never sold, so
# their tiles show how far along they are. All of them try on: hover or
# focus a tile (or tap it on a phone), and Mochi wears it in the big
# preview. Owned items also wear for real, in the notch and on the Timer.
BALANCE = 210
WARDROBE = [  # (look, name, cost or None if owned)
    ('hoodie', 'Cozy Hoodie', None),
    ('scholar', 'Scholar Set', None),
    ('flame', 'Flame Headband', None),
    ('wizard', 'Wizard Hat', 270),
    ('dino', 'Dinosaur Hoodie', 330),
]
LIMITED = [  # (look, name, how to earn it, done, goal, unit)
    ('crown', 'Tiny Crown', 'Earned for your first week', 1, 1, ''),
    ('cap', 'Backwards Cap', 'Finish a focus round in the Timer', 0, 1, 'round'),
    ('laurel', 'Golden Laurel', 'Study 7 days in a row', 4, 7, 'days'),
    ('medal', 'Team Medal', 'Study 50 hours in all', 31, 50, 'h'),
]


# An owned tile reads "Owned", or "On" while Mochi wears it; demo.css
# picks one from the tile's aria-pressed, so the script only flips state.
OWNED_STATUS = f'<span class="tile-status st-owned">Owned</span><span class="tile-status st-on">{icon("check")}On</span>'


def tile(look, name, detail, owned, status, cls='tile', extra=''):
    """One item: its look on Mochi, its status, and data demo.js reads.
    `detail` is what the footer says while the item is tried on. The flame
    is the animated item, so its tile plays its flicker too."""
    action = 'Click to wear it' if owned else 'Hover or tap to try it on'
    pet = ' data-pet="flame-tile"' if look == 'flame' else ''
    return (f'<button type="button" class="{cls}" data-look="{look}" data-name="{name}" data-detail="{detail}"{extra}'
            f'{" data-owned" if owned else ""} aria-pressed="false" title="{name}: {detail}. {action}" disabled>'
            f'<span class="pet" data-look="{look}"{pet}></span>{OWNED_STATUS}{status}</button>')


def wardrobe_tile(look, name, cost):
    if cost is None:
        return tile(look, name, 'Owned', True, '')
    return tile(look, name, f'{cost} pts to unlock', False, f'<span class="tile-status st-locked">{icon("lock")}{cost}</span>',
                extra=f' data-cost="{cost}"')


# A progress bar drawn as an SVG line, so no style attribute is needed.
def bar(fraction):
    return (f'<svg class="bar st-locked" viewBox="0 0 40 4" aria-hidden="true"><line x1="2" y1="2" x2="38" y2="2"/>'
            f'<line class="bar-fill" x1="2" y1="2" x2="{2 + 36 * fraction:g}" y2="2"/></svg>')


def limited_tile(look, name, how, done, goal, unit):
    owned = done >= goal
    status = '' if owned else f'<span class="tile-status st-locked">{done}/{goal} {unit}</span>{bar(done / goal)}'
    return tile(look, name, how, owned, icon('sparkles', 'ico tile-spark') + status, 'tile tile-limited')


NEXT = min((item for item in WARDROBE if item[2]), key=lambda item: item[2])
EARNED = sum(done >= goal for *_, done, goal, _ in LIMITED)

CLOSET_PANE = f'''
              <div class="pane pane-closet" data-pane="closet">
                <div class="n-card closet-pet">
                  <span class="pet pet-big" data-pet="closet" data-look="plain"></span>
                  <p class="pet-name">Mochi</p>
                  <p class="pet-sub" data-pet-sub>British Shorthair</p>
                </div>
                <div class="n-card closet-main">
                  <div class="closet-head">
                    <div class="sec-bar" role="radiogroup" aria-label="Closet sections">
                      <label class="sec" title="Outfits and accessories to unlock with study points"><input type="radio" name="closet-sec" value="wardrobe" checked>{icon('shirt')}<span>Wardrobe</span></label>
                      <label class="sec" title="Limited edition items, earned by studying, never sold"><input type="radio" name="closet-sec" value="limited">{icon('sparkles')}<span>Limited</span></label>
                    </div>
                    <p class="chip" title="Points: 1 for every focused minute, plus a bonus for finishing a session">{icon('star')}<span data-balance>{BALANCE}</span><span class="chip-unit">pts</span></p>
                  </div>
                  <div class="sec-pane sec-wardrobe">
                    <div class="tiles" aria-label="Wardrobe" role="group">{''.join(wardrobe_tile(*item) for item in WARDROBE)}</div>
                    <p class="closet-foot" data-foot="wardrobe"><span>Next unlock</span><b>{NEXT[1]}</b><span class="foot-gold" data-to-go>{NEXT[2] - BALANCE} pts to go</span></p>
                  </div>
                  <div class="sec-pane sec-limited">
                    <div class="tiles tiles-limited" aria-label="Limited" role="group">{''.join(limited_tile(*item) for item in LIMITED)}</div>
                    <p class="closet-foot" data-foot="limited"><span>Earned by studying, never sold</span><b class="foot-dim" data-earned>{EARNED} of {len(LIMITED)} earned</b></p>
                  </div>
                </div>
              </div>'''

# Now Playing's queue: made-up songs by made-up bands, each with a cover
# drawn like the app's generated artwork (a two-hue gradient, a soft light
# and a note). `hues` are the gradient's two hues in degrees, `length` and
# `at` are seconds, and the page starts paused partway into the first song.
TRACKS = [
    {'title': 'Paper Lanterns', 'artist': 'The Velvet Owls', 'album': 'Late Bloom',
     'length': 222, 'liked': True, 'hues': [348, 36]},
    {'title': 'Maple Street', 'artist': 'Juniper and June', 'album': 'Porch Light Stories',
     'length': 198, 'liked': False, 'hues': [205, 262]},
    {'title': 'Cloud Nap', 'artist': 'Soft Paws Trio', 'album': 'Slow Sundays',
     'length': 176, 'liked': False, 'hues': [318, 12]},
    {'title': 'Golden Hour Drive', 'artist': 'Sunny Static', 'album': 'Postcards',
     'length': 245, 'liked': True, 'hues': [150, 204]},
]
TRACK_AT = 82


def mmss(seconds):
    return f'{seconds // 60}:{seconds % 60:02d}'


FIRST = TRACKS[0]
FIRST_SUB = f"{FIRST['artist']} \u00b7 {FIRST['album']}"

# Like the app's Now Playing: the cover and its glow on the left, the song,
# the like heart, the scrubber and the transport on the right. demo.css
# draws the first song's hues as its default cover, so it needs no style
# attribute; demo.js recolors the cover for the others.
MUSIC_PANE = f'''
              <div class="pane pane-music" data-pane="music">
                <div class="cover" data-cover title="Made-up cover art. In the app, a click shows your music player">{icon('note')}</div>
                <div class="music-main">
                  <div class="music-head">
                    <p class="music-text" data-track-text title="{FIRST['title']}&#10;{FIRST_SUB}"><span class="music-title" data-track-title>{FIRST['title']}</span><span class="music-sub" data-track-sub>{FIRST_SUB}</span></p>
                    <button type="button" class="m-btn like" data-action="like" aria-pressed="{str(FIRST['liked']).lower()}" aria-label="Like" title="Unlike" disabled>{icon('heart')}</button>
                  </div>
                  <div class="scrub-wrap">
                    <input type="range" class="scrub" data-scrub min="0" max="{FIRST['length']}" step="1" value="{TRACK_AT}" aria-label="Position" aria-valuetext="{mmss(TRACK_AT)} of {mmss(FIRST['length'])}" title="Drag to seek" disabled>
                    <p class="music-times"><span data-track-at>{mmss(TRACK_AT)}</span><span data-track-left>-{mmss(FIRST['length'] - TRACK_AT)}</span></p>
                  </div>
                  <div class="transport">
                    <div class="modes">
                      <button type="button" class="m-btn mode" data-action="shuffle" aria-pressed="false" aria-label="Shuffle" title="Turn shuffle on" disabled>{icon('shuffle')}</button>
                      <button type="button" class="m-btn mode" data-action="repeat" aria-pressed="false" aria-label="Repeat" title="Repeat this song" disabled>{icon('repeat')}</button>
                    </div>
                    <div class="trio">
                      <button type="button" class="m-btn m-skip" data-action="prev" aria-label="Previous track" title="Previous track" disabled>{icon('back')}</button>
                      <button type="button" class="m-btn play" data-action="play" aria-label="Play" title="Play" disabled>{icon('play')}</button>
                      <button type="button" class="m-btn m-skip" data-action="next" aria-label="Next track" title="Next track" disabled>{icon('forward')}</button>
                    </div>
                  </div>
                </div>
              </div>'''

# Party, as the app's demo party has it: Mochi (you, the host) with Maya and
# Priya, and Leo among the friends, studying on his own. Start runs a
# shared focus round, sped up so it ends in seconds, and the party cheers;
# Invite brings Leo in. Nothing here talks to a server. (slot, look, name,
# status on the stage, status in the friends list, tone): the tone colors
# the status dot.
PARTY = [
    ('me', 'plain', 'You', 'Ready', '', 'idle'),
    ('maya', 'maya', 'Maya', '19m left', 'Studying · 19m', 'study'),
    ('priya', 'priya', 'Priya', 'Break', 'Break · 4m', 'break'),
    ('leo', 'leo', 'Leo', 'Ready', 'Studying · 41m', 'study'),
]
PARTY_CODE = 'Q4RT8M'
FRIEND_CODE = 'K7QW-2MZD'


def member(slot, look, name, status, _listed, tone):
    crown = icon('crown', 'ico crown') if slot == 'me' else ''
    hidden = ' hidden' if slot == 'leo' else ''
    return (f'<li class="member" data-member="{slot}"{hidden}><span class="pet pet-party" data-pet="party-{slot}" data-look="{look}"></span>'
            f'<span class="member-name">{crown}{name}</span>'
            f'<span class="member-status" data-tone="{tone}" data-status-of="{slot}">{status}</span></li>')


def friend(slot, look, name, _staged, status, tone):
    action = (f'<button type="button" class="pill-btn" data-action="invite" title="Invite Leo to your party" disabled>Invite</button>'
              if slot == 'leo' else f'<span class="friend-in" title="In your party">{icon("party")}</span>')
    return (f'<li class="friend" data-friend="{slot}"><span class="pet" data-pet="friend-{slot}" data-look="{look}"></span>'
            f'<span class="friend-text"><span class="friend-name">{name}</span>'
            f'<span class="member-status" data-tone="{tone}" data-status-of="{slot}">{status}</span></span>{action}</li>')


PARTY_PANE = f"""
              <div class="pane pane-party" data-pane="party">
                <div class="n-card stage">
                  <div class="stage-head">
                    <p class="stage-title">Party</p>
                    <span class="code-chip" title="The party code. Friends join with it (this one is made up)">{PARTY_CODE}</span>
                    <span class="stage-count" data-party-count title="Members in this party">3 of 8</span>
                  </div>
                  <ul class="members" aria-label="Party members">{''.join(member(*m) for m in PARTY)}</ul>
                  <div class="session">
                    <span class="session-icon">{icon('timer')}</span>
                    <p class="session-text"><span class="session-time" data-party-time>25:00</span><span class="session-cap" data-party-cap>focus together</span></p>
                    <svg class="session-bar" viewBox="0 0 100 4" preserveAspectRatio="none" aria-hidden="true"><line x1="2" y1="2" x2="98" y2="2"/><line class="bar-fill" x1="2" y1="2" x2="98" y2="2" pathLength="100" data-party-bar/></svg>
                    <button type="button" class="pill-btn pill-main" data-action="party" title="Start a shared focus round, sped up for this demo" disabled>Start</button>
                  </div>
                  <div class="party-banner" data-party-banner hidden>
                    <span class="banner-icon">{icon('party')}</span>
                    <p class="banner-text"><b>Great job, team!</b><span>+45 points for Mochi</span></p>
                  </div>
                </div>
                <div class="n-card friends">
                  <div class="friends-head">
                    <p class="friends-cap">Friends</p>
                    <span class="code-chip" title="Your friend code: friends add you with it (this one is made up)">{FRIEND_CODE}</span>
                  </div>
                  <ul class="friend-rows" aria-label="Friends">{''.join(friend(*m) for m in PARTY[1:])}</ul>
                </div>
              </div>"""

# AI Usage, as the app's demo shows it: the live 5-hour and weekly limits as
# rings and today's tokens by model, read from Claude Code or Codex on the
# Mac. demo.js lets the numbers tick up while the tab is open and swaps the
# figures when the source switches; the page shows Claude Code's.
AI_MODELS = [('Opus 5.5', 1_969_200, 'claude'), ('Haiku 4.5', 197_900, 'claude')]


def tokens(n):
    return f'{n / 1e6:.1f}M' if n >= 1e6 else f'{round(n / 1e3)}K'


def ai_ring(key, title, pct, reset, tone, help_text):
    return (f'<div class="ai-ring" title="{help_text}">'
            f'<div class="ai-dial" data-tone="{tone}" data-ai-dial="{key}">{ring("usage", 80, 7)}<p class="ai-pct" data-ai-pct="{key}">{pct}%</p></div>'
            f'<p class="ai-label">{title}</p><p class="ai-reset" data-ai-reset="{key}">{reset}</p></div>')


def ai_model(name, count, top):
    return (f'<li class="ai-model"><span class="ai-model-name">{name}</span>'
            f'<svg class="ai-bar" viewBox="0 0 100 4" preserveAspectRatio="none" aria-hidden="true"><line x1="2" y1="2" x2="98" y2="2"/>'
            f'<line class="bar-fill" x1="2" y1="2" x2="98" y2="2" pathLength="100" stroke-dashoffset="{100 - 100 * count / top:.1f}"/></svg>'
            f'<span class="ai-model-n">{tokens(count)}</span></li>')


AI_TOTAL = sum(n for _, n, _ in AI_MODELS)

AI_PANE = f"""
              <div class="pane pane-ai" data-pane="ai">
                <div class="ai-rings">
                  {ai_ring('five', '5-hour', 42, 'resets in 2h 14m', 'normal', 'Usage of your rolling 5-hour limit')}
                  {ai_ring('week', 'Weekly', 76, 'resets Thu 9:00 AM', 'warning', 'Usage of your weekly limit')}
                </div>
                <div class="n-card ai-card">
                  <p class="ai-cap">Today in <span data-ai-tool>Claude Code</span></p>
                  <p class="ai-total" title="Input, output and cache tokens across all sessions since midnight"><span class="ai-metric" data-ai-total>{tokens(AI_TOTAL)}</span><span>tokens</span></p>
                  <ul class="ai-models" data-ai-models aria-label="Tokens by model">{''.join(ai_model(name, n, AI_MODELS[0][1]) for name, n, _ in AI_MODELS)}</ul>
                  <template data-ai-model>{ai_model('', 0, 1)}</template>
                  <p class="ai-row"><span>Last 7 days</span><b data-ai-week>12.6M tokens</b></p>
                </div>
                <div class="ai-foot">
                  <p data-ai-updated>Updated just now</p>
                  <div class="ai-source" role="radiogroup" aria-label="Read usage from">
                    <label class="seg" title="Usage from Claude Code"><input type="radio" name="ai-source" value="claude" checked disabled><span>Claude Code</span></label>
                    <label class="seg" title="Usage from Codex"><input type="radio" name="ai-source" value="codex" disabled><span>Codex</span></label>
                  </div>
                  <button type="button" class="icon-btn" data-action="ai-refresh" title="Refresh now" aria-label="Refresh" disabled>{icon('refresh')}</button>
                </div>
              </div>"""

# Anki as the app's demo shows it: the cards due today in a ring with the
# new / learning / review split and what is done, the decks with the most
# due, the streak and the last ten days. Reviewing happens in Anki itself,
# with the panel on top, so demo.js only plays a short burst of reviews
# done there: the counts tick down and Done ticks up.
ANKI_DECKS = [  # (name, new, learning, review); the first is the pinned favorite
    ('Spanish verbs', 8, 3, 38),
    ('Biology', 6, 2, 28),
    ('World history', 4, 1, 20),
    ('Chemistry', 2, 2, 14),
]
ANKI_DONE = 46
ANKI_STREAK = 12
# Reviews on each of the last ten days, today last (its count is Done).
ANKI_HISTORY = [70, 140, 120, 95, 150, 105, 125, 90, 135, ANKI_DONE]
ANKI_QUEUES = [('new', 'New'), ('learn', 'Learning'), ('review', 'Review')]
ANKI_TOTALS = {key: sum(deck[i + 1] for deck in ANKI_DECKS) for i, (key, _) in enumerate(ANKI_QUEUES)}
ANKI_DUE = sum(ANKI_TOTALS.values())


def heat_level(count, busiest):
    """The app's AnkiFormat.heatLevels: four shades scaled to the busiest day,
    and at least one for any day with reviews."""
    return min(max(-(-count * 4 // busiest), 1), 4) if count else 0


def anki_queue(key, title):
    count = ANKI_TOTALS[key]
    return (f'<p class="queue" data-tone="{key}"><span class="queue-name">{title}</span>'
            f'<span class="queue-n" data-anki-total="{key}">{count}</span></p>')


def anki_deck(name, new, learn, review, favorite):
    star = f'<span class="deck-star" title="Pinned to the Study button">{icon("star")}</span>' if favorite else ''
    counts = ''.join(f'<span class="deck-n" data-tone="{key}" data-anki-count="{key}">{n}</span>'
                     for (key, _), n in zip(ANKI_QUEUES, (new, learn, review)))
    return (f'<li><button type="button" class="deck-row" data-anki-deck="{name}" '
            f'title="Review {name} in Anki: {new} new, {learn} learning, {review} review" disabled>'
            f'<span class="deck-name">{name}</span>{star}{icon("play", "ico deck-play")}{counts}</button></li>')


def anki_day(count, busiest, days_ago):
    when = 'Today' if days_ago == 0 else 'Yesterday' if days_ago == 1 else f'{days_ago} days ago'
    today = ' data-today' if days_ago == 0 else ''
    return (f'<span class="heat" data-count="{count}" data-level="{heat_level(count, busiest)}"{today} '
            f'title="{when}: {count} reviews"></span>')


ANKI_PANE = f"""
              <div class="pane pane-anki" data-pane="anki">
                <div class="n-card due-card" data-anki-due-card title="{ANKI_DONE} reviewed of {ANKI_DONE + ANKI_DUE} today">
                  <div class="due-dial">
                    {ring('due-ring', 92, 7, 100 * ANKI_DONE / (ANKI_DONE + ANKI_DUE))}
                    <p class="due-read"><span class="due-n" data-anki-due>{ANKI_DUE}</span><span class="due-cap">due</span></p>
                    <p class="due-read due-all">{icon('check', 'ico due-check')}<span class="due-cap">All done</span></p>
                  </div>
                  <div class="queues">
                    {''.join(anki_queue(key, title) for key, title in ANKI_QUEUES)}
                    <p class="queue-done"><span>Done</span><span data-anki-done>{ANKI_DONE}</span></p>
                  </div>
                </div>
                <div class="n-card decks">
                  <p class="decks-head" data-anki-head><span class="decks-spin"></span>{icon('cards', 'ico note-review')}{icon('check-fill', 'ico note-done')}<span class="decks-note">Top decks</span></p>
                  <ul class="deck-rows" aria-label="Top decks">{''.join(anki_deck(*deck, i == 0) for i, deck in enumerate(ANKI_DECKS))}</ul>
                </div>
                <div class="anki-foot">
                  <p class="streak" title="Days in a row with at least one review">{icon('flame')}<span>{ANKI_STREAK}-day streak</span></p>
                  <p class="heatmap" data-anki-heat title="Reviews on each of the last ten days, today outlined">{''.join(anki_day(n, max(ANKI_HISTORY), len(ANKI_HISTORY) - 1 - i) for i, n in enumerate(ANKI_HISTORY))}</p>
                  <button type="button" class="icon-btn" data-action="anki-sync" title="Sync with AnkiWeb" aria-label="Sync with AnkiWeb" disabled>{icon('refresh')}</button>
                  <button type="button" class="study" data-action="anki-study" data-anki-deck="{ANKI_DECKS[0][0]}" title="Review {ANKI_DECKS[0][0]} in Anki: {sum(ANKI_DECKS[0][1:])} due" disabled>{icon('play')}<span class="study-label">Study {ANKI_DECKS[0][0]}</span><span class="study-n" data-anki-study-n>{sum(ANKI_DECKS[0][1:])}</span></button>
                </div>
              </div>"""

# (id, title, icon). The tab bar left of the camera, like the app's.
TABS = [
    ('timer', 'Timer', 'timer'),
    ('today', 'Today', 'checklist'),
    ('music', 'Now Playing', 'note'),
    ('party', 'Party', 'party'),
    ('ai', 'AI Usage', 'gauge'),
    ('anki', 'Anki', 'cards'),
]


# The chips under the demo: each opens the notch on its tab. They are
# labels for the tabs' radio buttons, so they switch tabs without the script
# too.
TRY = [('timer', 'Timer'), ('today', 'Today'), ('music', 'Music'), ('party', 'Party'), ('ai', 'AI Usage'), ('anki', 'Flashcards')]


def tab(tab_id, title, symbol, checked):
    return (f'<label class="tab tab-{tab_id}" title="{title}">'
            f'<input type="radio" name="demo-tab" id="demo-tab-{tab_id}" value="{tab_id}" aria-label="{title}"{" checked" if checked else ""}>'
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
              <span class="wing wing-r"><span class="mini-time" data-time>0:20</span><span class="eq" title="Playing"><span></span><span></span><span></span><span></span></span></span>
            </button>
            <div class="panel" id="demo-panel" role="group" aria-label="Tabbi panel">
             <div class="panel-inner">
              <div class="panel-head" role="radiogroup" aria-label="Tabs">
                <div class="tab-bar">
                  {''.join(tab(t, title, symbol, i == 0) for i, (t, title, symbol) in enumerate(TABS))}
                </div>
                <p class="head-title"><span class="title-timer">Timer</span><span class="title-today">Today</span><span class="title-music">Now Playing</span><span class="title-party">Party</span><span class="title-ai">AI Usage</span><span class="title-anki">Anki</span><span class="title-closet">Closet</span></p>
                {tab('closet', 'Closet: your pet', 'paw', False)}
              </div>
{TIMER_PANE}
{TODAY_PANE}
{MUSIC_PANE}
{PARTY_PANE}
{AI_PANE}
{ANKI_PANE}
{CLOSET_PANE}
             </div>
            </div>
          </div>
          <p class="hint" aria-hidden="true"><svg viewBox="0 0 40 32" width="40" height="32"><path d="M36 28C24 28 12 22 7 6m0 0L3 13m4-7 6 5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>Psst... try it</p>
          <p class="burst" aria-hidden="true"><span class="burst-pts">+35 pts</span></p>
        </div>
        <p class="try"><span class="try-cap">Try</span>{''.join(f'<label class="try-chip" for="demo-tab-{t}">{name}</label>' for t, name in TRY)}</p>
        <p class="try-note">Every tab is optional. Keep the ones you love.</p>
        <p class="sr-only" aria-live="polite" data-status></p>
      </section>
'''


def data_block(block_id, data):
    text = json.dumps(data, separators=(',', ':')).replace('<', '\\u003c')
    return f'\n  <script type="application/json" id="{block_id}">{text}</script>'


def demo_data():
    """pets.json, Today's days and Now Playing's songs, minified, as data blocks for demo.js. The
    CSP lets the page load nothing but its own files, and a data block is
    never run, so they ride along in the page instead of a fetch the CSP
    would stop."""
    pets = json.loads((HERE / 'img' / 'demo' / 'pets.json').read_text())
    return data_block('demo-pets', pets) + data_block('demo-days', DAYS) + data_block('demo-tracks', TRACKS)
