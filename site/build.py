"""Generate the site into dist/. Standard library only.

    python3 site/build.py           build
    python3 site/build.py --serve   build, then serve dist/ the way Cloudflare Pages does
"""

import hashlib
import http.server
import io
import json
import pathlib
import re
import shutil
import sys
import zipfile
from html.parser import HTMLParser

from _partials import page, download_button, PAW, DOWNLOAD, DOWNLOAD_ICON, GITHUB, ISSUES, ORIGIN, RELEASES_URL, SUGGESTIONS, SUPPORT_EMAIL
from _releases import RELEASES, VERSION
from _legal import PRIVACY, PRIVACY_HERO, TERMS, TERMS_HERO
from _demo import DEMO, demo_data

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

# The tabs and features the notch demo above does not show, one line each.
MORE = [
    ('Party', 'Study with friends, pets side by side. Invite them with a link.'),
    ('Recap', 'A Sunday look back at your week. Streak freezes cover days off.'),
    ('Widget', 'Your pet, your streak and the timer on your desktop.'),
    ('Ask AI', 'Ask the AI you already use, even one that runs on your Mac.'),
]

HOME_HERO = {
    'home': True,
    'title': 'A little cat for your <span class="hl">notch</span>.',
    'subtitle': 'A cozy panel of tabs in your laptop notch.',
    'cta': f'''<div class="cta">{download_button()}</div>
        <p class="cta-note">Free, macOS 14+</p>''',
    'eyebrow': '<img class="hero-icon" src="/img/icon-256.webp" width="256" height="256" alt="The Tabbi app icon: a cream British Shorthair cat with blue eyes on a golden yellow square">',
    # A drawn laptop whose screen plays the app in use, rendered from its
    # demo snapshots by _hero_video.py (see README). The source only matches
    # without reduced motion, so then nothing loads and the poster stays.
    # The animated WebP is for browsers without video; lazy, so others never
    # fetch it. pixel-cat.png is the app's gray tabby sprite, sitting and blinking.
    'art': '''<div class="laptop">
        <span class="pixel-cat" aria-hidden="true"></span>
        <div class="laptop-screen">
          <video class="laptop-video" autoplay muted loop playsinline disableremoteplayback poster="/img/hero-poster.webp" width="1200" height="750" aria-label="Tabbi in use: clicking the notch opens the Timer, then Today, where a task gets checked off and the pet cheers">
            <source src="/img/hero.mp4" type="video/mp4" media="(prefers-reduced-motion: no-preference)">
            <img src="/img/hero-fallback.webp" width="600" height="375" loading="lazy" alt="Tabbi in use: clicking the notch opens the Timer, then Today, where a task gets checked off and the pet cheers">
          </video>
        </div>
        <div class="laptop-base"></div>
      </div>''',
}

# The trust stickers' little line icons, drawn like the paw: one stroke
# weight, round ends, colored by the card.
def sticker_icon(paths):
    return ('<svg class="trust-mark" viewBox="0 0 24 24" width="26" height="26" aria-hidden="true">'
            '<g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
            + paths + '</g></svg>')


HEART = sticker_icon('<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/>')
CODE = sticker_icon('<path d="M8.5 7 3.5 12l5 5M15.5 7l5 5-5 5"/>')
LOCK = sticker_icon('<rect x="5" y="10.5" width="14" height="10" rx="3"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>')
FEATHER = sticker_icon('<path d="M19 5c-7 0-12 4.5-12 12v2M7 17c5 0 9-3 10.5-8.5M10.5 13.5H15"/>')

