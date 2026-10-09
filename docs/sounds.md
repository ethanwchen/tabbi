# Sounds in Tabbi

Every sound Tabbi plays is either generated in code or comes from macOS.
The repository ships no audio recordings, so there is no third-party audio license to track.

## Focus sounds

The focus sounds (brown, pink and white noise, rain, fireplace and cafe) are synthesized sample by sample in `Sources/TabbiKitCore/Focus` and played by `FocusSoundEngine` in `Sources/TabbiKit/Audio`.
They are original code under Tabbi's MIT license, and so is everything they produce.
The recipes follow the layered approach in Andy Farnell's book "Designing Sound": a filtered-noise bed, slow random movement so nothing loops, and sparse events built from short bursts.

Every sound is calibrated to the same RMS level (`NoiseGenerator.targetRMS`), so layers mix predictably, and `FocusAmbienceTests` checks the level and character of each one.

### Cafe

The cafe is built to sound like people, not like a machine:

- Sixteen talkers at different distances, half with lower and half with higher voices.
  Each has a soft glottal pulse with a little breath, three formants that glide between real vowel shapes (Peterson and Barney's measurements), a pitch that lifts on stressed syllables and falls toward the end of a phrase, a consonant hiss at the start of most syllables, and pauses between phrases.
  The syllables are random, so no word is ever said.
- A small room reverb (a Schroeder design with Freeverb's delay lengths) that blends the voices into one murmur.
- A leveler that keeps the crowd at one steady loudness when a table sits close or everyone pauses at once.
- Low room tone, the odd cup set on a saucer and now and then a spoon stirring a mug.

## Notification and celebration sounds

Chimes such as the end of a focus block use the system sounds that come with macOS (`NSSound(named:)`), which apps may play under the macOS license.
