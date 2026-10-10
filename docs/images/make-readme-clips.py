"""Renders the README's short feature clips as small animated WebPs.

    python3 docs/images/make-readme-clips.py [snapshot-folder]

Without a folder it renders one first with
`TABBI_DEMO=1 swift run Tabbi --snapshot <tmp>`.
Every pixel of the app comes from the app itself: the pet clips are the
sprite sheets the site exports (site/img/demo), and the panels are the
demo snapshots. Only the card behind the pet and its captions are drawn here.

Writes docs/images/clip-costumes.webp and docs/images/clip-party.webp.
Needs Pillow.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PETS = ROOT / 'site' / 'img' / 'demo'
FONT = '/System/Library/Fonts/SFNSRounded.ttf'

# Theme.Palette: the notch's black, a Card surface, and the text levels.
BACKGROUND = (0, 0, 0, 255)
CARD = (28, 28, 33, 255)
PRIMARY = (255, 255, 255, 255)
SECONDARY = (163, 163, 170, 255)
CLOSET_ACCENT = (244, 196, 64, 255)


def font(size, weight):
    """SF Pro Rounded at a named weight (the variable font's instances)."""
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def save_webp(frames, durations, path):
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, lossless=True, method=6)
    print(f'{path.relative_to(ROOT)}: {len(frames)} frames, {path.stat().st_size // 1024} KB')


# --------------------------------------------------------------------------
# Costumes: Mochi tries on each Closet item and cheers in it.
# --------------------------------------------------------------------------

# (look, name, how it is earned), in the order the Closet shows them.
LOOKS = [
    ('plain', 'Mochi', 'British Shorthair'),
    ('hoodie', 'Cozy Hoodie', 'Bought with study points'),
    ('scholar', 'Scholar Set', 'Bought with study points'),
    ('wizard', 'Wizard Hat', 'Bought with study points'),
    ('dino', 'Dinosaur Hoodie', 'Bought with study points'),
    ('crown', 'Tiny Crown', 'Earned in your first week'),
    ('cap', 'Backwards Cap', 'Finish a focus round'),
    ('laurel', 'Golden Laurel', 'Study 7 days in a row'),
    ('medal', 'Team Medal', 'Study 50 hours in all'),
    ('flame', 'Flame Headband', 'Bought with study points'),
]
CARD_W, CARD_H = 640, 280
PET_SCALE = 7  # 32 px sprites at 224 pt, whole pixels so they stay crisp
CORNER = 32


def sprite_frames(sheet, meta, clip):
    """The frames and durations of one clip of a look's sprite sheet."""
    size = meta['frame']
    info = clip
    frames = []
    for i, _ in enumerate(info['durations']):
        box = (i * size, info['row'] * size, (i + 1) * size, (info['row'] + 1) * size)
        frames.append(sheet.crop(box).resize((size * PET_SCALE, size * PET_SCALE), Image.NEAREST))
    return frames, list(info['durations'])


def costume_card(pet, name, detail, index):
    card = Image.new('RGBA', (CARD_W, CARD_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((0, 0, CARD_W - 1, CARD_H - 1), CORNER, fill=BACKGROUND)
    inner = 16
    draw.rounded_rectangle((inner, inner, inner + 248, CARD_H - inner - 1), 20, fill=CARD)
    card.alpha_composite(pet, (inner + (248 - pet.width) // 2, (CARD_H - pet.height) // 2 + 4))
    x = inner + 248 + 32
    draw.text((x, 92), 'Closet', font=font(20, 'Semibold'), fill=CLOSET_ACCENT)
    draw.text((x, 120), name, font=font(34, 'Bold'), fill=PRIMARY)
    draw.text((x, 166), detail, font=font(20, 'Medium'), fill=SECONDARY)
    # One dot per look, the current one in the accent: how far along the loop is.
    for i in range(len(LOOKS)):
        cx = x + 6 + i * 18
        fill = CLOSET_ACCENT if i == index else (70, 70, 78, 255)
        draw.ellipse((cx - 4, 216, cx + 4, 224), fill=fill)
    return card


def costumes():
    meta = json.loads((PETS / 'pets.json').read_text())
    frames, durations = [], []
    for index, (look, name, detail) in enumerate(LOOKS):
        info = meta['looks'][look]
        sheet = Image.open(PETS / info['file']).convert('RGBA')
        idle, idle_d = sprite_frames(sheet, meta, info['clips']['idle'])
        cheer, cheer_d = sprite_frames(sheet, meta, info['clips']['celebrate'])
        if look == 'flame':
            # The flame is the point: let its flicker loop a few times.
            sequence = list(zip(idle, idle_d)) * 2 + list(zip(cheer, cheer_d)) + list(zip(idle, idle_d))
        else:
            sequence = [(idle[0], 500)] + list(zip(cheer, cheer_d)) + [(idle[0], 700)]
        for pet, ms in sequence:
            frames.append(costume_card(pet, name, detail, index))
            durations.append(ms)
    save_webp(frames, durations, HERE / 'clip-costumes.webp')


# --------------------------------------------------------------------------
# Party: friends studying together, then the team celebration.
# --------------------------------------------------------------------------

PANEL_W = 720


def panel(snapshots, name):
    shot = Image.open(snapshots / f'{name}.png').convert('RGBA')
    height = round(shot.height * PANEL_W / shot.width)
    return shot.resize((PANEL_W, height), Image.LANCZOS)


def ease(t):
    """Ease in and out, like a Theme.Motion spring settling (never linear)."""
    return t * t * (3 - 2 * t)


def crossfade(a, b, steps, ms):
    frames = [Image.blend(a, b, ease((i + 1) / (steps + 1))) for i in range(steps)]
    return frames, [ms] * steps


def party(snapshots):
    studying = panel(snapshots, 'open-party')
    done = panel(snapshots, 'open-party-celebrating')
    fade_in, fade_in_d = crossfade(studying, done, 6, 40)
    fade_out, fade_out_d = crossfade(done, studying, 6, 40)
    frames = [studying] + fade_in + [done] + fade_out
    durations = [2200] + fade_in_d + [3000] + fade_out_d
    # Lossy here: the panels are photos of UI with soft shadows, and lossless
    # would be five times the size for no visible gain.
    frames[0].save(HERE / 'clip-party.webp', save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, quality=80, method=6)
    path = HERE / 'clip-party.webp'
    print(f'{path.relative_to(ROOT)}: {len(frames)} frames, {path.stat().st_size // 1024} KB')


def main():
    if len(sys.argv) > 1:
        snapshots = Path(sys.argv[1])
    else:
        snapshots = Path(tempfile.mkdtemp())
        subprocess.run(['swift', 'run', 'Tabbi', '--snapshot', str(snapshots)], cwd=ROOT, check=True,
                       env={**__import__('os').environ, 'TABBI_DEMO': '1'})
    costumes()
    party(snapshots)


if __name__ == '__main__':
    main()