HOME = DEMO + f'''
      <section class="tabs" aria-labelledby="tabs-title">
        <h2 id="tabs-title" class="tabs-title">{PAW}<span>More inside</span></h2>
        <ul class="tab-row">
''' + '\n'.join(f'''          <li class="tab-card"><span class="tab-label">{label}</span>{line}</li>''' for label, line in MORE) + f'''
        </ul>
        <p class="more">Plus seasonal outfits, SoundCloud and more. Missing a tab? <a href="/suggest">Suggest one</a>.</p>
      </section>
      <section class="steps" aria-labelledby="steps-title">
        <h2 id="steps-title" class="tabs-title">{PAW}<span>How it works</span></h2>
        <ol class="step-row">
          <li class="step"><span class="step-num" aria-hidden="true">1</span><strong>Hover the notch</strong><span>Click, and it opens into a little panel.</span></li>
          <li class="step"><span class="step-num" aria-hidden="true">2</span><strong>Pick a tab</strong><span>Your timer, your day, your music and more.</span></li>
          <li class="step"><span class="step-num" aria-hidden="true">3</span><strong>Close it</strong><span>Your cat keeps you company beside the notch.</span></li>
        </ol>
        <figure class="peek">
          <div class="peek-screen" role="img" aria-label="The closed notch, showing in turn a meeting soon, a song playing, the timer counting down and the cat">
            <div class="peek-notch" aria-hidden="true">
              <span class="peek-slide peek-meet"><span class="peek-l"><span class="peek-cal"></span></span><span class="peek-r">Standup in 5 min</span></span>
              <span class="peek-slide peek-song"><span class="peek-l"><span class="peek-cover"></span></span><span class="peek-r peek-eq"><span></span><span></span><span></span><span></span></span></span>
              <span class="peek-slide peek-timer"><span class="peek-l"><svg class="peek-ring" viewBox="0 0 20 20"><circle cx="10" cy="10" r="8.5"/><circle class="peek-arc" cx="10" cy="10" r="8.5" pathLength="100"/></svg></span><span class="peek-r">18:42</span></span>
              <span class="peek-slide peek-pet"><span class="peek-l"><span class="peek-cat"></span></span><span class="peek-r">+35 pts</span></span>
            </div>
          </div>
          <figcaption>Closed, it still peeks: a meeting, your song, the timer or your cat.</figcaption>
        </figure>
      </section>
      <section class="trust" aria-label="Good to know">
        <ul class="trust-row">
          <li class="trust-card">{HEART}<span>Free forever</span></li>
          <li class="trust-card">{CODE}<span>Open source (MIT)</span></li>
          <li class="trust-card">{LOCK}<span>No account or tracking</span></li>
          <li class="trust-card">{FEATHER}<span>A tiny native app</span></li>
        </ul>
      </section>
      <section class="home-faq" aria-labelledby="faq-title">
        <h2 id="faq-title" class="tabs-title">{PAW}<span>Little questions</span></h2>
        <details class="faq">
          <summary>Does my Mac need a notch?</summary>
          <div class="faq-body"><p>No. Any Mac on macOS 14 or later works. Without a notch, Tabbi draws a small one at the top of the screen.</p></div>
        </details>
        <details class="faq">
          <summary>Do I need an account?</summary>
          <div class="faq-body"><p>No. Everything works without one. Sign in with Apple only if you want your pet on more than one Mac.</p></div>
        </details>
        <details class="faq">
          <summary>Do I need an AI app?</summary>
          <div class="faq-body"><p>Only the AI tabs do. Pick Claude, Codex, Gemini or Ollama, or bring your own key. Every other tab works without one.</p></div>
        </details>
        <details class="faq">
          <summary>How do I quit Tabbi?</summary>
          <div class="faq-body"><p>Right-click the notch and choose <strong>Quit Tabbi</strong>. Settings live in the same menu.</p></div>
        </details>
        <p class="more">More answers on the <a href="/support">Support page</a>.</p>
      </section>
      <section class="thanks" aria-label="Say hi">
        <div class="card-pair">
          <a class="gh-card" href="''' + GITHUB + '''">
            <img class="gh-cat" src="/img/glyph.webp" width="56" height="56" alt="">
            <svg class="gh-mark" viewBox="0 0 16 16" width="26" height="26" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
            <span class="gh-text"><strong>Open source on GitHub</strong><span>Come say hi or leave a star.</span></span>
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
      <section class="outro" aria-labelledby="outro-title">
        <h2 id="outro-title" class="outro-title">Give your notch a cat.</h2>
        <div class="cta">''' + download_button() + '''</div>
        <p class="cta-note">No account. macOS 14 or later.</p>
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
    'description': 'A cozy panel of tabs in your laptop notch: a focus timer, your day, music, AI, Anki flashcards and a pet cat or dog.',
    'url': ORIGIN + '/',
    'image': ORIGIN + '/img/icon-256.webp',
    'screenshot': ORIGIN + '/img/social-preview.png',
    'applicationCategory': 'ProductivityApplication',
    'operatingSystem': 'macOS 14 or later',
    'softwareVersion': VERSION,
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
          Say which Mac, macOS and Tabbi version you have (right-click the notch, then <strong>Settings &gt; About</strong>), and what you were doing.</p>
        <p>Found a bug or have an idea? <a href="{ISSUES}">Open an issue on GitHub</a>.
          Security problems go by email, please, not in a public issue.</p>
      </div>

      <h2>Common questions</h2>

{faq('How do I install Tabbi?', f"""          <ol>
            <li>Click <a href="{DOWNLOAD}">Download for Mac</a> to get <strong>Tabbi.dmg</strong>, the newest version.</li>
            <li>Open it and drag <strong>Tabbi</strong> onto the <strong>Applications</strong> folder.</li>
            <li>Open Tabbi from Applications. macOS asks once whether to open an app downloaded from the Internet: click <strong>Open</strong>.</li>
          </ol>
          <p>Tabbi has no Dock icon and no menu bar item. Move the pointer to the notch and click it.
            The first time, a short welcome inside the notch helps you pick your tabs.</p>
          <p>With Homebrew you can run <code>brew install --cask ethanwchen/tap/tabbi</code> instead.</p>""", 'install')}

{faq('What if macOS will not open Tabbi?', """          <p>Releases downloaded from GitHub are signed by the developer and notarized by Apple, so they open normally.
            The warning appears only for a copy built without a Developer ID, such as a test build.
            To open one anyway:</p>
          <ol>
            <li>Open Tabbi. When macOS stops it, click <strong>Done</strong> (not Move to Trash).</li>
            <li>Open <strong>System Settings &gt; Privacy &amp; Security</strong>, scroll to <strong>Security</strong>, and click <strong>Open Anyway</strong> next to Tabbi. The button shows for about an hour after step 1.</li>
            <li>Enter your Mac password, then click <strong>Open</strong>.</li>
          </ol>
          <p>If macOS says Tabbi is damaged, the download was cut short. Move it to the Trash and download it again.</p>""", 'gatekeeper')}

{faq('How do I quit Tabbi?', """          <p>Right-click the notch and choose <strong>Quit Tabbi</strong>.
            The same menu has your tabs, <strong>Settings</strong>, <strong>Suggest a Feature or Report a Bug</strong>, and in the direct download <strong>Check for Updates</strong>.</p>
          <p>Tabbi opens at login by default. To stop that, turn off <strong>Launch at login</strong> in <strong>Settings &gt; General</strong>.</p>""", 'quit')}

{faq('Can I make the panel bigger or smaller?', """          <p>Yes. Right-click the notch, choose <strong>Settings</strong>, and pick a <strong>Panel size</strong> in <strong>General</strong>:
            Compact, Regular or Large. Every tab uses the same size, so switching tabs never jumps.</p>
          <p>In the same place you can turn on <strong>Open on hover</strong>, hide the notch in fullscreen apps, and choose which display it appears on.</p>""", 'resize')}

{faq('How do friend codes work in Party?', """          <p>Party is an optional tab: add it from <strong>Settings &gt; Tabs &gt; Add more</strong>.
            Party is for people 13 and older: when you turn it on, it first asks the month and year you were born, which stay on your Mac.
            Then Tabbi gives you an 8-character <strong>friend code</strong>. Copy it from the Party tab and send it to a friend. Once they add it, you see each other.
            Friendship is always mutual, and nobody can find you without your code: there is no directory or search.</p>
          <p>To study together, one of you starts a party and shares its 6-character party code. Anyone with that code can join while there is room, so share it only with people you want to study with.</p>
          <p>Want a break from being seen? Turn on <strong>Go invisible</strong> in the Party options and friends see you as offline.</p>""", 'party')}
{faq('How do I block or report someone in Party?', f"""          <p>Right-click their row in your friends list or their pet in a party, then choose <strong>Block</strong> or <strong>Report</strong>.</p>
          <p><strong>Blocking</strong> ends the friendship and hides the two of you from each other everywhere in Party. They cannot add you again or join a party you host, and they are not told. Unblock someone any time from the <strong>Blocked</strong> list in the Party options.</p>
          <p><strong>Reporting</strong> sends us their current name and pet, a reason and an optional note, and offers to block them too. We review every report and can rename or ban an account. A banned account cannot change its name or join parties, and no one else sees it.</p>
          <p>For anything else, email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>.</p>""", 'party-safety')}

{faq('Do I need an account?', """          <p>No. Everything in Tabbi works without one.
            To sync your pet across Macs, choose <strong>Sign in with Apple</strong> in <strong>Settings &gt; General</strong> on each of them.
            Your pet, points, unlocked items and streaks then sync, and your Party friend code and friends follow you.</p>
          <p>Accounts are for people 13 and older.
            Tabbi asks Apple only for your name, never your email, and keeps the name on your Mac.
            In the direct download, Apple's sign-in page passes the name through our server, which does not store it.
            Your calendar, tasks, activity history, AI chats and settings are never synced.
            Signing in on a Mac that already has progress adds it to your account, so nothing is overwritten.
            <strong>Sign Out</strong> stops syncing on that Mac and keeps your pet there.
            The <a href="/privacy#account">privacy policy</a> lists exactly what the account stores.</p>""", 'account')}

{faq('How do I delete my account or Party data?', f"""          <p>Party keeps only a nickname, your pet's look and level, your study status, minutes and streak, your friend list, your party, and any blocks and reports. It never has your email or real name. See the <a href="/privacy#friends">privacy policy</a> for the full list and <a href="/privacy#deleting">Deleting your data</a> for every option.</p>
          <ul>
            <li><strong>Leave a party</strong> from the Party tab. A party is deleted when its last member leaves, or after 12 hours without activity.</li>
            <li><strong>Remove a friend</strong> from their card in the Party tab. That deletes the friendship on both sides.</li>
            <li><strong>Delete your Party data</strong>: without an account, open <strong>Settings &gt; Tabs</strong>, click <strong>Options</strong> next to Party, and choose <strong>Delete my Party data</strong>. Your profile, status, study minutes, friend list and party are erased from the server at once, and your pet stays on your Mac.</li>
            <li><strong>Delete your account</strong>: when signed in with Apple, open <strong>Settings &gt; General</strong> and choose <strong>Delete Account</strong>. That erases your Party data, your synced pet and progress, and your Apple link from the server, and revokes Tabbi's Sign in with Apple access. Your pet stays on the Mac you deleted from.</li>
            <li>Cannot open the app? Email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> with your friend code. To make sure the request is yours, we may ask you to change your Party nickname to a word we send you. We then delete the same data within 30 days, usually much sooner, and confirm by email.</li>
          </ul>
          <p>Daily study minutes are deleted automatically after 28 days either way.
            Backup copies of deleted data are gone within 30 days.</p>""", 'delete-party')}

{faq('How do I use the AI features?', """          <p>Ask AI, Plan my day, the Wrap up day review and the Schedule's Refine need an AI. Everything else works without one.
            Tabbi sends nothing until you pick a provider in <strong>Settings &gt; Connections &gt; AI</strong>.
            The first time you pick one that runs outside your Mac, Tabbi says which company receives your data and what each feature sends, and sends nothing unless you choose <strong>Allow</strong>.</p>
          <ul>
            <li><strong>Your own API key</strong> for Claude (Anthropic), OpenAI or Gemini (Google). The key stays in your Mac's Keychain.</li>
            <li><strong>Ollama</strong>, which runs a model on your Mac. Nothing leaves it.</li>
            <li><strong>A command line tool you already use</strong>: Claude Code, Codex or Gemini CLI. Tabbi runs your own command, so usage stays on your plan and Tabbi never handles your credentials. These are in the direct download only.</li>
          </ul>
          <p>What you send goes to the provider you picked, under its terms. The <a href="/privacy#ai">privacy policy</a> says exactly what is sent.</p>""", 'ai')}

{faq('How do I update or uninstall Tabbi?', f"""          <p>Tabbi checks for updates once a day and installs them in a few seconds. To check now, right-click the notch and choose <strong>Check for Updates</strong>.</p>
          <p>The Mac App Store edition is updated by the App Store instead.</p>
          <p>To uninstall, quit Tabbi and drag it from Applications to the Trash. Your tabs, tasks and settings stay in <code>~/Library/Application Support/Tabbi</code> in case you come back; delete that folder to remove them too.
            The App Store edition keeps them in <code>~/Library/Containers/dev.tabbi.Tabbi</code> instead.
            The <a href="{GITHUB}/blob/main/docs/install.md#uninstall">install guide</a> lists every folder.</p>""", 'uninstall')}
'''


