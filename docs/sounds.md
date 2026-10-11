# Sounds in Tabbi

Every sound Tabbi plays is generated in code, comes from macOS, or is one of the public domain recordings listed under [Recordings](#recordings).

## Focus sounds

Brown, pink and white noise, rain and the fireplace are synthesized sample by sample in `Sources/TabbiKitCore/Focus`, and the cafe is a recording played as a seamless loop (`FocusRecording`).
All of them are played by `FocusSoundEngine` in `Sources/TabbiKit/Audio`.
The synthesized sounds are original code under Tabbi's MIT license, and so is everything they produce.
The recipes follow the layered approach in Andy Farnell's book "Designing Sound": a filtered-noise bed, slow random movement so nothing loops, and sparse events built from short bursts.

Every sound is calibrated to the same RMS level (`NoiseGenerator.targetRMS`), so layers mix predictably, and `FocusAmbienceTests` checks the level and character of each one.
A recording is scaled to that level when it is decoded, so the level of the file itself does not matter.

Equal RMS is not equal loudness: the ear hears white noise's treble far more than brown noise's rumble, so at the same RMS white sounded about 8 dB louder than brown or the fireplace.
The mixer therefore trims each sound by `FocusSound.loudnessTrimDecibels` so all of them play at the same integrated loudness (ITU-R BS.1770, K-weighted and gated), and switching sounds or blending them never jumps in level.
`FocusLoudnessTests` measures that loudness through the mixer and fails if a sound drifts more than 1 LU from the target.

### Cafe

The cafe used to be synthesized too: sixteen formant-synthesized talkers in a small artificial reverb.
However careful the recipe, the result sat in the uncanny valley between a crowd and a machine.
The talkers buzzed like robots, the room fell almost silent whenever they paused together, and everything above about 1 kHz was muffled, so it sounded ghostly rather than cozy.
It is now a real coffee shop, recorded.

The loop in `Sources/TabbiKitCore/Focus/FocusRecordings/cafe.m4a` was made from the recording below like this:

- It starts from Freesound's high-quality OGG rendition of the recording (Freesound needs an account to download the original WAV).
- The steadiest two minutes were picked (the fewest sudden sounds and the least change in level), skipping the first second.
- A gentle high-pass at 90 Hz removes rumble, and a narrow notch removes a steady 100 Hz hum.
- Cups and spoons that stand out of the room are softened, and a look-ahead limiter keeps every peak within 13.5 dB of the room's level, so nothing clinks out at you.
- The last 6 seconds are crossfaded (equal power) into the first 6, so the end flows straight into the start and the loop point cannot be heard.
- It is normalized to -17 LUFS integrated with true peaks under -2 dBTP and encoded as mono AAC-LC at 96 kb/s and 48 kHz, the rate the mixer plays at, by Apple's encoder, which records the encoder delay so the loop decodes to exactly 5,760,000 samples.

`FocusAmbienceTests` checks that the file ships, that the loop has no seam and that no second of it is much louder or quieter than the room.

The recording is decoded the first time a mix plays the cafe (about 40 ms) and kept in memory as 16-bit samples (about 11 MB), so a mix without it costs nothing.

## Recordings

| Sound | File | Source | Author | License |
| --- | --- | --- | --- | --- |
| Cafe murmur | `Sources/TabbiKitCore/Focus/FocusRecordings/cafe.m4a` | [Small coffee shop quiet.wav](https://freesound.org/people/JarredGibb/sounds/244915/) on Freesound | Jarred Gibb | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

CC0 dedicates a work to the public domain, so the recording may be used, changed and shipped in any app, the App Store included, with no attribution required.
It is credited here anyway, and the edited loop is shared under the same CC0 terms.

## Notification and celebration sounds

Chimes such as the end of a focus block use the system sounds that come with macOS (`NSSound(named:)`), which apps may play under the macOS license.
