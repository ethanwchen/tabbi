"""Turn the app's tab screenshots in docs/images into the home page's tab images.

The renders sit on a navy wallpaper, which clashes with the site's brown.
This makes the wallpaper transparent, so only the black notch panel shows on
the card: wallpaper is the blue-tinted area that touches the image edge, and
the 2 px rim beside the panel becomes black at a matching alpha, so the edge
stays smooth. Run it from the repo root: python3 site/_tab_shots.py
"""
import numpy as np
from PIL import Image
from scipy import ndimage

SHOTS = [('study', 'timer'), ('today', 'today'), ('closet', 'closet'), ('party', 'party')]

for src, dst in SHOTS:
    a = np.array(Image.open(f'docs/images/{src}.png').convert('RGBA')).astype(float)
    rgb, alpha = a[..., :3], a[..., 3]
    bluish = ((rgb[..., 2] > 40) & (rgb[..., 2] > rgb[..., 0] + 20)) | (alpha < 255)
    labels, _ = ndimage.label(bluish)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    wall = np.isin(labels, edge[edge > 0])
    panel = ~wall
    rim = wall & ndimage.binary_dilation(panel, iterations=2)
    # How much darker than the nearby wallpaper a rim pixel is says how much panel it holds.
    nearby = ndimage.maximum_filter(np.where(wall, rgb[..., 2], 0), size=7)
    rim_alpha = np.clip(1 - rgb[..., 2] / np.maximum(nearby, 1), 0, 1) * 255
    alpha = np.where(rim, rim_alpha, np.where(panel, alpha, 0.0))
    out = np.dstack([np.where(rim[..., None], 0, rgb), alpha]).astype(np.uint8)
    im = Image.fromarray(out, 'RGBA')
    im.save(f'site/img/{dst}.webp', quality=92, method=6)
    im.resize((680, 260), Image.LANCZOS).save(f'site/img/{dst}-680.webp', quality=92, method=6)
    print('wrote', dst)
