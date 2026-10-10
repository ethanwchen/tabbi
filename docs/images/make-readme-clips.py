"""Renders the README's short feature clips as small animated WebPs.

    python3 docs/images/make-readme-clips.py [snapshot-folder]

Without a folder it renders one first with
`TABBI_DEMO=1 swift run Tabbi --snapshot <tmp>`.
Every pixel of the app comes from the app itself: the pet clips are the
sprite sheets the site exports (site/img/demo), and the panels are the
demo snapshots. Only the card behind the pet and its captions are drawn here.

Writes docs/images/clip-costumes.webp, clip-party.webp and clip-celebration.webp.
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


# --------------------------------------------------------------------------
# Celebration: a focus round ends with confetti and the cat's "That's a wrap".
# --------------------------------------------------------------------------

# The confetti strip's cells: 520 x 300 px each, 536 px apart, from (24, 24).
CONFETTI_CELL = (24, 24, 520, 300, 536)
CONFETTI_TIMES = [0.05, 0.15, 0.30, 0.50, 0.80, 1.10, 1.40]


def confetti_frames(snapshots):
    """The milestone confetti keyframes on black, as overlay masks for the panel."""
    strip = Image.open(snapshots / 'motion-celebration-confetti-milestone.png').convert('RGBA')
    x0, y0, w, h, step = CONFETTI_CELL
    cells = []
    for i in range(len(CONFETTI_TIMES)):
        cell = strip.crop((x0 + i * step, y0, x0 + i * step + w, y0 + h))
        # A bit larger than the panel's scale, so the pieces read in a small clip.
        cells.append(cell.resize((round(w * 0.8), round(h * 0.8)), Image.LANCZOS))
    return cells


def overlay(base, cell):
    """Confetti over the panel: the black around each piece stays see-through."""
    mask = cell.convert('L').point(lambda v: min(255, v * 3))
    out = base.copy()
    out.paste(cell, ((base.width - cell.width) // 2, (base.height - cell.height) // 2 - 16), mask)
    return out


def wrap_bubble(snapshots):
    """The pet coach's "That's a wrap. Well done!" bubble, cut from its snapshot."""
    shot = Image.open(snapshots / 'coach-celebrate.png').convert('RGBA')
    box = (369, 80, 806, 224)  # the bubble with its tail, inside the shadow
    bubble = shot.crop(box)
    mask = Image.new('L', bubble.size, 0)
    draw = ImageDraw.Draw(mask)
    # Inset 2 px: the outer edge carries the light window behind the snapshot.
    draw.rounded_rectangle((14, 2, bubble.width - 3, bubble.height - 3), 20, fill=255)
    # The tail: the near-black pixels left of the bubble.
    for x in range(14):
        for y in range(bubble.height):
            if max(bubble.getpixel((x, y))[:3]) < 30:
                mask.putpixel((x, y), 255)
    bubble.putalpha(mask)
    # A hairline, so the black bubble stands apart from the dimmed panel.
    ImageDraw.Draw(bubble).rounded_rectangle((14, 2, bubble.width - 3, bubble.height - 3), 20,
                                             outline=(255, 255, 255, 40), width=2)
    scale = 0.7
    return bubble.resize((round(bubble.width * scale), round(bubble.height * scale)), Image.LANCZOS)


def wrap_card(dimmed, pet, bubble):
    card = dimmed.copy()
    gap = 12
    width = pet.width + gap + bubble.width
    x = (card.width - width) // 2
    y = (card.height - pet.height) // 2
    card.alpha_composite(pet, (x, y))
    card.alpha_composite(bubble, (x + pet.width + gap, (card.height - bubble.height) // 2))
    return card


def celebration(snapshots):
    timer = panel(snapshots, 'open-study')
    cells = confetti_frames(snapshots)
    meta = json.loads((PETS / 'pets.json').read_text())
    info = meta['looks']['scholar']
    sheet = Image.open(PETS / info['file']).convert('RGBA')
    scale = 3
    def pet_frames(clip):
        size = meta['frame']
        row = info['clips'][clip]
        return [sheet.crop((i * size, row['row'] * size, (i + 1) * size, (row['row'] + 1) * size))
                .resize((size * scale, size * scale), Image.NEAREST)
                for i in range(len(row['durations']))], list(row['durations'])
    cheer, cheer_d = pet_frames('celebrate')
    idle, _ = pet_frames('idle')
    bubble = wrap_bubble(snapshots)
    dimmed = Image.blend(timer, Image.new('RGBA', timer.size, BACKGROUND), 0.72)

    frames, durations = [timer], [1800]
    # The burst, timed like the app: each keyframe held until the next one.
    for i, cell in enumerate(cells[:-1]):
        frames.append(overlay(timer, cell))
        durations.append(round((CONFETTI_TIMES[i + 1] - CONFETTI_TIMES[i]) * 1000))
    first = wrap_card(dimmed, idle[0], bubble)
    fade, fade_d = crossfade(overlay(timer, cells[-1]), first, 5, 40)
    frames += fade
    durations += fade_d
    for pet, ms in zip(cheer, cheer_d):
        frames.append(wrap_card(dimmed, pet, bubble))
        durations.append(ms)
    frames.append(wrap_card(dimmed, idle[0], bubble))
    durations.append(2000)
    back, back_d = crossfade(frames[-1], timer, 6, 40)
    frames += back
    durations += back_d
    path = HERE / 'clip-celebration.webp'
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, quality=80, method=6)
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
    celebration(snapshots)


if __name__ == '__main__':
    main()
