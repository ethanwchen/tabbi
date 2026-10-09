# Launch day checklist

Nothing goes out until Ethan says go.
"Ethan" means Ethan does it by hand from his own accounts.
"Agent" means a coding agent can do it in the repo, with no posting anywhere.

## The week before

| Step | Who | Done when |
| --- | --- | --- |
| 1. Merge the launch README, images and these docs to `main`. | Agent opens the PR, Ethan merges | README on GitHub shows the hero GIF and badges. |
| 2. Re-render the README images and demo videos from the final `main` with `swift docs/make-screenshots.swift` (needs `ffmpeg`) and check every PNG. | Agent | `docs/images/` matches the current UI. |
| 3. Watch both videos in `docs/launch/video/` end to end (see [video-storyboard.md](video-storyboard.md)). | Ethan | Captions read with the sound off and the loop is seamless. |
| 4. Cut the release: run the Release workflow (`.github/workflows/release.yml`, Developer ID signing, Publish on), check the draft, then publish it. | Ethan | https://github.com/ethanwchen/tabbi/releases/latest has a signed, notarized DMG. |
| 5. Download the DMG on a clean Mac, install it, open it, pick a kit, run a timer. | Ethan | It opens with no Gatekeeper warning. |
| 6. Check `brew install --cask ethanwchen/tap/tabbi` installs the same version. | Ethan | `brew info tabbi` shows the new version. |
| 7. Check https://tabbinotch.com: download button, About, Support, Privacy, Terms. | Ethan | Every link works. |
| 8. Set the GitHub social preview to `docs/images/social-preview.png` (Settings > General). | Ethan | Sharing the repo link shows the image. |
| 9. Schedule the Product Hunt launch for 12:01 am Pacific, upload the gallery from [product-hunt.md](product-hunt.md). | Ethan | The listing preview looks right. |
| 10. Send the r/GetStudying modmail from [reddit.md](reddit.md). | Ethan | The mods have replied. |
| 11. Check r/macapps karma (10+) and the current sidebar rules. | Ethan | Eligible for the main feed, or ready for the megathread. |

## Launch day (US Pacific time)

| Time | Step | Who | Link |
| --- | --- | --- | --- |
| 12:01 am | Product Hunt goes live. Post the maker comment right away. | Ethan | https://www.producthunt.com |
| 7:00 am | Post Show HN, then the first comment from [show-hn.md](show-hn.md). | Ethan | https://news.ycombinator.com/submit |
| 8:00 am | Post the X thread from [x-thread.md](x-thread.md), with the video on the first post. | Ethan | https://x.com |
| 9:00 am | Post on LinkedIn from [linkedin.md](linkedin.md). | Ethan | https://www.linkedin.com |
| 10:00 am | Post on r/macapps from [reddit.md](reddit.md). | Ethan | https://www.reddit.com/r/macapps |
| All day | Reply to every comment on each post, kindly and briefly. | Ethan | |
| All day | Watch GitHub issues and support@tabbinotch.com for install problems. | Ethan, Agent fixes bugs | https://github.com/ethanwchen/tabbi/issues |

## The days after

| When | Step | Who |
| --- | --- | --- |
| Day 2 or later | Post on r/GetStudying, only if the mods said yes. | Ethan |
| Day 2 | Thank-you post on X with a short note on what people asked for. | Ethan |
| Week 1 | Turn the top requests into GitHub issues and update `docs/ROADMAP.md`. | Agent drafts, Ethan decides |
| Week 1 | Ship a small update with the first fixes, so early users see it improve. | Agent builds, Ethan releases |

## Rules for every post and reply

- First name only: Ethan.
- No emojis and no em dashes.
- Say "notch" or "laptop notch", not "MacBook".
- Never ask for upvotes, and never post the same text twice.
- Say "I made this" up front wherever self-promotion rules apply.

## Links

- Website: https://tabbinotch.com
- Repo: https://github.com/ethanwchen/tabbi
- Releases: https://github.com/ethanwchen/tabbi/releases/latest
- Issues: https://github.com/ethanwchen/tabbi/issues
- Coffee: https://buymeacoffee.com/ethanpolar
- Support: support@tabbinotch.com
- Press kit: [press-kit.md](press-kit.md)
