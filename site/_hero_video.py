"""Renders the home page's hero animation from the app's own demo snapshots.

    python3 site/_hero_video.py [snapshot-folder]

Without a folder it renders one first with
`TABBI_DEMO=1 swift run Tabbi --snapshot <tmp> --scale 3 --transparent`.
The clip is nine seconds and loops: the pointer clicks the notch, the panel
springs open on the Timer, which ticks, the pointer switches to Today and
checks off a task, the panel closes and the pet cheers in the notch. The
camera zooms in on each step. Everything else (the wallpaper, the pointer,
the ticking digits, the check, the sparkles) is drawn here on top of the
snapshots, so the panels themselves are the app's real pixels.

Writes img/hero.mp4 (H.264, which every browser plays and which came out
smaller than VP9 here), img/hero-poster.webp (the open Timer, also what
prefers-reduced-motion shows) and img/hero-fallback.webp (a small animated
WebP for browsers without video).
Needs Pillow, numpy, scipy and ffmpeg.
"""

import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
IMG = SITE / 'img'

# Snapshots at --scale 3, so every crop below scales down and stays crisp.
# Positions are written in the 2x pixels of the default snapshot ("units")
# and multiplied by K.
SCALE = 3
K = SCALE / 2
OUT_W, OUT_H = 1200, 750  # 16:10, the drawn laptop's screen at 2x
FPS = 30
SECONDS = 9.0
# The screen the notch sits in, in units: wide enough that the closed notch
# reads as part of a laptop, and 16:10 like the drawn one on the page.
WORLD_W = 2040
WORLD_H = WORLD_W * 10 // 16
SNAP_X = (WORLD_W - 1200) / 2  # snapshots are 1200 units wide, centered
FONT = '/System/Library/Fonts/SFNSRounded.ttf'


def px(v):
    return int(round(v * K))


# --------------------------------------------------------------------------
# Easing. Nothing moves linearly.
# --------------------------------------------------------------------------

def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def ease(p):
    """Ease in and out (cubic)."""
    p = clamp(p)
    return 4 * p ** 3 if p < 0.5 else 1 - (-2 * p + 2) ** 3 / 2


def spring(p):
    """A lightly damped spring, about 6% overshoot, settled at p = 1."""
    if p <= 0:
        return 0.0
    if p >= 1:
        return 1.0
    return 1 - math.exp(-7 * p) * (math.cos(8 * p) + 7 / 8 * math.sin(8 * p))


def phase(t, start, end):
    return clamp((t - start) / (end - start))


def lerp(a, b, p):
    return a + (b - a) * p


# --------------------------------------------------------------------------
# Snapshots and the drawing on top of them
# --------------------------------------------------------------------------

def load(folder, name):
    return Image.open(folder / f'{name}.png').convert('RGBA')


