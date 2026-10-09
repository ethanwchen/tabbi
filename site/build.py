"""Generate the site into dist/. Standard library only.

    python3 site/build.py           build
    python3 site/build.py --serve   build, then serve dist/ the way Cloudflare Pages does
"""

import hashlib
import http.server
import json
import pathlib
import re
import shutil
import sys
import zipfile
from html.parser import HTMLParser

from _partials import page, download_button, PAW, DOWNLOAD, GITHUB, ISSUES, ORIGIN, SUPPORT_EMAIL
from _legal import PRIVACY, PRIVACY_HERO, TERMS, TERMS_HERO

HERE = pathlib.Path(__file__).parent
# Built into its own directory so a deploy uploads pages and assets only,
# never build.py or _legal.py.
OUT = HERE / 'dist'


EMAIL_RE = re.compile(
    r'(<a href="mailto:[^"]+">[^<]*</a>)'
    r'|([a-z][a-z0-9._-]*@tabbinotch\.com)'
)


def unobfuscate(html):
    """Stop Cloudflare rewriting the contact address.

    Cloudflare's Email Address Obfuscation turns every address into
    `[email protected]` and injects a script to decode it. The CSP in
    _headers is `default-src 'none'`, so that script never runs and the
    address stays unreadable. The privacy policy names this address as the
    way to exercise your rights, so it has to be readable.
    `<!--email_off-->` is Cloudflare's documented directive for this; it lives
    in the build so a dashboard toggle cannot silently break it.
    """
    return EMAIL_RE.sub(lambda m: '<!--email_off-->%s<!--/email_off-->' % m.group(0), html)


# --------------------------------------------------------------------------
# Home
# --------------------------------------------------------------------------

# (image, label, name, line, alt). The screenshots are the app's own snapshot
# renders from docs/images, so the site shows exactly what the app draws.
TABS = [
    ('timer', 'Timer', 'Timer', 'Pomodoro and quick timers, with focus sounds.',
     'The Timer tab: a Pomodoro ring at 15:14 with focus sounds and today\'s total'),
    ('today', 'Today', 'Today', 'Your to-dos and what is next on the calendar.',
     'The Today tab: a checklist on the left and upcoming meetings on the right'),
    ('closet', 'Closet', 'Closet', 'Dress up your cat with the points you earn.',
     'The Closet: a pixel cat with costumes and accessories to choose from'),
    ('party', 'Party', 'Party', 'Study with friends, pets side by side.',
     'The Party tab: friends\' pets sitting together with their study status'),
]

# How wide a tab screenshot draws: one column under 600 px, two under 1000,
# then four. The card crops the image to 1120 of its 1360 px, so each width
# is scaled up by that 1.21 to ask for enough pixels.
TAB_SIZES = '(max-width: 600px) calc(121vw - 60px), (max-width: 1000px) calc(60vw - 50px), 300px'

HOME_HERO = {
    'home': True,
    'title': 'A little cat for your notch.',
    'subtitle': 'A cozy panel of tabs in your laptop notch.',
    'cta': f'''<div class="cta">{download_button()}</div>
        <p class="cta-note">Free, macOS 14+</p>''',
    'eyebrow': '<img class="hero-icon" src="/img/icon-256.webp" width="256" height="256" alt="The Tabbi app icon: a cream British Shorthair cat with blue eyes on a golden yellow square">',
    # A drawn laptop with the real Timer panel hanging from its notch.
    # notch-timer.webp is timer.webp cropped to the panel (see README).
    # pixel-cat.png is the app's gray tabby sprite, sitting and blinking.
    'art': '''<div class="laptop">
        <span class="pixel-cat" aria-hidden="true"></span>
        <div class="laptop-screen">
          <img class="laptop-panel" src="/img/notch-timer.webp" width="880" height="376" alt="Tabbi open in a laptop notch on its Timer tab: a Pomodoro ring at 15:14 with focus sounds">
        </div>
        <div class="laptop-base"></div>
      </div>''',
}