# The press kit: the icon at 1024 px and four tab screenshots, as lossless
# PNGs, zipped by the build.
PRESS = HERE / 'press'
PRESS_KIT = 'tabbi-press-kit.zip'
PRESS_MB = f"{sum(f.stat().st_size for f in PRESS.glob('*.png')) / 1e6:.1f}&nbsp;MB"


ABOUT = f'''
      <div class="about">
        <img class="about-cat" src="/img/glyph.webp" width="96" height="96" alt="">
        <p class="about-lead">Hi, it&rsquo;s Ethan.</p>
        <p>I made Tabbi because I wanted my study tools in one cozy spot, right where I already look: the notch.</p>
        <p>It&rsquo;s free and open source. No ads, no tracking, no account needed.</p>
        <p>If Tabbi helps you focus, a&nbsp;star or a&nbsp;coffee means a lot.</p>
        <div class="cta center">
          <a class="btn" href="https://buymeacoffee.com/ethanpolar">Buy me a coffee</a>
          <a class="btn soft" href="{GITHUB}">Star on GitHub</a>
        </div>
        <div class="press" id="press">
          <h2>Press kit</h2>
          <p>Tabbi is a free, open source app for macOS 14 or later. It turns the laptop notch into a cozy panel of tabs: a focus timer, your day, music, AI, Anki flashcards and a pet cat or dog. No ads, no tracking.</p>
          <div class="cta center">
            <a class="btn soft" href="/press/{PRESS_KIT}" download title="A ZIP of the icon and four screenshots">Get the kit ({PRESS_MB})</a>
          </div>
        </div>
      </div>
'''


