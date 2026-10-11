"""The home page's download figure ("10,000+ downloads"), read when the site builds.

The friends backend adds GitHub's DMG downloads to the App Store units the
maintainer stores and answers with only a rounded milestone
(GET /v1/public/downloads, see docs/study/backend-api.md#downloads-maintainer).
The build asks once and writes the line into the page, so visitors' browsers
fetch nothing (the CSP allows no connections) and the site keeps its one
script. The figure moves in big steps, so refreshing it on each deploy is
enough.

Below 10,000, or when the backend cannot be reached, the line is left out and
the build goes on. TABBI_DOWNLOADS overrides the figure for a preview:
a number (`TABBI_DOWNLOADS=12345 python3 site/build.py --serve`) is rounded
the way the backend rounds it, and `off` skips the request.
"""

import json
import os
import sys
import urllib.request

from _partials import BACKEND

DOWNLOADS_URL = BACKEND + '/v1/public/downloads'
# Below this the page shows nothing; matches DOWNLOAD_MILESTONE_MIN in backend/src/downloads.ts.
MILESTONE_MIN = 10_000
TIMEOUT_S = 5


def milestone(total):
    """The largest of 10,000, 25,000, 50,000, 100,000, 250,000... that `total` reaches, else 0.

    The same steps as downloadMilestone in backend/src/downloads.ts, so a
    forced preview value shows what the backend would send.
    """
    if not isinstance(total, int) or isinstance(total, bool) or total < MILESTONE_MIN:
        return 0
    best = MILESTONE_MIN
    power = MILESTONE_MIN
    while power <= total:
        for step in (1, 2.5, 5):
            if power * step <= total:
                best = int(power * step)
        power *= 10
    return best


def fetch_milestone(url=DOWNLOADS_URL, opener=urllib.request.urlopen):
    """The backend's milestone, or 0 (with a note on stderr) when it cannot be read."""
    try:
        request = urllib.request.Request(url, headers={'Accept': 'application/json', 'User-Agent': 'tabbi-site-build'})
        with opener(request, timeout=TIMEOUT_S) as response:
            data = json.loads(response.read(4096))
        value = data.get('milestone') if isinstance(data, dict) else None
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ValueError(f'no milestone in {data!r:.80}')
        # Rounded again, so an odd reply can never put an exact figure on the page.
        return milestone(value)
    except Exception as e:  # noqa: BLE001 - any failure just leaves the line out
        print(f'note: no download count ({e}); the home page leaves the line out', file=sys.stderr)
        return 0


def current_milestone(env=os.environ):
    forced = env.get('TABBI_DOWNLOADS', '').strip()
    if forced == 'off':
        return 0
    if forced:
        return milestone(int(forced))
    return fetch_milestone()


def downloads_note(value):
    """The words beside "Free, macOS 14+", or '' below the threshold."""
    if value < MILESTONE_MIN:
        return ''
    return f'<span class="downloads"> <span class="sep" aria-hidden="true">&middot;</span> {value:,}+ downloads</span>'