HOME = f'''
      <section class="tabs" aria-labelledby="tabs-title">
        <h2 id="tabs-title" class="tabs-title">{PAW}<span>Click the notch, pick a tab</span></h2>
        <div class="tab-row">
''' + '\n'.join(f'''          <figure class="tab-card">
            <span class="tab-label" aria-hidden="true">{label}</span>
            <img src="/img/{img}.webp" srcset="/img/{img}-680.webp 680w, /img/{img}.webp 1360w" sizes="{TAB_SIZES}" width="1360" height="520" loading="lazy" decoding="async" alt="{alt}">
            <figcaption><strong>{name}</strong>{line}</figcaption>
          </figure>''' for img, label, name, line, alt in TABS) + '''
        </div>
        <p class="more">And more fun tabs inside.</p>
        <div class="card-pair">
          <a class="gh-card" href="''' + GITHUB + '''">
            <img class="gh-cat" src="/img/glyph.png" width="56" height="56" alt="">
            <svg class="gh-mark" viewBox="0 0 16 16" width="26" height="26" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
            <span class="gh-text"><strong>Open source on GitHub</strong><span>Free forever. Come say hi or leave a star.</span></span>
            <span class="gh-arrow" aria-hidden="true">&rarr;</span>
          </a>
          <a class="gh-card coffee-card" href="https://buymeacoffee.com/ethanpolar">
            <svg class="coffee-mark" viewBox="0 0 32 32" width="30" height="30" aria-hidden="true">
              <g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <path class="steam s1" d="M11 4c-1.2 1.4 1.2 2.6 0 4"/>
                <path class="steam s2" d="M16 3c-1.2 1.4 1.2 2.6 0 4"/>
                <path class="steam s3" d="M21 4c-1.2 1.4 1.2 2.6 0 4"/>
                <path d="M6 12h19v7a7 7 0 0 1-7 7h-5a7 7 0 0 1-7-7z"/>
                <path d="M25 14h1.5a3.5 3.5 0 0 1 0 7H25"/>
              </g>
            </svg>
            <span class="gh-text"><strong>Buy me a coffee</strong><span>Tabbi is free. A coffee keeps it purring.</span></span>
            <span class="gh-arrow" aria-hidden="true">&rarr;</span>
          </a>
        </div>
      </section>
'''


# Structured data for search engines. A script of type application/ld+json
# is a data block: browsers never run it, so the CSP's default-src 'none'
# does not block it (the preview server sends the same CSP, so a violation
# would show up in the console).
SOFTWARE_APP = {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    'name': 'Tabbi',
    'description': 'A cozy panel of tabs in your laptop notch: a focus timer, your day, music, Claude, Anki and a pet cat.',
    'url': ORIGIN + '/',
    'image': ORIGIN + '/img/icon-256.webp',
    'screenshot': ORIGIN + '/img/social-preview.png',
    'applicationCategory': 'ProductivityApplication',
    'operatingSystem': 'macOS 14 or later',
    'downloadUrl': DOWNLOAD,
    'softwareHelp': ORIGIN + '/support',
    'isAccessibleForFree': True,
    'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
    'author': {'@type': 'Person', 'name': 'Ethan', 'url': ORIGIN + '/about'},
}


def json_ld(data):
    # "<" is escaped so no string in the data can close the script element.
    text = json.dumps(data, indent=2).replace('<', '\\u003c')
    return '\n  <script type="application/ld+json">\n' + text + '\n  </script>'


# --------------------------------------------------------------------------
# Support
# --------------------------------------------------------------------------

def faq(question, answer, anchor):
    return f'''      <details class="faq" id="{anchor}">
        <summary>{question}</summary>
        <div class="faq-body">
{answer}
        </div>
      </details>'''