# --------------------------------------------------------------------------
# What's new
# --------------------------------------------------------------------------

# One sentence per release, newest first (_releases.py). The full notes stay
# on GitHub.
WHATS_NEW = '\n'.join(f'''
        <article class="release" id="v{version}">
          <h2><span class="release-tag">v{version}</span> <span class="release-when">{when}</span></h2>
          <p>{sentence}</p>
        </article>''' for version, when, sentence in RELEASES) + f'''
        <p class="release-more">Every change in detail is in the <a href="{RELEASES_URL}">release notes on GitHub</a>.</p>
'''


# --------------------------------------------------------------------------
# Suggest
# --------------------------------------------------------------------------

# A plain form, no script: it posts to the friends backend, which answers with
# a redirect to /thanks. The "website" field is a honeypot: people never see
# it, bots fill it in, and the backend drops anything that arrives with it.
# "version", "macos" and "edition" say which Tabbi a bug report is about when
# the app opened the page (FeedbackLink in TabbiKitCore); left empty, the
# backend stores none.
SUGGEST_APP_FACTS = ['version', 'macos', 'edition']
SUGGEST_CATEGORIES = [
    ('tab', 'A new tab'),
    ('integration', 'An integration'),
    ('improvement', 'An improvement'),
    ('other', 'Something else'),
]

