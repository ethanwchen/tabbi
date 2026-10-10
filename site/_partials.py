"""Shared chrome for the site. Run build.py to regenerate the pages."""

from html import escape

ORIGIN = 'https://tabbinotch.com'
# The newest DMG itself: every release also uploads it as Tabbi.dmg (scripts/release.sh).
DOWNLOAD = 'https://github.com/ethanwchen/tabbi/releases/latest/download/Tabbi.dmg'
RELEASES = 'https://github.com/ethanwchen/tabbi/releases'
GITHUB = 'https://github.com/ethanwchen/tabbi'
ISSUES = 'https://github.com/ethanwchen/tabbi/issues'
SUPPORT_EMAIL = 'support@tabbinotch.com'
# The friends backend's suggestion inbox. The Suggest form posts here and the
# backend answers with a redirect to /thanks; _headers' form-action allows
# this origin, plus 'self' for that redirect, which browsers check too.
SUGGESTIONS = 'https://tabbi-friends.drosophil-anki-friends-backend.workers.dev/v1/suggestions'

# Links are root-relative and extensionless, the way Cloudflare Pages serves
# them: /support answers with support.html, and /support.html redirects to
# /support. Writing the final form saves every click a redirect, and the
# root-relative paths keep 404.html working at any depth.
NAV = [
    ('/about', 'About'),
    ('/support', 'Support'),
    (DOWNLOAD, 'Download'),
]

BRAND = '<img src="/img/icon-256.webp" width="36" height="36" alt="" class="mark">'

# A download arrow, drawn inline so it costs no request and takes the
# button's text color in both themes.
DOWNLOAD_ICON = (
    '<svg class="ico" viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">'
    '<path d="M10 3v9.2m0 0 3.6-3.6M10 12.2 6.4 8.6M4 15.5h12" fill="none" '
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
)

# A small paw, the site's one decoration besides the cat itself.
PAW = (
    '<svg class="paw" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">'
    '<g fill="currentColor"><ellipse cx="12" cy="16.2" rx="5" ry="4.3"/>'
    '<ellipse cx="5.2" cy="10.4" rx="2.2" ry="2.7"/><ellipse cx="9.3" cy="6.2" rx="2.2" ry="2.8"/>'
    '<ellipse cx="14.7" cy="6.2" rx="2.2" ry="2.8"/><ellipse cx="18.8" cy="10.4" rx="2.2" ry="2.7"/></g></svg>'
)


def download_button():
    return f'<a class="btn" href="{DOWNLOAD}">{DOWNLOAD_ICON}<span>Download for Mac</span></a>'


def canonical(slug):
    if slug == 'index.html':
        return ORIGIN + '/'
    return ORIGIN + '/' + slug.removesuffix('.html')


def page(slug, title, description, body, hero=None, wide=False, indexable=True, head=''):
    def link(href, label):
        here = '/' + slug.removesuffix('.html')
        current = ' aria-current="page"' if href == here else ''
        cls = ' class="nav-cta"' if href == DOWNLOAD else ''
        return f'<a href="{href}"{current}{cls}>{label}</a>'

    nav = '\n        '.join(link(href, label) for href, label in NAV)
    hero_html = ''
    if hero:
        hero_html = f'''
  <section class="hero{' hero-home' if hero.get('home') else ''}">
    <div class="wrap">
      <div class="hero-copy">
        {hero.get("eyebrow", "")}
        <h1>{hero["title"]}</h1>
        <p class="lede">{hero["subtitle"]}</p>
        {hero.get("cta", "")}
      </div>
      {hero.get("art", "")}
    </div>
  </section>
'''
    title_attr = escape(title)
    desc_attr = escape(description)
    url = canonical(slug)
    robots = '' if indexable else '\n  <meta name="robots" content="noindex">'
    canonical_tag = f'\n  <link rel="canonical" href="{url}">' if indexable else ''
    return f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title_attr}</title>
  <meta name="description" content="{desc_attr}">{robots}{canonical_tag}
  <meta name="color-scheme" content="dark">
  <meta name="theme-color" content="#2A231D">
  <meta property="og:site_name" content="Tabbi">
  <meta property="og:title" content="{title_attr}">
  <meta property="og:description" content="{desc_attr}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="{url}">
  <meta property="og:image" content="{ORIGIN}/img/social-preview.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="The Tabbi icon and the line A little cat for your notch, beside a laptop with the Timer tab open in its notch">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{title_attr}">
  <meta name="twitter:description" content="{desc_attr}">
  <meta name="twitter:image" content="{ORIGIN}/img/social-preview.png">
  <meta name="twitter:image:alt" content="The Tabbi icon and the line A little cat for your notch, beside a laptop with the Timer tab open in its notch">
  <link rel="icon" href="/favicon.ico" sizes="48x48">
  <link rel="icon" href="/img/favicon-64.png" type="image/png" sizes="64x64">
  <link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
  <link rel="preload" href="/fonts/fredoka-600.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="preload" href="/fonts/nunito.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="/styles.css">{head}
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="site">
    <div class="wrap">
      <a class="brand" href="/">
        {BRAND}
        <span class="name">Tabbi</span>
      </a>
      <nav class="site" aria-label="Main">
        {nav}
      </nav>
    </div>
  </header>
{hero_html}
  <main id="main"{' class="home"' if wide else ''}>
    <div class="wrap">
{body if wide else '      <div class="sheet">' + body + '      </div>'}
    </div>
  </main>

  <footer class="site">
    <nav class="wrap" aria-label="More">
      <a href="/support">Support</a>
      <a href="/suggest">Suggest</a>
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
      <a href="{RELEASES}">What&rsquo;s new</a>
      <a href="{GITHUB}">GitHub</a>
      <a href="https://buymeacoffee.com/ethanpolar">Buy me a coffee</a>
    </nav>
    <p class="made">Made with care by <a href="https://www.linkedin.com/in/ethanwchen/">Ethan</a>
      <span class="socials">
        <a class="social" href="https://www.linkedin.com/in/ethanwchen/" aria-label="Ethan on LinkedIn"><svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M20.45 20.45h-3.55v-5.57c0-1.33-.03-3.04-1.85-3.04-1.86 0-2.14 1.45-2.14 2.94v5.67H9.36V9h3.41v1.56h.05c.47-.9 1.64-1.85 3.37-1.85 3.6 0 4.27 2.37 4.27 5.46v6.28zM5.34 7.43a2.06 2.06 0 110-4.12 2.06 2.06 0 010 4.12zM7.12 20.45H3.56V9h3.56v11.45zM22.22 0H1.77C.79 0 0 .77 0 1.73v20.54C0 23.23.79 24 1.77 24h20.45c.98 0 1.78-.77 1.78-1.73V1.73C24 .77 23.2 0 22.22 0z"/></svg></a>
        <a class="social" href="https://x.com/1ethain" aria-label="Ethan on X (@1ethain)"><svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><path fill="currentColor" d="M18.24 2.25h3.31l-7.23 8.26 8.5 11.24h-6.66l-5.21-6.82-5.97 6.82H1.67l7.73-8.84L1.25 2.25h6.83l4.71 6.23 5.45-6.23zm-1.16 17.52h1.83L7.08 4.13H5.12l11.96 15.64z"/></svg></a>
      </span>
    </p>
  </footer>
</body>
</html>
'''