SUPPORT = f'''
      <div class="card contact">
        <h2>Contact</h2>
        <p>Email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>.
          A person reads every message, usually within a few days.
          It helps to say which Mac and macOS version you have, which Tabbi version (right-click the notch, then <strong>Settings &gt; About</strong>), and what you were doing.</p>
        <p>Found a bug or have an idea? <a href="{ISSUES}">Open an issue on GitHub</a>.
          Please report security problems privately by email rather than in a public issue.</p>
      </div>

      <h2>Common questions</h2>

{faq('How do I install Tabbi?', f"""          <ol>
            <li>Download <strong>Tabbi-&lt;version&gt;.dmg</strong> from the <a href="{DOWNLOAD}">latest release</a>.</li>
            <li>Open it and drag <strong>Tabbi</strong> onto the <strong>Applications</strong> folder.</li>
            <li>Open Tabbi from Applications. macOS asks once whether to open an app downloaded from the Internet: click <strong>Open</strong>.</li>
          </ol>
          <p>Tabbi has no Dock icon and no menu bar item. Move the pointer to the notch and click it.
            The first time, a short welcome inside the notch helps you pick your tabs.</p>
          <p>With Homebrew you can run <code>brew install --cask ethanwchen/tap/tabbi</code> instead.</p>""", 'install')}

{faq('macOS says it cannot verify Tabbi, or will not open it', """          <p>Releases downloaded from GitHub are signed by the developer and notarized by Apple, so they open normally.
            The warning appears only for a copy built without a Developer ID, such as a test build.
            To open one anyway:</p>
          <ol>
            <li>Open Tabbi. When macOS stops it, click <strong>Done</strong> (not Move to Trash).</li>
            <li>Open <strong>System Settings &gt; Privacy &amp; Security</strong>, scroll to <strong>Security</strong>, and click <strong>Open Anyway</strong> next to Tabbi. The button shows for about an hour after step 1.</li>
            <li>Enter your Mac password, then click <strong>Open</strong>.</li>
          </ol>
          <p>If macOS says Tabbi is damaged, the download was cut short. Move it to the Trash and download it again.</p>""", 'gatekeeper')}

{faq('How do I quit Tabbi?', """          <p>Right-click the notch and choose <strong>Quit Tabbi</strong>.
            The same menu has <strong>Settings</strong> and <strong>Check for Updates</strong>.</p>
          <p>Tabbi opens at login by default. To stop that, turn off <strong>Launch at login</strong> in <strong>Settings &gt; General</strong>.</p>""", 'quit')}

{faq('Can I make the panel bigger or smaller?', """          <p>Yes. Right-click the notch, choose <strong>Settings</strong>, and pick a <strong>Panel size</strong> in <strong>General</strong>:
            Compact, Regular or Large. Every tab uses the same size, so switching tabs never jumps.</p>
          <p>In the same place you can turn on <strong>Open on hover</strong>, hide the notch in fullscreen apps, and choose which display it appears on.</p>""", 'resize')}

{faq('How do friend codes work in Party?', """          <p>Party is an optional tab: add it from <strong>Settings &gt; Tabs &gt; Add more</strong>.
            When you turn it on, Tabbi gives you an 8-character <strong>friend code</strong>. Copy it from the Party tab and send it to a friend. Once they add it, you see each other.
            Friendship is always mutual, and nobody can find you without your code: there is no directory or search.</p>
          <p>To study together, one of you starts a party and shares its 6-character party code. Anyone with that code can join while there is room, so share it only with people you want to study with.</p>
          <p>Want a break from being seen? Turn on <strong>Go invisible</strong> in the Party options and friends see you as offline.</p>""", 'party')}

{faq('Do I need an account? How do I sync my pet across Macs?', """          <p>No. Everything in Tabbi works without an account.
            If you use Tabbi on more than one Mac, you can choose <strong>Sign in with Apple</strong> in <strong>Settings &gt; General</strong> on each of them.
            Your pet, points, unlocked items and streaks then sync between them, and your Party friend code and friends follow you.</p>
          <p>Tabbi asks Apple only for your name, which stays on your Mac, never your email.
            Your calendar, tasks, activity history, Claude chats and settings are never synced.
            Signing in on a Mac that already has progress adds it to your account; nothing is overwritten.
            <strong>Sign Out</strong> stops syncing on that Mac and keeps your pet there.
            The <a href="/privacy#account">privacy policy</a> lists exactly what the account stores.</p>""", 'account')}

{faq('How do I delete my account or my Party data?', f"""          <p>Party keeps only a nickname, your pet's look, your study status and minutes, your friend list and your party. It never has your email or real name. See the <a href="/privacy#friends">privacy policy</a> for the full list and <a href="/privacy#deleting">Deleting your data</a> for every option.</p>
          <ul>
            <li><strong>Leave a party</strong> from the Party tab. A party is deleted when its last member leaves, or after 12 hours without activity.</li>
            <li><strong>Remove a friend</strong> from their card in the Party tab. That deletes the friendship on both sides.</li>
            <li><strong>Delete your Party data</strong>: without an account, open <strong>Settings open <strong>Settings &gt; Party</strong> and choose <strong>Delete my Party data</strong>gt; Tabs</strong>, click <strong>Options</strong> next to Party, and choose <strong>Delete my Party data</strong>. Your profile, status, study minutes, friend list and party are erased from the server at once, and your pet stays on your Mac.</li>
            <li><strong>Delete your account</strong>: when signed in with Apple, open <strong>Settings &gt; General</strong> and choose <strong>Delete Account</strong>. That erases your Party data, your synced pet and progress, and your Apple link from the server, and revokes Tabbi's Sign in with Apple access. Your pet stays on the Mac you deleted from.</li>
            <li>Cannot open the app? Email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> with your friend code. To make sure the request is yours, we may ask you to change your Party nickname to a word we send you. We then delete the same data and confirm by email.</li>
          </ul>
          <p>Daily study minutes are deleted automatically after 28 days either way.</p>""", 'delete-party')}

{faq('Do I need Claude Code?', """          <p>No. Only Ask Claude, Claude Usage, and the optional Refine with Claude and Wrap up use it.
            Those tabs show a setup hint until the <code>claude</code> command is installed.
            Tabbi runs your own <code>claude</code> command, so your usage stays on the plan you already have and Tabbi never handles your credentials.</p>""", 'claude')}

{faq('How do I update or uninstall Tabbi?', f"""          <p>Tabbi checks for updates once a day and installs them in a few seconds. To check now, right-click the notch and choose <strong>Check for Updates</strong>.</p>
          <p>To uninstall, quit Tabbi and drag it from Applications to the Trash. Your tabs, tasks and settings stay in <code>~/Library/Application Support/Tabbi</code> in case you come back; delete that folder to remove them too.
            The <a href="{GITHUB}/blob/main/docs/install.md#uninstall">install guide</a> lists every folder.</p>""", 'uninstall')}
'''