SUGGEST = f'''
      <form class="suggest" action="{SUGGESTIONS}" method="post">
        <div class="field">
          <label for="category">What kind of idea?</label>
          <select id="category" name="category">
''' + '\n'.join(f'            <option value="{value}">{label}</option>' for value, label in SUGGEST_CATEGORIES) + '''
          </select>
        </div>
        <div class="field">
          <label for="message">Your idea</label>
          <textarea id="message" name="message" rows="6" minlength="10" maxlength="2000" required placeholder="A tab for my plants, so I remember to water them."></textarea>
        </div>
        <div class="field">
          <label for="email">Email <span class="optional">(optional)</span></label>
          <input id="email" name="email" type="email" maxlength="254" autocomplete="email" aria-describedby="email-note">
          <p class="note" id="email-note">Only to ask about or reply to this idea. Never a newsletter.</p>
        </div>
        <div class="hp" aria-hidden="true">
          <label for="website">Leave this empty</label>
          <input id="website" name="website" type="text" tabindex="-1" autocomplete="off">
        </div>
''' + '\n'.join(f'        <input type="hidden" name="{name}" value="">' for name in SUGGEST_APP_FACTS) + '''
        <button class="btn" type="submit">Send suggestion</button>
      </form>
'''

THANKS = '''
      <div class="lost">
        <img src="/img/glyph.webp" width="96" height="96" alt="">
        <p class="measure">Every idea gets read. If you left an email, you may hear back.</p>
        <div class="cta center">
          <a class="btn" href="/">Back to the start</a>
          <a class="btn soft" href="/suggest">Suggest another</a>
        </div>
      </div>
'''


NOT_FOUND = '''
      <div class="lost">
        <img src="/img/glyph.webp" width="96" height="96" alt="">
        <p class="measure">This page may have moved, or the link was wrong.</p>
        <div class="cta center">
          <a class="btn" href="/">Back to the start</a>
          <a class="btn soft" href="/support">Get help</a>
        </div>
      </div>
'''

# Party invites. People share https://tabbinotch.com/add/<friend code> and
# /join/<party code> (PartyInvite in TabbiKitCore). The site has no script,
# so a Pages Function (functions/add/[code].js, functions/join/[code].js,
# through _invite.mjs) checks the code and fills it into one of these pages
# on the server. Each page sends Tabbi the same link as tabbi://add/<code>
# with a meta refresh (left out on phones, which cannot run Tabbi and would
# only show an error), and has buttons for people without Tabbi yet. The
# pages are built like the others so every check covers them, then moved out
# of dist into _generated.mjs, since without a code they mean nothing.
#
# The codes use PartyCode's alphabet (no I, O, 0 or 1) and lengths.
INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
INVITE_CODE_LENGTHS = {'add': 8, 'join': 6}
# Placeholders the Function replaces. Neither is a valid code (I and O are
# not in the alphabet), so a page that slipped through unfilled shows it.
INVITE_CODE = 'INVITECODE'
INVITE_SHOWN = 'INVITE-SHOWN'
INVITE_REFRESH = '<!--invite-refresh-->'
INVITE_SLUGS = {'add': 'invite-add.html', 'join': 'invite-join.html', 'invalid': 'invite-invalid.html'}


def invite_body(label, note):
    return f'''
      <div class="invite">
        <img src="/img/glyph.webp" width="96" height="96" alt="">
        <p class="eyebrow">{label}</p>
        <p class="invite-code">{INVITE_SHOWN}</p>
        <div class="cta center">
          <a class="btn" href="tabbi://ACTION/{INVITE_CODE}">Open in Tabbi</a>
          <a class="btn soft" href="{DOWNLOAD}">{DOWNLOAD_ICON}<span>Download Tabbi</span></a>
        </div>
        <p class="note measure">{note}</p>
      </div>
'''


INVITE_ADD = invite_body(
    'Friend code',
    'New to Tabbi? Download it, then open this link again. Tabbi asks before it adds anyone.',
).replace('ACTION', 'add')

INVITE_JOIN = invite_body(
    'Party code',
    'New to Tabbi? Download it, then open this link again. Tabbi asks before you join.',
).replace('ACTION', 'join')

INVITE_INVALID = f'''
      <div class="lost">
        <img src="/img/glyph.webp" width="96" height="96" alt="">
        <p class="measure">The code in this link is not one Tabbi hands out. Ask your friend to copy their invite link again, or type their code in the Party tab.</p>
        <div class="cta center">
          <a class="btn" href="{DOWNLOAD}">{DOWNLOAD_ICON}<span>Download Tabbi</span></a>
          <a class="btn soft" href="/support">Get help</a>
        </div>
      </div>
'''


