# UX pass 2 (October 2026)

A holistic look at Tabbi after the summer features landed (focus celebrations, presets, the shop, seasonal items, AI providers, SoundCloud, yesterday and tomorrow, the recap card, streak freeze, reminders, invites, feedback and moderation).
The goal is the same as the first pass: fantastic, smooth and simple.
Each entry is a short before and after.

## Now Playing

- Before: the like heart filled in the module accent, Spotify green, even for an Apple Music favorite or a SoundCloud like.
  After: a liked or favorited song's heart is pink-red in every player (`Theme.Palette.favorite`), the color people read as "loved".

## Onboarding

- Before: the pet step was wider than the panel, because ten breed tiles could not shrink below their sprite's canvas, so the pet card started left of the header and the right card ran past Skip Setup.
  After: breed tiles shrink to fit (the sprite's transparent margins are clipped), and both cards line up with the header and the footer.
- Before: onboarding ended on the last module setup step, so the desktop widget, the daily reminder, invite links and syncing the pet with Sign in with Apple were only found by exploring.
  After: one last, skippable screen, "A few extras", says each in a line (a tile per extra, only the ones whose tab is on), with a Sign In button on the sync tile that opens Settings > General.
  New extras join that one screen (`OnboardingExtra`), so onboarding never grows a step for them.

## Gestures

- Before: a two-finger swipe sideways switched tabs, but nothing put the open notch away from the trackpad; it took Esc, the shortcut or moving the pointer off.
  After: a two-finger swipe up closes the open notch with the usual close spring (`CloseSwipe`), once per gesture.
  A mouse wheel and momentum never close it, a swipe that starts over a list that can scroll scrolls the list instead, and onboarding stays open until it is done or skipped.
  The Shortcut footer in Settings > General mentions it.

## AI providers

- Before: picking an AI provider in Settings > Connections started sending to it at once, and nothing said what is sent or to whom (App Review Guideline 5.1.2(i) asks for both, and for permission).
  After: picking a provider that answers from outside the Mac asks first, "Share with Anthropic?" (or OpenAI, or Google), naming what Ask, Plan my day and Refine send, with Use and Cancel.
  Ollama runs on the Mac and asks nothing, switching between two providers of one company asks nothing new, and the section footer keeps a short "Sends what you ask to Google." line.

## Settings sounds

- Before: Focus offered a Preview button for its sound, but the Celebration sound and Haptic feedback switches under General > More options gave no hint of what they add, so turning one on meant waiting for the next celebration.
  After: turning Celebration sound on plays its soft pop once, and turning Haptic feedback on taps the trackpad once, the way macOS previews an alert sound when you pick it.
  No extra button, so the section stays as short as before.

## Closet at Compact

- Before: with all five sections on, the Compact Closet header did not fit, so the points chip showed a bare star with no number, and the whole panel ran about 2pt past the canvas on each side, clipping both cards' borders.
  The tightest header variant asked for narrower pills, but the pills ignored the request.
  After: tight pills and the header gaps shrink, the balance never truncates, and both cards line up with the header (x=104 to 1000 at 2x).
  A four-digit balance falls back to a header where the open section is its tinted symbol, so the number still shows.

## Focus at Compact

- Before: at Compact the Focus card dropped the names of its two settings to fit one line, leaving a moon and a bare "On" that did not say what was on.
  After: when one line is too narrow, the settings stack on two lines and keep their names ("Sound Rain + Fireplace", "Do Not Disturb On"), using the card's spare height.
  Only a panel too narrow for that drops the names, and VoiceOver reads each setting's name either way.