# The press kit: the icon at 1024 px and the four tabs from the home page,
# as lossless PNGs, zipped by the build.
PRESS = HERE / 'press'
PRESS_KIT = 'tabbi-press-kit.zip'
PRESS_MB = f"{sum(f.stat().st_size for f in PRESS.glob('*.png')) / 1e6:.1f} MB"


ABOUT = f'''
      <div class="about">
        <img class="about-cat" src="/img/glyph.png" width="96" height="96" alt="">
        <p class="about-lead">Hi, it&rsquo;s Ethan.</p>
        <p>I made Tabbi because I wanted my study tools in one cozy spot, right where I already look: the notch.</p>
        <p>It&rsquo;s free and open source. No ads, no tracking, no account needed.</p>
        <p>If Tabbi helps you focus, a star or a coffee means a lot.</p>
        <div class="cta center">
          <a class="btn" href="https://buymeacoffee.com/ethanpolar">Buy me a coffee</a>
          <a class="btn soft" href="{GITHUB}">Star on GitHub</a>
        </div>
        <div class="press" id="press">
          <h2>Press kit</h2>
          <p>Tabbi is a free, open source app for macOS 14 or later. It turns the laptop notch into a cozy panel of tabs: a focus timer, your day, music, Claude, Anki and a pet cat. Everything stays on your Mac. The kit has the icon and four screenshots.</p>
          <div class="cta center">
            <a class="btn soft" href="/press/{PRESS_KIT}" download>Download ({PRESS_MB} ZIP)</a>
          </div>
        </div>
      </div>
'''


