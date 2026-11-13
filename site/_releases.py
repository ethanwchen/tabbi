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
    ('1.0.6', 'Study Crews and the Heirloom shelf',
     'Study Crews: study together, race for the weekly top 3 and earn medals for your crest. Plus fifteen new outfits and an Heirloom shelf of long goals.'),
    ('1.0.5', 'Goals and badges',
     'Forty-eight badges from Bronze to Starlight, sixteen mastery outfits you earn instead of buy, monthly quests, and a widget that never goes blank.'),
    ('1.0.4', 'Party everywhere',
     'The App Store version gets Party, AI Usage and Do Not Disturb, and Party speaks every language Tabbi does.'),
    ('1.0.3', 'Kinder permissions',
     'Sign in without a birthday, clearer Continue or Not now steps before macOS asks for access, and a sign-in fix.'),
    ('1.0.2', 'Break Buddy and sweet themes',
     'Your pet takes a short break with you, ten new themes like Strawberry Milk and Deep Sea, the British Longhair, and a lighter app.'),
    ('1.0.1', 'Friend requests',
     'Accept or decline friend requests, every hat now shows in Party, and smoother birthday and focus sound controls.'),
    ('1.0.0', 'The first release',
     'Tabbi moves into your notch: a focus timer, your day, music, study parties with friends, and a cat to dress up.'),
]

if RELEASES[0][0] != VERSION:
    raise SystemExit(f'_releases.py: Info.plist says {VERSION}, but the newest release listed is {RELEASES[0][0]}')
