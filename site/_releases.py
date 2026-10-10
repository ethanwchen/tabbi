"""The version tag beside the logo and the What's New page.

VERSION is read from the app's own Info.plist, so the site never names a
version the app does not have. RELEASES says what each version brought, one
sentence each, newest first; the build stops when the newest entry is not
VERSION, so a version bump needs its line here before the site can ship.
"""

import pathlib
import plistlib

with open(pathlib.Path(__file__).parent.parent / 'Resources' / 'Info.plist', 'rb') as _f:
    VERSION = plistlib.load(_f)['CFBundleShortVersionString']

# (version, when, one sentence). Keep each line short and warm: the details
# live in the GitHub release notes, which the page links to.
RELEASES = [
    ('0.1.0', 'The first release',
     'Tabbi moves into your notch: a focus timer, your day, music, study parties with friends, and a cat to dress up.'),
]

if RELEASES[0][0] != VERSION:
    raise SystemExit(f'_releases.py: Info.plist says {VERSION}, but the newest release listed is {RELEASES[0][0]}')