NOT_FOUND = '''
      <div class="lost">
        <img src="/img/glyph.png" width="128" height="128" alt="">
        <p class="measure">That page is not here. It may have moved, or the link may have been wrong to begin with.</p>
        <div class="cta center">
          <a class="btn" href="/">Back to the start</a>
          <a class="btn soft" href="/support">Get help</a>
        </div>
      </div>
'''

pages = [
    ('index.html', 'Tabbi: a little cat for your notch',
     'Tabbi turns your laptop notch into a cozy panel of tabs: a focus timer, your day, music, Claude, Anki and a pet cat. Free and open source for macOS.',
     HOME, HOME_HERO, True, True),
    ('about.html', 'About | Tabbi',
     'Who makes Tabbi, and why.',
     ABOUT, {'title': 'About', 'subtitle': 'A small app made with care.'}, False, True),
    ('support.html', 'Support | Tabbi',
     'Help with installing and using Tabbi, answers to common questions, and how to reach a person.',
     SUPPORT, {'title': 'Support', 'subtitle': 'Answers to common questions, and how to reach a person.'}, False, True),
    ('privacy.html', 'Privacy Policy | Tabbi',
     'What Tabbi keeps on your Mac, what the optional friends service and account store, and how to delete them.',
     PRIVACY, {'title': PRIVACY_HERO[0], 'subtitle': PRIVACY_HERO[1]}, False, True),
    ('terms.html', 'Terms of Use | Tabbi',
     'The terms for using the Tabbi app and its optional friends service.',
     TERMS, {'title': TERMS_HERO[0], 'subtitle': TERMS_HERO[1]}, False, True),
    # Cloudflare Pages serves 404.html for anything it cannot find.
    ('404.html', 'Not found | Tabbi',
     'That page is not here.',
     NOT_FOUND, {'title': 'Nothing in this tab', 'subtitle': 'The cat looked everywhere and came back empty-pawed.'}, False, False),
]

# Extra <head> markup per page.
HEADS = {'index.html': json_ld(SOFTWARE_APP)}


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------

class Refs(HTMLParser):
    """Collects ids and every local href/src in a page."""

    def __init__(self):
        super().__init__()
        self.ids, self.refs = set(), []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a:
            self.ids.add(a['id'])
        for key in ('href', 'src'):
            value = a.get(key)
            if value and (value.startswith('/') or value.startswith('#')) and not value.startswith('//'):
                self.refs.append(value)


def resolve(path):
    """The file Cloudflare Pages would serve for `path`, or None."""
    rel = path.lstrip('/')
    candidates = [rel + 'index.html'] if rel.endswith('/') or rel == '' else [rel, rel + '.html']
    for c in candidates:
        if (OUT / c).is_file():
            return OUT / c
    return None


def check_links():
    """Every local link and asset must resolve, and every #anchor must exist.

    A broken link on a support or privacy page is a page App Review cannot
    reach, so a broken reference stops the build instead of shipping.
    """
    parsed = {}
    for html_file in OUT.glob('*.html'):
        p = Refs()
        p.feed(html_file.read_text())
        parsed[html_file] = p
    problems = []
    for html_file, p in parsed.items():
        for ref in p.refs:
            path, _, anchor = ref.partition('#')
            target = html_file if not path else resolve(path)
            if target is None:
                problems.append(f'{html_file.name}: {ref} does not exist')
                continue
            if anchor and target.suffix == '.html':
                ids = parsed[target].ids if target in parsed else set()
                if anchor not in ids:
                    problems.append(f'{html_file.name}: {ref} has no #{anchor}')
    if problems:
        raise SystemExit('broken links:\n  ' + '\n  '.join(sorted(set(problems))))


