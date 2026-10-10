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

# (id, title, icon). The tab bar left of the camera, like the app's.
TABS = [
    ('timer', 'Timer', 'timer'),
    ('today', 'Today', 'checklist'),
    ('music', 'Now Playing', 'note'),
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
              <span class="wing wing-r"><span class="mini-time" data-time>0:20</span><span class="eq" title="Playing"><span></span><span></span><span></span><span></span></span></span>
            </button>
            <div class="panel" id="demo-panel" role="group" aria-label="Tabbi panel">
             <div class="panel-inner">
              <div class="panel-head" role="radiogroup" aria-label="Tabs">
                <div class="tab-bar">
                  {''.join(tab(t, title, symbol, i == 0) for i, (t, title, symbol) in enumerate(TABS))}
                </div>
                <p class="head-title"><span class="title-timer">Timer</span><span class="title-today">Today</span><span class="title-music">Now Playing</span><span class="title-closet">Closet</span></p>
                {tab('closet', 'Closet: your pet', 'paw', False)}
              </div>
{TIMER_PANE}
{TODAY_PANE}
{MUSIC_PANE}
{CLOSET_PANE}
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
    """pets.json, Today's days and Now Playing's songs, minified, as data blocks for demo.js. The
    CSP lets the page load nothing but its own files, and a data block is
    never run, so they ride along in the page instead of a fetch the CSP
    would stop."""
    pets = json.loads((HERE / 'img' / 'demo' / 'pets.json').read_text())
    return data_block('demo-pets', pets) + data_block('demo-days', DAYS) + data_block('demo-tracks', TRACKS)
