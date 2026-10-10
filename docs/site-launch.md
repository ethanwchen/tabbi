# tabbinotch.com launch checklist

What was verified on the site before launch, and how to verify it again.
Build with `python3 site/build.py` (it checks links, page weight and the release list) and run `scripts/check-style.sh`.
Browser checks use Playwright WebKit (from `~/Library/Caches/ms-playwright`) against `python3 site/build.py --serve`.

## Pages

- [x] Home, About, Support, Suggest, Thanks, Privacy, Terms, What's new, `/add/<code>`, `/join/<code>` and 404 all load with the right status (404 for an unknown path).
- [x] No horizontal scroll and no console errors at 1440, 1280, 1024, 834, 768, 430, 390, 360 and 320 px.
- [x] Thanks and 404 are `noindex`; every other page has a canonical URL.
- [x] Privacy and Terms wording belongs to `site/_legal.py` and was not changed here.

## Home

- [x] The hero clip plays, loops every 9 s and is 1200x750 (crisp at 2x in its 600 px frame).
- [x] Under reduced motion the `<source>` does not match, so the poster (the open Timer) shows and nothing plays.
- [x] Browsers without video get the animated WebP fallback.
- [x] The interactive notch demo leads; the closed-notch strip, How it works, More inside, trust stickers, FAQ and closing download band follow without repeating the demo's tabs.
- [x] Feature lines match the app: widget, recap and streak freezes, seasonal outfits, invites, AI providers, SoundCloud.
- [x] Weight: the page counts 266 KB, about 1.1 MB with the 504 KB video and the poster (budget 2.5 MB); every other page is about 110 to 125 KB.

## Third-party content

- [x] The hero clip, poster, social card and press kit show only fictional content (Timer, Today, Closet, Party).
- [x] The demo's Now Playing songs and bands are made up (`site/_demo.py`).
- [ ] The app's own demo data still names a real song and a real question bank; re-render the hero (`site/_hero_video.py`) if a future clip shows Now Playing or the Med School kit.

## Accessibility

- [x] Every focusable element gets a 3 px `:focus-visible` ring in the link color.
- [x] Buttons and nav links are at least 24 px tall; smaller targets are inline links inside sentences, which WCAG 2.5.8 exempts.
- [x] Every looping animation sits under `prefers-reduced-motion: no-preference`.

## Launch readiness

- [x] Download buttons point to `releases/latest/download/Tabbi.dmg`, the stable copy `scripts/release.sh` uploads with each release.
- [x] The version tag and What's new read the version from `Resources/Info.plist`, and the JSON-LD `softwareVersion` does too.
- [x] Open Graph and Twitter cards use the 1200x630 social image with alt text.
- [x] Favicons: `favicon.ico`, a 64 px PNG and the Apple touch icon.
- [x] `robots.txt` allows everything and points to `sitemap.xml`, which lists the seven public pages.
- [x] JSON-LD `SoftwareApplication` parses, and its image URLs carry the fingerprinted file names.
- [x] `_headers`: strict CSP (`default-src 'none'`, scripts, images, media, styles and fonts only from self, `form-action` limited to self and the invite worker, `frame-ancestors 'none'`), HSTS, nosniff and a year of immutable caching for `/img` and `/assets`.
- [x] The press kit ZIP (the icon at 1024 px and four tab screenshots, 1.6 MB) downloads from About.
- [x] `node --test site/test/*.mjs` passes (invite pages and the Suggest prefill).