LD_RE = re.compile(r'<script type="application/ld\+json">(.*?)</script>', re.S)
SCRIPT_RE = re.compile(r'<script(?![^>]*type="application/ld\+json")[^>]*>')


def check_scripts():
    """No page may carry a script the CSP would block, and every JSON-LD
    block must parse and name its schema.org type."""
    for html_file in sorted(OUT.glob('*.html')):
        html = html_file.read_text()
        if SCRIPT_RE.search(html):
            raise SystemExit(f'{html_file.name}: has a script; the CSP blocks every script')
        for block in LD_RE.findall(html):
            try:
                data = json.loads(block)
            except ValueError as e:
                raise SystemExit(f'{html_file.name}: JSON-LD does not parse: {e}')
            if data.get('@context') != 'https://schema.org' or '@type' not in data:
                raise SystemExit(f'{html_file.name}: JSON-LD needs a schema.org @context and an @type')


# The whole home page should stay under about 600 KB. Google Fonts take
# about 150 KB of that, so the site's own files get the rest.
PAGE_BUDGET = 450 * 1024
ASSET_RE = re.compile(r'/(?:img|assets)/[A-Za-z0-9._-]+')
# Fetched only for link previews, search results or a home screen icon, not
# by the page.
NOT_LOADED_RE = re.compile(r'<meta [^>]*>|<link rel="apple-touch-icon"[^>]*>|<script type="application/ld\+json">.*?</script>', re.S)


def check_weight(stylesheet):
    """Every page, with its stylesheet and every image it can load (both
    sizes of a srcset, so this is a ceiling), must fit PAGE_BUDGET."""
    css = (OUT / stylesheet.lstrip('/')).read_text()
    css_assets = set(ASSET_RE.findall(css))
    report = []
    for html_file in sorted(OUT.glob('*.html')):
        html = html_file.read_text()
        assets = set(ASSET_RE.findall(NOT_LOADED_RE.sub('', html))) | css_assets
        total = len(html.encode()) + sum((OUT / a.lstrip('/')).stat().st_size for a in assets)
        report.append(f'{html_file.name} {total // 1024} KB')
        if total > PAGE_BUDGET:
            raise SystemExit(f'{html_file.name} loads {total // 1024} KB of the site\'s own files; the budget is {PAGE_BUDGET // 1024} KB')
    print('page weight:', ', '.join(report))


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

def unhashed(text):
    """Asset references that kept their plain name: files that did not exist
    when the fingerprints were built."""
    return sorted({m for m in ASSET_RE.findall(text) if len(m.rsplit('/', 1)[1].split('.')) < 3})


