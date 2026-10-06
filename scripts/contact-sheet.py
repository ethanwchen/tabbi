#!/usr/bin/env python3
"""Builds a before/after contact sheet from two snapshot folders.

Usage: scripts/contact-sheet.py BEFORE_DIR AFTER_DIR OUT.png NAME [NAME ...]

Each NAME is a snapshot file name without .png (for example
onboarding-modules). Every name becomes one row: the before shot on the
left, the after shot on the right, both at 1x so the sheet stays small.
Needs Pillow.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GAP = 16
LABEL = 28
BACKGROUND = (28, 28, 30)
TEXT = (235, 235, 240)
MUTED = (160, 160, 168)


def font(size):
    for path in ("/System/Library/Fonts/SFNSRounded.ttf", "/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    before_dir, after_dir, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    names = sys.argv[4:]
    pairs = []
    for name in names:
        before = Image.open(before_dir / f"{name}.png").convert("RGB")
        after = Image.open(after_dir / f"{name}.png").convert("RGB")
        before = before.resize((before.width // 2, before.height // 2), Image.LANCZOS)
        after = after.resize((after.width // 2, after.height // 2), Image.LANCZOS)
        pairs.append((name, before, after))

    column = max(max(b.width, a.width) for _, b, a in pairs)
    width = GAP * 3 + column * 2
    height = GAP + LABEL + sum(LABEL + max(b.height, a.height) + GAP for _, b, a in pairs)
    sheet = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    heading, caption = font(15), font(12)
    draw.text((GAP, GAP), "Before", font=heading, fill=TEXT)
    draw.text((GAP * 2 + column, GAP), "After", font=heading, fill=TEXT)
    y = GAP + LABEL
    for name, before, after in pairs:
        draw.text((GAP, y + 6), name, font=caption, fill=MUTED)
        y += LABEL
        sheet.paste(before, (GAP, y))
        sheet.paste(after, (GAP * 2 + column, y))
        y += max(before.height, after.height) + GAP
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, optimize=True)


if __name__ == "__main__":
    main()
