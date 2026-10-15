# Formatting golden fixtures

Written by `Tests/TabbiKitCoreTests/FormattingGoldenTests.swift` from `DurationFormat` and `DateRangeFormat`, in all 12 languages `L10n.languages` ships.
They pin how Tabbi writes a length of time ("45 min", "1h 15m", "in 12 min", "20 min of 45 min", "320 cards") and a span of days ("Oct 5 - 11", "Sep 28 - Oct 4"), so the Windows port writes the same text in every language.

The file has `schema` (`tabbi.formatting.golden`) and `version` (1).
Times are seconds since 1970, duration inputs are minutes (or seconds for `seconds`), and every list of outputs is in the order of its inputs.

- `constants`: the unit names `quantity` treats specially (`minuteUnit` is `min`, `cardUnit` is `cards`) and the `sourceLanguage` (`en`), whose catalog keys are the English text.
- `languages`: each shipped language with its `.lproj` name (`language`), the Foundation locale id the app runs it with (`locale`, the `.lproj` name with `_` for `-`, as `--locale` sets `AppleLocale`), and that locale as a BCP 47 tag (`bcp47`) to hand to `Intl`.
- `durations.inputs`: sample values for each function.
  - `minutes` for `DurationFormat.minutes`, `seconds` for `DurationFormat.seconds`, `countdownMinutes` for `DurationFormat.countdown(minutes:)`, `progress` (`done`, `total`) for `DurationFormat.progress(_:of:)`, and `quantities` (`value`, `unit`) for `DurationFormat.quantity(_:unit:)`.
- `durations.outputs`: one entry per language, with `language` and the text for each input under `minutes`, `seconds`, `countdown`, `progress` and `quantities`.
- `dateRanges.cases`: each has a `name`, a `timeZone` (an IANA name), and the instants `first` and `last` given to `DateRangeFormat.days(from:to:)` with a Gregorian calendar in that zone.
- `dateRanges.outputs`: one entry per language, with `language` and the text for each case under `days`.

How the durations are made:

- `DurationFormat` takes no language: it looks its strings up in `Bundle.tabbi`, which is fixed once per process from the preferred languages, and formats them with `Locale.current`.
  So the test writes each language through `FormattingDurationMirror`, which runs the same rules and the same catalog keys against that language's compiled strings (`Localization/Strings/<language>.lproj`) and its locale.
  `testDurationMirrorMatchesDurationFormat` checks the mirror against the real `DurationFormat` in the test's own language, so the two cannot drift apart.
- The catalog keys are `%lld min`, `%lldh`, `%lldh %lldm`, `%lldm`, `<1 min`, `in %@`, `%@ of %@` and `%lld cards`.
  A port takes their translations from `Localizable.xcstrings` and fills them in the same way.
- Under an hour a value reads with the minute word (`%lld min`); from 60 it reads `%lldh` when the minutes are whole hours and `%lldh %lldm` otherwise.
  There is no day unit: 1440 minutes is `24h`.
- `seconds` rounds up to the next whole minute once the value is 60 or more (60.001 seconds is `2 min`), and anything under 60, including 0 and negatives, reads `<1 min`.
- `progress` clamps both sides to zero, then uses the minute word on both when both are under 60, and otherwise the compact form on both, where a side under an hour reads `%lldm` (`45m of 2h`).
- `countdown` wraps `minutes` in `in %@`, so a negative countdown reads as `in 0 min`.
- `quantity` writes `min` as a duration, `cards` as the plural `%lld cards`, and any other unit as the number in the locale's own grouping, a space, and the unit as given (never translated).

Which outputs come from the Mac's ICU:

- Every `dateRanges.outputs` string comes from Foundation's `DateIntervalFormatter` with the template `MMMd`, which is ICU's interval formatting with the locale's CLDR data on the Mac that recorded the fixture.
  A port should use `Intl.DateTimeFormat(bcp47, { month: "short", day: "numeric", timeZone })` with `formatRange`, and the year appears only when the two years differ, as ICU's interval patterns decide.
  Then, as `DateRangeFormat` does, it must replace thin spaces (U+2009) and narrow no-break spaces (U+202F) with plain spaces, and en dashes (U+2013) and em dashes (U+2014) with a hyphen.
  Other characters ICU writes are kept as they are, including no-break spaces (U+00A0), the full-width tilde in Japanese and Chinese, and any directional marks in Arabic.
  CLDR versions differ between ICU builds, so a mismatch that is only spacing or punctuation is an ICU difference, not a Tabbi rule.
- The plural form each language picks for `%lld cards` (one, few, many, two, zero, other) follows CLDR plural rules for the language's locale, which `Intl.PluralRules(bcp47)` gives too.
- Every number in the durations, the `%lld` inside a translated string as well as a `quantity` with any other unit (`1,234 questions`, `1.000.000 steps`), is written in the locale's own number format, which `Intl.NumberFormat(bcp47)` gives.
  The digits are Western in every shipped language, Arabic included, and only `quantity` values reach four digits, where the grouping shows: `1,234` in English, `1.234` in German, `1234` in Spanish (which groups only from five digits), a narrow no-break space (U+202F) in French and a no-break space (U+00A0) in Russian.
  These spaces are kept as ICU writes them, since only `DateRangeFormat` swaps spaces.
  Some ICU builds, including V8's, write Arabic-Indic digits for plain `ar`, so a port may need `ar-u-nu-latn` to get the recorded Western digits.
- In Arabic, Foundation wraps every string argument (`%@`, so each side of `%@ of %@` and the duration in `in %@`) in a first-strong isolate (U+2068) and a pop directional isolate (U+2069), so a port must add the same two marks around each one.
  The test checks the mirror against `DurationFormat` only in the language it runs in, so that Arabic behavior is Foundation's `String(format:locale:)`, and is assumed to match `String(localized:)` under an Arabic locale.

Rules the fixture pins that are easy to miss:

- `DateRangeFormat.days` shows `last` as the final day, so an all-day event stored with its end at the next midnight reads one day too long (`all-day-one-day` is `Oct 5 - 6`); callers pass the last day itself.
- A `last` before `first` shows `first` alone (`reversed`).
- The days are read in the case's own zone, so the same two instants can name different days in another zone (`zone-moves-the-days` is New York evenings shown in Tokyo).
- Days when clocks change (New York, Berlin, Sydney, and São Paulo's 2018 change, when midnight itself was skipped) still read as plain days.
- The app passes `Calendar.current`, so a user whose calendar is not Gregorian would see other dates; the fixture pins the Gregorian calendar only.
- `quantity` of -5 `min` clamps to `0 min`, as `minutes` does.

A port replays only the inputs and compares every recorded output.