def fingerprint(src, folder, data=None):
    data = src.read_bytes() if data is None else data
    digest = hashlib.sha256(data).hexdigest()[:8]
    hashed = f'{src.stem}.{digest}{src.suffix}'
    (OUT / folder).mkdir(exist_ok=True)
    (OUT / folder / hashed).write_bytes(data)
    return f'/{folder}/{hashed}'


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()

    # Content-hashed names. _headers serves /img/* and /assets/* as
    # `immutable`, a promise that a URL's bytes never change; putting the
    # hash in the name makes that promise true.
    fingerprints = {}
    for src in sorted((HERE / 'img').iterdir()):
        if src.suffix in ('.png', '.gif', '.jpg', '.webp', '.svg'):
            fingerprints['/img/' + src.name] = fingerprint(src, 'img')

    def asset_sub(text):
        asset_re = re.compile('|'.join(re.escape(k) for k in sorted(fingerprints, key=len, reverse=True)))
        return asset_re.sub(lambda m: fingerprints[m.group(0)], text)

    # The stylesheet points at images too (the paper grain), so its image
    # URLs are hashed first and its own hash covers them.
    css = asset_sub((HERE / 'styles.css').read_text())
    if unhashed(css):
        raise SystemExit('styles.css: references files that do not exist: ' + ', '.join(unhashed(css)))
    fingerprints['/styles.css'] = fingerprint(HERE / 'styles.css', 'assets', css.encode())

    for slug, title, description, body, hero, wide, indexable in pages:
        html = unobfuscate(page(slug, title, description, body, hero, wide, indexable, HEADS.get(slug, '')))
        html = asset_sub(html)

        # A missing image should stop a build.
        if unhashed(html):
            raise SystemExit(f'{slug}: references files that do not exist: ' + ', '.join(unhashed(html)))

        (OUT / slug).write_text(html)
        print('wrote', slug)

    shutil.copy(HERE / '_headers', OUT / '_headers')
    shutil.copy(HERE / 'favicon.ico', OUT / 'favicon.ico')
    write_press_kit()
    (OUT / 'robots.txt').write_text('User-agent: *\nAllow: /\n\nSitemap: https://tabbinotch.com/sitemap.xml\n')
    urls = ''.join(
        f'  <url><loc>https://tabbinotch.com/{"" if slug == "index.html" else slug.removesuffix(".html")}</loc></url>\n'
        for slug, *_rest, indexable in pages if indexable
    )
    (OUT / 'sitemap.xml').write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + urls + '</urlset>\n'
    )

    check_links()
    check_scripts()
    check_weight(fingerprints['/styles.css'])

    biggest = max((f for f in OUT.rglob('*') if f.is_file()), key=lambda f: f.stat().st_size)
    if biggest.stat().st_size > 20 * 1024 * 1024:
        raise SystemExit(f'{biggest} is over 20 MB; Cloudflare Pages refuses files over 25 MB')
    print('copied _headers, favicon.ico, robots.txt, sitemap.xml, the press kit and %d fingerprinted assets' % len(fingerprints))


def write_press_kit():
    """Zips site/press into one download. PNGs are already compressed, so
    they are stored, and fixed timestamps keep the zip's bytes stable."""
    (OUT / 'press').mkdir()
    with zipfile.ZipFile(OUT / 'press' / PRESS_KIT, 'w', zipfile.ZIP_STORED) as z:
        for src in sorted(PRESS.glob('*.png')):
            info = zipfile.ZipInfo(f'tabbi-press-kit/{src.name}', (2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16  # readable files once unzipped
            z.writestr(info, src.read_bytes())


def site_headers():
    """The `/*` block of _headers as (name, value) pairs."""
    pairs, in_block = [], False
    for line in (HERE / '_headers').read_text().splitlines():
        if line and not line[0].isspace():
            in_block = line.strip() == '/*'
        elif in_block and ':' in line:
            name, value = line.strip().split(':', 1)
            pairs.append((name, value.strip()))
    return pairs


SITE_HEADERS = site_headers()


class PagesHandler(http.server.SimpleHTTPRequestHandler):
    """Serves dist/ with Cloudflare Pages' rules: /support finds support.html,
    and anything missing gets 404.html with a 404 status."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(OUT), **kwargs)

    def end_headers(self):
        # The headers _headers sets for every path, CSP included, so a
        # preview fails the same way production would.
        for name, value in SITE_HEADERS:
            self.send_header(name, value)
        super().end_headers()

    def send_head(self):
        path = self.path.split('?', 1)[0].split('#', 1)[0]
        target = resolve(path)
        if target is None:
            body = (OUT / '404.html').read_bytes()
            self.send_response(404)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return None
        self.path = '/' + str(target.relative_to(OUT))
        return super().send_head()


if __name__ == '__main__':
    build()
    if '--serve' in sys.argv:
        port = 8765
        print(f'serving http://localhost:{port}')
        http.server.ThreadingHTTPServer(('127.0.0.1', port), PagesHandler).serve_forever()
