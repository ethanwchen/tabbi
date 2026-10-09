"""Generate the site into dist/. Standard library only.

    python3 site/build.py           build
    python3 site/build.py --serve   build, then serve dist/ the way Cloudflare Pages does
"""

import hashlib
import http.server
import pathlib
import re
import shutil
import sys
from html.parser import HTMLParser

from _partials import page, download_button, PAW, DOWNLOAD, GITHUB, ISSUES, SUPPORT_EMAIL
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

# (image, name, line, alt). The screenshots are the app's own snapshot
# renders from docs/images, so the site shows exactly what the app draws.
TABS = [
    ('timer', 'Timer', 'Pomodoro and quick timers, with focus sounds.',
     'The Timer tab: a Pomodoro ring at 15:14 with focus sounds and today\'s total'),
    ('today', 'Today', 'Your to-dos and what is next on the calendar.',
     'The Today tab: a checklist on the left and upcoming meetings on the right'),
    ('closet', 'Closet', 'Dress up your cat with the points you earn.',
     'The Closet: a pixel cat with costumes and accessories to choose from'),
    ('party', 'Party', 'Study with friends, pets side by side.',
     'The Party tab: friends\' pets sitting together with their study status'),
]

HOME_HERO = {
    'home': True,
    'title': 'A little cat for your notch.',
    'subtitle': 'Tabbi turns your MacBook notch into a cozy panel of tabs for focus, your day, music and study.',
    'cta': f'''<div class="cta">{download_button()}</div>
        <p class="cta-note">Free, macOS 14+</p>''',
    'art': '''<div class="hero-art">
        <img src="/img/icon-512.webp" width="512" height="512" alt="The Tabbi app icon: a cream British Shorthair cat with blue eyes on a golden yellow square">
      </div>''',
}

HOME = f'''
      <section class="tabs" aria-labelledby="tabs-title">
        <h2 id="tabs-title" class="tabs-title">{PAW}<span>Click the notch, pick a tab</span></h2>
        <div class="tab-row">
''' + '\n'.join(f'''          <figure class="tab-card">
            <img src="/img/{img}.webp" width="1360" height="520" loading="lazy" decoding="async" alt="{alt}">
            <figcaption><strong>{name}</strong>{line}</figcaption>
          </figure>''' for img, name, line, alt in TABS) + '''
        </div>
        <p class="more">Also Now Playing, Ask Claude, Anki, Schedule, Claude Usage and System.
          Open source on <a href="''' + GITHUB + '''">GitHub</a>.</p>
      </section>
'''


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

{faq('How do I delete my Party data?', f"""          <p>Party keeps only a nickname, your pet's look, your study status and minutes, your friend list and your party. It never has your email or real name. See the <a href="/privacy#friends">privacy policy</a> for the full list and <a href="/privacy#deleting">Deleting your data</a> for every option.</p>
          <ul>
            <li><strong>Leave a party</strong> from the Party tab. A party is deleted when its last member leaves, or after 12 hours without activity.</li>
            <li><strong>Remove a friend</strong> from their card in the Party tab. That deletes the friendship on both sides.</li>
            <li><strong>Delete everything</strong>: email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> with your friend code. To make sure the request is yours, we may ask you to change your Party nickname to a word we send you. We then erase your profile, status, study minutes and friend list, remove you from your friends' lists and your party, and confirm by email.</li>
          </ul>
          <p>Daily study minutes are deleted automatically after 28 days either way.</p>""", 'delete-party')}

{faq('Do I need Claude Code?', """          <p>No. Only Ask Claude, Claude Usage, and the optional Refine with Claude and Wrap up use it.
            Those tabs show a setup hint until the <code>claude</code> command is installed.
            Tabbi runs your own <code>claude</code> command, so your usage stays on the plan you already have and Tabbi never handles your credentials.</p>""", 'claude')}