class Glyphs:
    """Redraws single characters in a snapshot (a ticking digit, a count)
    in SF Rounded, matched to the original's size, weight and color, so
    the clip can show time passing without another render of the app."""

    def __init__(self, image, box):
        self.image = image
        x0, y0, x1, y1 = (px(v) for v in box)
        region = np.asarray(image.crop((x0, y0, x1, y1)).convert('RGB')).astype(int)
        flat = region.reshape(-1, 3)
        colors, counts = np.unique(flat, axis=0, return_counts=True)
        self.bg = tuple(colors[counts.argmax()])
        distance = np.abs(flat - np.array(self.bg)).sum(axis=1)
        self.fg = tuple(flat[distance.argmax()])
        ink = np.abs(region - np.array(self.bg)).sum(axis=2) > 60
        columns = np.where(ink.any(axis=0))[0]
        # Characters are runs of inked columns.
        self.slots = []
        start = prev = columns[0]
        for c in list(columns[1:]) + [None]:
            if c is None or c > prev + 1:
                rows = np.where(ink[:, start:prev + 1].any(axis=1))[0]
                self.slots.append((x0 + start, y0 + rows[0], x0 + prev + 1, y0 + rows[-1] + 1))
                if c is not None:
                    start = c
            if c is not None:
                prev = c
        self.font = None

    def fit(self, slot, char):
        """Finds the font size and weight whose `char` matches the slot."""
        x0, y0, x1, y1 = self.slots[slot]
        target = np.asarray(self.image.crop((x0, y0, x1, y1)).convert('L')).astype(float)
        target = np.abs(target - np.mean(self.bg)) / max(1, abs(np.mean(self.fg) - np.mean(self.bg)))
        best = None
        for weight in range(500, 860, 30):
            size = (y1 - y0) * 1.3
            for _ in range(3):
                font = self._font(size, weight)
                ink = self._ink(font, char)
                size *= (y1 - y0) / ink.shape[0]
            font = self._font(size, weight)
            ink = self._ink(font, char)
            h, w = min(ink.shape[0], target.shape[0]), min(ink.shape[1], target.shape[1])
            error = np.abs(ink[:h, :w] - target[:h, :w]).mean() + abs(ink.shape[1] - target.shape[1]) * 0.05
            if best is None or error < best[0]:
                best = (error, font)
        self.font = best[1]
        return self

    @staticmethod
    def _font(size, weight):
        font = ImageFont.truetype(FONT, max(1, int(round(size))))
        font.set_variation_by_axes([400, weight])
        return font

    @staticmethod
    def _ink(font, char):
        mask = Image.new('L', (font.size * 2, font.size * 2), 0)
        ImageDraw.Draw(mask).text((font.size // 2, font.size // 4), char, font=font, fill=255)
        a = np.asarray(mask).astype(float) / 255
        rows, cols = np.where(a > 0.2)
        return a[rows.min():rows.max() + 1, cols.min():cols.max() + 1]

    def replace(self, image, slot, char):
        """`image` with the slot's character drawn as `char`, centered on
        the old one and on the same baseline."""
        x0, y0, x1, y1 = self.slots[slot]
        out = image.copy()
        draw = ImageDraw.Draw(out)
        pad = px(2)
        draw.rectangle((x0 - pad, y0 - pad, x1 + pad - 1, y1 + pad - 1), fill=self.bg + (255,))
        ink = self._ink(self.font, char)
        h, w = ink.shape
        cx = (x0 + x1) / 2
        left, top = int(round(cx - w / 2)), y1 - h
        color = Image.new('RGBA', (w, h), self.fg + (255,))
        out.paste(color, (left, top), Image.fromarray((ink * 255).astype(np.uint8)))
        return out


def timer_frames(snaps):
    """The Timer panel at 15:14, 15:13 and 15:12."""
    timer = load(snaps, 'open-study')
    glyphs = Glyphs(timer, (190, 210, 375, 285))
    assert len(glyphs.slots) == 5, glyphs.slots
    glyphs.fit(4, '4')
    return {s: glyphs.replace(timer, 4, str(s)) for s in (4, 3, 2)}


def today_frames(snaps):
    """Today before and after checking off "Ship notch planner beta", with
    the running Timer's card showing 15:12, 15:11 and 15:10."""
    today = load(snaps, 'open-planner')
    clock = Glyphs(today, (780, 370, 866, 400))
    assert len(clock.slots) == 5, clock.slots
    clock.fit(1, '4')
    count = Glyphs(today, (425, 88, 442, 110))
    count.fit(0, '3')

    def at(image, seconds):
        for slot, char in zip((1, 3, 4), f'5{seconds:02d}'):
            image = clock.replace(image, slot, char)
        return image

    done = count.replace(today, 0, '4')
    # The check: the circle of "Review Ana's pull request" two rows up, a
    # strike through the title in the done rows' gray.
    a = np.asarray(done).copy()
    row, step = px(203), px(88)
    x0, x1 = px(118), px(162)
    half = px(22)
    a[row + step - half:row + step + half, x0:x1] = a[row - half:row + half, x0:x1]
    title = a[px(272):px(312), px(170):px(445), :3].astype(float)
    title *= 158 / 255
    a[px(272):px(312), px(170):px(445), :3] = title.astype(np.uint8)
    checked = Image.fromarray(a)
    return {
        'plain': {s: at(today, s) for s in (12, 11, 10)},
        'checked': {s: at(checked, s) for s in (12, 11, 10)},
        'check_box': (x0, row + step - half, x1, row + step + half),
        'strike': (px(176), row + step, px(435), row + step + px(2)),
    }


def wallpaper():
    """The drawn laptop's wallpaper from styles.css, as one RGB image."""
    w, h = px(WORLD_W), px(WORLD_H)
    y, x = np.mgrid[0:h, 0:w].astype(float)
    fy = y / (h - 1)
    stops = [(0, (0x4A, 0x3A, 0x2E)), (0.55, (0x6E, 0x51, 0x41)), (1, (0x9A, 0x6F, 0x55))]
    out = np.zeros((h, w, 3))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        inside = (fy >= p0) & (fy <= p1)
        m = ((fy - p0) / (p1 - p0))[..., None]
        out = np.where(inside[..., None], np.array(c0) * (1 - m) + np.array(c1) * m, out)
    # Bottom layer first: radial-gradient(rx ry at cx cy, color alpha, transparent stop).
    for rx, ry, cx, cy, color, alpha, stop in [
        (0.50, 0.50, 0.80, 0.10, (0xF2, 0xA0, 0xA6), 0.25, 0.70),
        (0.60, 0.80, 0.92, 1.00, (0xF4, 0xD5, 0x7E), 0.75, 0.62),
        (0.70, 0.90, 0.12, 1.05, (0xF2, 0xA0, 0xA6), 0.85, 0.60),
    ]:
        d = np.sqrt(((x / w - cx) / rx) ** 2 + ((y / h - cy) / ry) ** 2)
        a = (alpha * np.clip(1 - d / stop, 0, 1))[..., None]
        out = out * (1 - a) + np.array(color) * a
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def notch_shape(p):
    """The black notch shape between closed (p = 0, the pet's wing) and
    open (p = 1, the panel), in snapshot pixels, as an L mask."""
    x0 = lerp(319, 64, p)
    x1 = lerp(880, 1135, p)
    h = lerp(64, 472, p)
    r = lerp(20, 48, clamp(p, 0, 1.2))
    s = lerp(7, 17, clamp(p))
    ss = 4  # supersampled
    mask = Image.new('L', (px(1200) * ss // 4, px(max(h, 64) + 8) * ss // 4), 0)
    d = ImageDraw.Draw(mask)
    f = K * ss / 4
    d.rounded_rectangle((x0 * f, -r * f, x1 * f, h * f), radius=r * f, fill=255)
    # The shoulders that flare into the top edge.
    for side in (-1, 1):
        edge = x0 if side < 0 else x1
        box = (edge - s, 0, edge, s) if side < 0 else (edge, 0, edge + s, s)
        d.rectangle(tuple(v * f for v in box), fill=255)
        cx = edge - s if side < 0 else edge + s
        d.ellipse(((cx - s) * f, 0, (cx + s) * f, 2 * s * f), fill=0)
    return mask.resize((px(1200), mask.height * 4 // ss), Image.LANCZOS)


def sparkle(size, color, angle):
    """A four-point sparkle, drawn large and scaled down so it is smooth."""
    big = max(8, int(size * 4))
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    c, r, n = big / 2, big / 2, big / 9
    points = []
    for i in range(8):
        a = angle + i * math.pi / 4
        rad = r if i % 2 == 0 else n
        points.append((c + rad * math.cos(a), c + rad * math.sin(a)))
    ImageDraw.Draw(im).polygon(points, fill=color + (255,))
    return im.resize((max(2, int(size)), max(2, int(size))), Image.LANCZOS)


SPARKLE_COLORS = [(0xF4, 0xD5, 0x7E), (0xF2, 0xA0, 0xA6), (0xFB, 0xF7, 0xF0), (0x9F, 0xE0, 0xC0), (0x9C, 0xC8, 0xFF)]


def bursts():
    """Sparkle particles: (start time, x, y, vx, vy, size, color, spin)."""
    rng = np.random.default_rng(9)
    particles = []
    for start in (6.75, 7.35):
        for i in range(14):
            a = rng.uniform(-0.15 * math.pi, 1.15 * math.pi)  # mostly down and out
            v = rng.uniform(140, 300)
            particles.append((start + rng.uniform(0, 0.08), 361, 34, v * math.cos(a), v * abs(math.sin(a)) * 0.9 + 40,
                              rng.uniform(10, 18), SPARKLE_COLORS[i % len(SPARKLE_COLORS)], rng.uniform(0, 1)))
    return particles


ARROW = [(0, 0), (0, 16.5), (4, 12.6), (6.8, 19.2), (9.4, 18.1), (6.7, 11.7), (11.8, 11.7)]


def draw_pointer(frame, x, y, size, press):
    """The macOS arrow: black, a white edge and a soft shadow. `size` is its
    height in output pixels; a click squeezes it a little."""
    k = size / 19.2 * (1 - 0.14 * press)
    ss = 4
    w, h = int(16 * k * ss), int(24 * k * ss)
    pad = 2 * k * ss
    pts = [(pad + x_ * k * ss, pad + y_ * k * ss) for x_, y_ in ARROW]
    shadow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(shadow).polygon([(a, b + k * ss) for a, b in pts], fill=110)
    shadow = gaussian_filter(np.asarray(shadow).astype(float), 1.2 * k * ss)
    sprite = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sprite.putalpha(Image.fromarray(shadow.astype(np.uint8)))
    d = ImageDraw.Draw(sprite)
    edge = max(2, int(0.75 * k * ss))
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=2 * edge, joint='curve')
    d.polygon(pts, fill=(0, 0, 0, 255))
    sprite = sprite.resize((w // ss, h // ss), Image.LANCZOS)
    frame.alpha_composite(sprite, (int(round(x - pad / ss)), int(round(y - pad / ss))))


# --------------------------------------------------------------------------
# The timeline, in seconds
# --------------------------------------------------------------------------

AWAY = (840, 640)   # the pointer's resting place below the panel (snapshot units)
NOTCH = (600, 30)   # the closed notch, then the empty middle of the header
TODAY_TAB = (192, 33)
CHECKBOX = (140, 291)

# (time, snapshot-unit x, y): the pointer's stops, eased between.
POINTER = [(0.0, AWAY), (0.35, AWAY), (1.15, NOTCH), (3.0, NOTCH), (3.6, TODAY_TAB), (4.15, TODAY_TAB),
           (4.75, CHECKBOX), (5.55, CHECKBOX), (6.2, AWAY), (9.0, AWAY)]
CLICKS = [1.2, 3.65, 4.8]
OPEN = (1.25, 1.95)       # spring open
TAB_SWITCH = (3.7, 3.95)  # Timer to Today
CHECK = 4.85
CLOSE = (6.05, 6.45)
HOPS = [6.75, 7.2, 7.65]
# (time, crop width in units, crop center x in units): the camera.
# Checking off the task pushes in on the list, its right edge in the gap
# before Up next; the cheer pushes in on the pet.
CAMERA = [(0.0, 1600, 1020), (0.45, 1600, 1020), (1.5, 1240, 1020), (3.85, 1240, 1020), (4.55, 800, 708),
          (5.7, 800, 708), (6.5, 1600, 1020), (6.6, 1600, 1020), (7.15, 720, 860), (8.1, 720, 860),
          (8.95, 1600, 1020), (9.0, 1600, 1020)]


def keyframed(keys, t):
    for (t0, *a), (t1, *b) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            p = ease((t - t0) / (t1 - t0)) if t1 > t0 else 1
            return [lerp(u, v, p) for u, v in zip(_flat(a), _flat(b))]
    return _flat(keys[-1][1:])


def _flat(values):
    out = []
    for v in values:
        out.extend(v if isinstance(v, tuple) else [v])
    return out


def openness(t):
    if t < OPEN[0]:
        return 0.0
    if t < OPEN[1]:
        return spring(phase(t, *OPEN))
    if t < CLOSE[0]:
        return 1.0
    return 1 - ease(phase(t, *CLOSE)) if t < CLOSE[1] else 0.0


def panel(t, timer, today):
    """The open panel's content at time t."""
    if t < TAB_SWITCH[0]:
        return timer[4 if t < 2.4 else 3 if t < 3.4 else 2]
    seconds = 12 if t < 4.4 else 11 if t < 5.4 else 10
    checked = today['checked'][seconds] if t >= CHECK else today['plain'][seconds]
    if t >= CHECK:
        checked = checked.copy()
        plain = today['plain'][seconds]
        # The check pops in with a spring, the strike draws left to right.
        p = spring(phase(t, CHECK, CHECK + 0.45))
        x0, y0, x1, y1 = today['check_box']
        box = checked.crop((x0, y0, x1, y1))
        if p < 1:
            under = plain.crop((x0, y0, x1, y1))
            size = max(1, int((x1 - x0) * (0.4 + 0.6 * p)))
            small = box.resize((size, size), Image.LANCZOS)
            under.alpha_composite(small, ((x1 - x0 - size) // 2, (y1 - y0 - size) // 2))
            checked.paste(under, (x0, y0))
            fade = ease(phase(t, CHECK, CHECK + 0.3))
            tx = (px(170), px(272), px(445), px(312))
            checked.paste(Image.blend(plain.crop(tx), checked.crop(tx), fade), tx[:2])
        s = ease(phase(t, CHECK + 0.05, CHECK + 0.35))
        sx0, sy0, sx1, sy1 = today['strike']
        if s > 0:
            d = ImageDraw.Draw(checked)
            d.rectangle((sx0, sy0, sx0 + (sx1 - sx0) * s, sy1 - 1), fill=(218, 218, 218, 255))
    else:
        checked = today['plain'][seconds]
    if t < TAB_SWITCH[1]:
        return Image.blend(timer[2], checked, ease(phase(t, *TAB_SWITCH)))
    return checked


def notch_layer(t, timer, today, idle, cheer):
    """The notch and panel in snapshot pixels (1200 x 520 units)."""
    p = openness(t)
    if p >= 1:
        return panel(t, timer, today)
    hopping = HOPS[0] - 0.05 <= t < HOPS[-1] + 0.5
    closed = cheer if hopping else idle
    if p <= 0:
        layer = closed.copy()
    else:
        mask = notch_shape(p)
        layer = Image.new('RGBA', closed.size, (0, 0, 0, 0))
        black = Image.new('RGBA', mask.size, (0, 0, 0, 255))
        layer.paste(black, (0, 0), mask)
        content = panel(t if t >= OPEN[0] and t < CLOSE[0] else min(t, OPEN[1]), timer, today) \
            if t < CLOSE[0] else panel(CLOSE[0] - 0.01, timer, today)
        scale = 0.82 + 0.18 * clamp(p, 0, 1.1)
        cw, ch = int(content.width * scale), int(content.height * scale)
        scaled = content.resize((cw, ch), Image.LANCZOS)
        placed = Image.new('RGBA', closed.size, (0, 0, 0, 0))
        placed.paste(scaled, ((closed.width - cw) // 2, 0))
        alpha = np.asarray(placed.getchannel('A')).astype(float) * clamp((p - 0.35) / 0.5)
        alpha = np.minimum(alpha, np.asarray(mask.crop((0, 0) + closed.size)).astype(float))
        placed.putalpha(Image.fromarray(alpha.astype(np.uint8)))
        layer.alpha_composite(placed)
        fade = clamp(1 - p / 0.3)
        if fade > 0:
            wing = closed.copy()
            wing.putalpha(Image.fromarray((np.asarray(wing.getchannel('A')) * fade).astype(np.uint8)))
            layer.alpha_composite(wing)
    if hopping:
        # Hop the pet inside the wing: three small spring hops.
        lift = 0.0
        for start in HOPS:
            q = phase(t, start, start + 0.42)
            if 0 < q < 1:
                lift = math.sin(math.pi * q) * 5
        x0, y0, x1, y1 = px(334), px(4), px(390), px(60)
        pet = layer.crop((x0, y0, x1, y1))
        ImageDraw.Draw(layer).rectangle((x0, y0, x1 - 1, y1 - 1), fill=(0, 0, 0, 255))
        layer.alpha_composite(pet, (x0, y0 - px(lift)))
        ImageDraw.Draw(layer).rectangle((x0, 0, x1 - 1, px(3)), fill=(0, 0, 0, 255))
    return layer


def frame(t, base, timer, today, idle, cheer, particles):
    world = base.copy()
    layer = notch_layer(t, timer, today, idle, cheer)
    # The panel's soft shadow on the wallpaper, as on the page.
    a = np.asarray(layer.getchannel('A').reduce(4)).astype(float)
    shadow = gaussian_filter(a, 18 * K / 4) * 0.55
    shadow_im = Image.fromarray(shadow.clip(0, 255).astype(np.uint8)).resize(layer.size, Image.BILINEAR)
    dark = Image.new('RGBA', layer.size, (58, 30, 12, 255))
    dark.putalpha(shadow_im)
    ox = px(SNAP_X)
    world.alpha_composite(dark, (ox, px(14)))
    world.alpha_composite(layer, (ox, 0))
    for start, x, y, vx, vy, size, color, spin in particles:
        age = t - start
        if not 0 <= age < 1.1:
            continue
        drag = (1 - math.exp(-3 * age)) / 3
        sx = x + vx * drag
        sy = y + vy * drag + 60 * age ** 2
        fade = 1 - ease(clamp((age - 0.55) / 0.55))
        grow = spring(clamp(age / 0.3))
        sp = sparkle(px(size * grow), color, spin + age * 2)
        sp.putalpha(Image.fromarray((np.asarray(sp.getchannel('A')) * fade).astype(np.uint8)))
        world.alpha_composite(sp, (px(SNAP_X + sx) - sp.width // 2, px(sy) - sp.height // 2))
    width, center = keyframed(CAMERA, t)
    left = clamp(center - width / 2, 0, WORLD_W - width)
    box = (px(left), 0, px(left + width), px(width * OUT_H / OUT_W))
    out = world.crop(box).resize((OUT_W, OUT_H), Image.LANCZOS)
    # The pointer, in the camera's scale.
    zoom = OUT_W / width
    x, y = keyframed(POINTER, t)
    press = max((math.sin(math.pi * phase(t, c - 0.06, c + 0.12)) for c in CLICKS), default=0)
    draw_pointer(out, (SNAP_X + x - left) * zoom, y * zoom, 38 * zoom, press)
    return out.convert('RGB')


def render_snapshots():
    folder = Path(tempfile.mkdtemp(prefix='tabbi-hero-'))
    env = dict(os.environ, TABBI_DEMO='1')
    subprocess.run(['swift', 'run', 'Tabbi', '--snapshot', str(folder), '--scale', str(SCALE), '--transparent'],
                   cwd=ROOT, env=env, check=True)
    return folder


def main():
    snaps = Path(sys.argv[1]) if len(sys.argv) > 1 else render_snapshots()
    if Image.open(snaps / 'open-study.png').width != px(1200):
        raise SystemExit(f'render the snapshots with --scale {SCALE}')
    timer = timer_frames(snaps)
    today = today_frames(snaps)
    idle, cheer = load(snaps, 'closed-pet'), load(snaps, 'closed-pet-cheer')
    base = wallpaper().convert('RGBA')
    particles = bursts()
    frames = Path(tempfile.mkdtemp(prefix='tabbi-hero-frames-'))
    count = int(SECONDS * FPS)
    for i in range(count):
        frame(i / FPS, base, timer, today, idle, cheer, particles).save(frames / f'{i:04d}.png')
    pattern = str(frames / '%04d.png')
    ff = ['ffmpeg', '-v', 'error', '-y', '-framerate', str(FPS), '-i', pattern]
    subprocess.run(ff + ['-c:v', 'libx264', '-preset', 'veryslow', '-crf', '23', '-tune', 'animation',
                         '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', str(IMG / 'hero.mp4')], check=True)
    subprocess.run(ff + ['-vf', 'fps=15,scale=600:-1:flags=lanczos', '-c:v', 'libwebp_anim', '-quality', '70',
                         '-loop', '0', '-an', str(IMG / 'hero-fallback.webp')], check=True)
    # The poster: the Timer open and still, the frame reduced motion shows.
    poster = frame(2.2, base, timer, today, idle, cheer, particles)
    poster.save(IMG / 'hero-poster.webp', quality=88, method=6)
    shutil.rmtree(frames)
    for name in ('hero.mp4', 'hero-fallback.webp', 'hero-poster.webp'):
        print(f'{name}: {(IMG / name).stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
