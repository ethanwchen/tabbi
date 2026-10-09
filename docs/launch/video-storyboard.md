# Demo video storyboard

A 20 second, silent, looping video for X, LinkedIn, Product Hunt and Reddit.
It is 1920 x 1080 (16:9) at 30 fps, and it reads with the sound off, so every shot carries one short caption.

Every frame comes from the app's demo snapshots (`TABBI_DEMO=1 swift run Tabbi --snapshot <folder> --kit medicine`), so it shows the real UI with sample data and nothing personal.
Shots use the snapshots named in brackets.

| # | Time | Shot | Caption |
| --- | --- | --- | --- |
| 1 | 0.0 - 2.5 s | The closed notch on a dark desktop, the pixel cat beside it [`closed-pet`]. Slow push in. | A little cat for your laptop notch. |
| 2 | 2.5 - 3.0 s | The notch springs open into the Timer tab [`closed-pet` to `open-study`]. | |
| 3 | 3.0 - 6.0 s | Timer, a Pomodoro counting down [`open-study`]. | A focus timer that never hides behind a window. |
| 4 | 6.0 - 9.0 s | Today: tasks and the next meeting [`open-planner`]. | Your tasks and what's next, at a glance. |
| 5 | 9.0 - 12.0 s | Anki, cards due today [`open-anki`]. | Anki cards due, one click to study. |
| 6 | 12.0 - 15.0 s | Party, friends focusing together [`open-party`]. | Study with friends. |
| 7 | 15.0 - 17.5 s | The Closet, the cat in an outfit [`open-closet`]. | Your cat earns outfits as you study. |
| 8 | 17.5 - 18.0 s | The notch closes back to the cat [`open-closet` to `closed-pet`]. | |
| 9 | 18.0 - 20.0 s | The closed notch again, with the icon and the link fading in below. | Free and open source. tabbinotch.com |

## Look

- The same dark, wallpaper-like backdrop as the README images, so the video and the screenshots match.
- Captions in SF Pro Rounded, white at 90% opacity, centered under the notch, one line each.
- Tabs switch with a cut, like the hero GIF: a crossfade between two busy panels reads as a double exposure.
- Opening and closing use a short eased grow, never a linear one.
- The last frame matches the first, so the loop is seamless.

## Variants

- `tabbi-demo.mp4`: 1920 x 1080, for X, LinkedIn and Product Hunt.
- `tabbi-demo-square.mp4`: 1080 x 1080, for feeds that crop to a square, if needed.

Both go in `docs/launch/video/`.