{faq('How do I update or uninstall Tabbi?', f"""          <p>Tabbi checks for updates once a day and installs them in a few seconds. To check now, right-click the notch and choose <strong>Check for Updates</strong>.</p>
          <p>To uninstall, quit Tabbi and drag it from Applications to the Trash. Your tabs, tasks and settings stay in <code>~/Library/Application Support/Tabbi</code> in case you come back; delete that folder to remove them too.
            The <a href="{GITHUB}/blob/main/docs/install.md#uninstall">install guide</a> lists every folder.</p>""", 'uninstall')}
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
     'Tabbi turns your MacBook notch into a cozy panel of tabs: a focus timer, your day, music, Claude, Anki and a pet cat. Free and open source for macOS.',
     HOME, HOME_HERO, True, True),
    ('support.html', 'Support | Tabbi',
     'Help with installing and using Tabbi, answers to common questions, and how to reach a person.',
     SUPPORT, {'title': 'Support', 'subtitle': 'Answers to common questions, and how to reach a person.'}, False, True),
    ('privacy.html', 'Privacy Policy | Tabbi',
     'What Tabbi keeps on your Mac, what the optional friends service stores, and how to delete it.',
     PRIVACY, {'title': PRIVACY_HERO[0], 'subtitle': PRIVACY_HERO[1]}, False, True),
    ('terms.html', 'Terms of Use | Tabbi',
     'The terms for using the Tabbi app and its optional friends service.',
     TERMS, {'title': TERMS_HERO[0], 'subtitle': TERMS_HERO[1]}, False, True),
    # Cloudflare Pages serves 404.html for anything it cannot find.
    ('404.html', 'Not found | Tabbi',
     'That page is not here.',
     NOT_FOUND, {'title': 'Nothing in this tab', 'subtitle': 'The cat looked everywhere and came back empty-pawed.'}, False, False),
]


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


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

def fingerprint(src, folder):
    digest = hashlib.sha256(src.read_bytes()).hexdigest()[:8]
    hashed = f'{src.stem}.{digest}{src.suffix}'
    (OUT / folder).mkdir(exist_ok=True)
    shutil.copy(src, OUT / folder / hashed)
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
    fingerprints['/styles.css'] = fingerprint(HERE / 'styles.css', 'assets')

    asset_re = re.compile('|'.join(re.escape(k) for k in sorted(fingerprints, key=len, reverse=True)))

    for slug, title, description, body, hero, wide, indexable in pages:
        html = unobfuscate(page(slug, title, description, body, hero, wide, indexable))
        html = asset_re.sub(lambda m: fingerprints[m.group(0)], html)

        # An unhashed reference is a file that did not exist when the
        # fingerprints were built. A missing image should stop a build.
        unhashed = [m for m in re.findall(r'/(?:img|assets)/[A-Za-z0-9._-]+', html)
                    if len(m.rsplit('/', 1)[1].split('.')) < 3]
        if unhashed:
            raise SystemExit(f'{slug}: references files that do not exist: ' + ', '.join(sorted(set(unhashed))))

        (OUT / slug).write_text(html)
        print('wrote', slug)

    shutil.copy(HERE / '_headers', OUT / '_headers')
    shutil.copy(HERE / 'favicon.ico', OUT / 'favicon.ico')
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

    biggest = max((f for f in OUT.rglob('*') if f.is_file()), key=lambda f: f.stat().st_size)
    if biggest.stat().st_size > 20 * 1024 * 1024:
        raise SystemExit(f'{biggest} is over 20 MB; Cloudflare Pages refuses files over 25 MB')
    print('copied _headers, favicon.ico, robots.txt, sitemap.xml and %d fingerprinted assets' % len(fingerprints))


class PagesHandler(http.server.SimpleHTTPRequestHandler):
    """Serves dist/ with Cloudflare Pages' rules: /support finds support.html,
    and anything missing gets 404.html with a 404 status."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(OUT), **kwargs)

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
