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