def shown_code(code):
    """The code the way the app shows it: a friend code split in two halves
    (PartyStyle.display), a party code whole."""
    return code if len(code) <= 6 else code[:len(code) // 2] + '-' + code[len(code) // 2:]


# Phones cannot run Tabbi, and Safari there answers a tabbi:// refresh with
# an "address is invalid" alert, so they get the page without it.
PHONE_RE = re.compile(r'iPhone|iPad|iPod|Android|Mobile')


def invite_page(templates, action, raw, user_agent=''):
    """(status, html) for /<action>/<raw>, the way _invite.mjs answers in
    production; --serve uses it to preview the pages. A code is normalized
    like PartyCode (upper-cased, dashes dropped) and must use its alphabet
    and length; a percent-encoded one is refused, never decoded."""
    code = raw.upper().replace('-', '')
    if '%' in raw or len(code) != INVITE_CODE_LENGTHS[action] or any(c not in INVITE_ALPHABET for c in code):
        return 404, templates['invalid']
    refresh = '' if PHONE_RE.search(user_agent) else f'\n  <meta http-equiv="refresh" content="0; url=tabbi://{action}/{code}">'
    html = templates[action].replace(INVITE_REFRESH, refresh)
    return 200, html.replace(INVITE_SHOWN, shown_code(code)).replace(INVITE_CODE, code)


pages = [
    ('index.html', 'Tabbi: a little cat for your notch',
     'Tabbi turns your laptop notch into a cozy panel of tabs: a focus timer, your day, music, AI, Anki flashcards and a pet cat or dog. Free and open source for macOS.',
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
    ('whats-new.html', 'What\u2019s new | Tabbi',
     'What each version of Tabbi brought, one line per release.',
     WHATS_NEW, {'title': 'What&rsquo;s new', 'subtitle': 'What the cat brought home in each release.'}, False, True),
    ('suggest.html', 'Suggest | Tabbi',
     'Suggest a new tab, an integration or an improvement for Tabbi.',
     SUGGEST, {'title': 'Suggest', 'subtitle': 'An idea for a new tab, an integration or something better? Tell the cat.'}, False, True),
    # Where the suggestion backend redirects after a post.
    ('thanks.html', 'Thank you | Tabbi',
     'Your suggestion reached Tabbi.',
     THANKS, {'title': 'Thank you!', 'subtitle': 'Your idea is in the cat&rsquo;s inbox.'}, False, False),
    ('invite-add.html', 'Add a friend on Tabbi',
     'A friend invited you to Tabbi. Open the link in Tabbi on your Mac to add them.',
     INVITE_ADD, {'title': 'A friend wants to add you', 'subtitle': 'Open this invite in Tabbi on your Mac, and your pets can study side by side.'}, False, False),
    ('invite-join.html', 'Join a party on Tabbi',
     'A friend invited you to a study party in Tabbi. Open the link in Tabbi on your Mac to join.',
     INVITE_JOIN, {'title': 'You are invited to a party', 'subtitle': 'Open this invite in Tabbi on your Mac to focus together with your friends.'}, False, False),
    ('invite-invalid.html', 'Invite not found | Tabbi',
     'That invite link is not right.',
     INVITE_INVALID, {'title': 'This invite looks off', 'subtitle': 'The cat could not read the code in this link.'}, False, False),
    # Cloudflare Pages serves 404.html for anything it cannot find.
    ('404.html', 'Not found | Tabbi',
     'That page is not here.',
     NOT_FOUND, {'title': 'Nothing in this tab', 'subtitle': 'The cat looked everywhere and came back empty-pawed.'}, False, False),
]

# Extra <head> markup per page.
# The home page's notch demo: its stylesheet, its data blocks (the pet's
# frames and Today's lists) and the site's one script, deferred so it runs
# after the page is parsed.
HEADS = {'index.html': json_ld(SOFTWARE_APP)
         + '\n  <link rel="stylesheet" href="/demo.css">'
         + demo_data()
         + '\n  <script src="/js/demo.js" defer></script>'}
for _action in INVITE_CODE_LENGTHS:
    HEADS[INVITE_SLUGS[_action]] = INVITE_REFRESH


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
        for key in ('href', 'src', 'poster'):
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


SCRIPT_TAG_RE = re.compile(r'<script\b([^>]*)>(.*?)</script>', re.S)
# The one script a page may load: the demo's, from the site itself, with no
# inline code. _headers allows exactly that (script-src 'self').
DEMO_SCRIPT_RE = re.compile(r' src="/assets/demo\.[0-9a-f]{8}\.js" defer')
# An inline event handler is inline script, which the CSP blocks.
HANDLER_RE = re.compile(r'<[a-z][^>]*\son[a-z]+\s*=', re.I)
# What demo.js must never do: run strings as code or talk to the network.
JS_FORBIDDEN_RE = re.compile(r'\b(?:eval|Function|fetch|XMLHttpRequest|WebSocket|EventSource|importScripts|sendBeacon)\s*\(|\bimport\s*\(|innerHTML|document\.write')


def check_scripts():
    """Pages run no script but the demo's own file: every other script
    element must be a data block (JSON-LD or JSON) that parses, JSON-LD must
    name its schema.org type, and no element may carry an inline handler."""
    for html_file in sorted(OUT.glob('*.html')):
        html = html_file.read_text()
        if HANDLER_RE.search(html):
            raise SystemExit(f'{html_file.name}: has an inline event handler; the CSP blocks inline script')
        external = 0
        for attrs, body in SCRIPT_TAG_RE.findall(html):
            if attrs == ' type="application/ld+json"' or re.fullmatch(r' type="application/json" id="[a-z-]+"', attrs):
                try:
                    data = json.loads(body)
                except ValueError as e:
                    raise SystemExit(f'{html_file.name}: a JSON data block does not parse: {e}')
                if 'ld+json' in attrs and (data.get('@context') != 'https://schema.org' or '@type' not in data):
                    raise SystemExit(f'{html_file.name}: JSON-LD needs a schema.org @context and an @type')
            elif DEMO_SCRIPT_RE.fullmatch(attrs) and not body.strip():
                external += 1
            else:
                raise SystemExit(f'{html_file.name}: has a script the CSP would block: <script{attrs}>')
        if external > 1:
            raise SystemExit(f'{html_file.name}: loads the demo script more than once')
        if html.count('<script') != len(SCRIPT_TAG_RE.findall(html)):
            raise SystemExit(f'{html_file.name}: has a script element the check cannot read')
    for js in OUT.glob('assets/*.js'):
        found = JS_FORBIDDEN_RE.search(js.read_text())
        if found:
            raise SystemExit(f'{js.name}: uses {found.group(0)!r}; the demo runs no strings as code and makes no network calls')


FORM_RE = re.compile(r'<form [^>]*action="([^"]+)"')


def check_forms():
    """Every form must post to an origin the CSP's form-action allows, or
    the browser refuses to send it and the visitor's words are lost."""
    csp = dict(SITE_HEADERS).get('Content-Security-Policy', '')
    allowed = next((d.split()[1:] for d in csp.split(';') if d.split()[:1] == ['form-action']), [])
    for html_file in sorted(OUT.glob('*.html')):
        for action in FORM_RE.findall(html_file.read_text()):
            origin = '/'.join(action.split('/')[:3]) if '://' in action else "'self'"
            if origin not in allowed:
                raise SystemExit(f'{html_file.name}: a form posts to {origin}, which form-action in _headers does not allow')


# The whole home page should stay under about 600 KB, fonts included.
PAGE_BUDGET = 500 * 1024
ASSET_RE = re.compile(r'/(?:img|assets|fonts)/(?:[A-Za-z0-9_-]+/)?[A-Za-z0-9._-]+')
# Fetched only for link previews, search results or a home screen icon, not
# by the page.
NOT_LOADED_RE = re.compile(r'<meta [^>]*>|<link rel="apple-touch-icon"[^>]*>|<script type="application/ld\+json">.*?</script>', re.S)
# A video streams in after the page is up, so it has a budget of its own.
# Its poster is part of the page; the rest (the clip and the fallback for
# browsers without video, which others never fetch) is counted here.
MEDIA_BUDGET = 2 * 1024 * 1024
VIDEO_RE = re.compile(r'<video\b(?:[^>]*?\bposter="([^"]*)")?[^>]*>(.*?)</video>', re.S)


def check_weight():
    """Every page, with its stylesheets, script and every image they can
    load (both sizes of a srcset, and every pet look the demo can show, so
    this is a ceiling), must fit PAGE_BUDGET, and every file inside a video
    must fit MEDIA_BUDGET."""
    report = []
    for html_file in sorted(OUT.glob('*.html')):
        html = NOT_LOADED_RE.sub('', html_file.read_text())
        for media in ASSET_RE.findall(''.join(inner for _poster, inner in VIDEO_RE.findall(html))):
            size = (OUT / media.lstrip('/')).stat().st_size
            report.append(f'{media.rsplit("/", 1)[1]} {size // 1024} KB')
            if size > MEDIA_BUDGET:
                raise SystemExit(f'{html_file.name}: {media} is {size // 1024} KB; a video\'s budget is {MEDIA_BUDGET // 1024} KB')
        page = VIDEO_RE.sub(lambda m: m.group(1) or '', html)
        assets = set(ASSET_RE.findall(page))
        for css in [a for a in assets if a.endswith('.css')]:
            assets |= set(ASSET_RE.findall((OUT / css.lstrip('/')).read_text()))
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
    (OUT / folder).mkdir(parents=True, exist_ok=True)
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
    for src in sorted((HERE / 'img').rglob('*')):
        if src.suffix in ('.png', '.gif', '.jpg', '.webp', '.svg', '.mp4'):
            folder = src.parent.relative_to(HERE).as_posix()
            fingerprints[f'/{folder}/{src.name}'] = fingerprint(src, folder)
    # Fonts land in /assets/ with the stylesheet, which is cached the same way.
    for src in sorted((HERE / 'fonts').glob('*.woff2')):
        fingerprints['/fonts/' + src.name] = fingerprint(src, 'assets')

    def asset_sub(text):
        asset_re = re.compile('|'.join(re.escape(k) for k in sorted(fingerprints, key=len, reverse=True)))
        return asset_re.sub(lambda m: fingerprints[m.group(0)], text)

    # The stylesheets point at images too (the paper grain, the demo's pet),
    # so their image URLs are hashed first and their own hash covers them.
    for name in ('styles.css', 'demo.css'):
        css = asset_sub((HERE / name).read_text())
        if unhashed(css):
            raise SystemExit(f'{name}: references files that do not exist: ' + ', '.join(unhashed(css)))
        fingerprints['/' + name] = fingerprint(HERE / name, 'assets', css.encode())
    fingerprints['/js/demo.js'] = fingerprint(HERE / 'js' / 'demo.js', 'assets')

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
    check_forms()
    check_weight()

    # The invite pages passed every check; without a code they mean
    # nothing, so they leave dist for the Function (see INVITE_SLUGS).
    for key, slug in INVITE_SLUGS.items():
        INVITE_TEMPLATES[key] = (OUT / slug).read_text()
        (OUT / slug).unlink()
    write_function_facts()

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
# The invite pages, filled in by build() (see INVITE_SLUGS).
INVITE_TEMPLATES = {}


def write_function_facts():
    """Writes _generated.mjs for the Pages Functions: the `/*` headers,
    which Cloudflare Pages does not apply to a Function's response, the
    Suggest form's hidden app facts (functions/suggest.js), and the invite
    pages with their code rules (functions/add, functions/join), so the
    pages and the Functions cannot drift apart."""
    invite = {
        'alphabet': INVITE_ALPHABET,
        'lengths': INVITE_CODE_LENGTHS,
        'placeholders': {'code': INVITE_CODE, 'shown': INVITE_SHOWN, 'refresh': INVITE_REFRESH},
        'phones': PHONE_RE.pattern,
        'pages': INVITE_TEMPLATES,
    }
    (HERE / '_generated.mjs').write_text(
        '// Written by build.py from _headers, SUGGEST_APP_FACTS and the invite pages. Do not edit.\n'
        f'export const SITE_HEADERS = {json.dumps(SITE_HEADERS)};\n'
        f'export const SUGGEST_APP_FACTS = {json.dumps(SUGGEST_APP_FACTS)};\n'
        f'export const INVITE = {json.dumps(invite)};\n'
    )


class PagesHandler(http.server.SimpleHTTPRequestHandler):
    """Serves dist/ with Cloudflare Pages' rules: /support finds support.html,
    and anything missing gets 404.html with a 404 status."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(OUT), **kwargs)

    def end_headers(self):
        # The headers _headers sets for every path, CSP included, so a
        # preview fails the same way production would.
        for name, value in SITE_HEADERS:
            # WebKit applies upgrade-insecure-requests even to localhost, so
            # over plain http every stylesheet, font and image would fail.
            # Production is https, where the directive changes nothing.
            if name == 'Content-Security-Policy':
                value = value.replace('; upgrade-insecure-requests', '')
            self.send_header(name, value)
        super().end_headers()

    def send_head(self):
        path = self.path.split('?', 1)[0].split('#', 1)[0]
        invite = INVITE_PATH_RE.fullmatch(path)
        if invite:
            status, html = invite_page(INVITE_TEMPLATES, invite.group(1), invite.group(2), self.headers.get('User-Agent', ''))
            body = html.encode()
            self.send_response(status)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            return io.BytesIO(body)
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
        # Safari plays a video only from a server that answers byte ranges,
        # as Cloudflare Pages does.
        ranged = RANGE_RE.fullmatch(self.headers.get('Range', ''))
        if ranged and (ranged.group(1) or ranged.group(2)):
            data = target.read_bytes()
            first, last = ranged.groups()
            if first:
                start, end = int(first), min(int(last) if last else len(data) - 1, len(data) - 1)
            else:
                start, end = max(0, len(data) - int(last)), len(data) - 1
            if start > end:
                self.send_error(416)
                return None
            self.send_response(206)
            self.send_header('Content-Type', self.guess_type(str(target)))
            self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
            self.send_header('Content-Length', str(end - start + 1))
            self.end_headers()
            return io.BytesIO(data[start:end + 1])
        return super().send_head()


RANGE_RE = re.compile(r'bytes=(\d*)-(\d*)')
# What functions/add/[code].js and functions/join/[code].js match.
INVITE_PATH_RE = re.compile(r'/(add|join)/([^/]+)')


if __name__ == '__main__':
    build()
    if '--serve' in sys.argv:
        port = 8765
        print(f'serving http://localhost:{port}')
        http.server.ThreadingHTTPServer(('127.0.0.1', port), PagesHandler).serve_forever()
