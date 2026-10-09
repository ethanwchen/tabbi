"""Shared chrome for the site. Run build.py to regenerate the pages."""

from html import escape

ORIGIN = 'https://tabbinotch.com'
DOWNLOAD = 'https://github.com/ethanwchen/tabbi/releases/latest'
GITHUB = 'https://github.com/ethanwchen/tabbi'
ISSUES = 'https://github.com/ethanwchen/tabbi/issues'
SUPPORT_EMAIL = 'support@tabbinotch.com'

# Links are root-relative and extensionless, the way Cloudflare Pages serves
# them: /support answers with support.html, and /support.html redirects to
# /support. Writing the final form saves every click a redirect, and the
# root-relative paths keep 404.html working at any depth.
NAV = [
    ('/support', 'Support'),
]

BRAND = '<img src="/img/glyph.png" width="34" height="34" alt="" class="mark">'

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


def page(slug, title, description, body, hero=None, wide=False, indexable=True):
    def link(href, label):
        here = '/' + slug.removesuffix('.html')
        current = ' aria-current="page"' if href == here else ''
        return f'<a href="{href}"{current}>{label}</a>'

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
  <meta name="color-scheme" content="light dark">
  <meta name="theme-color" content="#F4D57E" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#2A231D" media="(prefers-color-scheme: dark)">
  <meta property="og:site_name" content="Tabbi">
  <meta property="og:title" content="{title_attr}">
  <meta property="og:description" content="{desc_attr}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="{url}">
  <meta property="og:image" content="{ORIGIN}/img/social-preview.png">
  <meta property="og:image:width" content="1280">
  <meta property="og:image:height" content="640">
  <meta property="og:image:alt" content="The Tabbi notch open on its Timer tab, above the Tabbi icon and name">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{title_attr}">
  <meta name="twitter:description" content="{desc_attr}">
  <meta name="twitter:image" content="{ORIGIN}/img/social-preview.png">
  <link rel="icon" href="/favicon.ico" sizes="48x48">
  <link rel="icon" href="/img/favicon-64.png" type="image/png" sizes="64x64">
  <link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600;700&family=Nunito:wght@400;600;700;800&display=swap">
  <link rel="stylesheet" href="/styles.css">
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
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
      <a href="{GITHUB}">GitHub</a>
    </nav>
    <p class="made">Made with care by <a href="https://www.linkedin.com/in/ethanwchen/">Ethan</a></p>
  </footer>
</body>
</html>
'''
