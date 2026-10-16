import Foundation
@testable import TabbiKitCore
import XCTest

/// Pins how Tabbi writes lengths of time (`DurationFormat`) and spans of
/// days (`DateRangeFormat`) in every language it ships, to the golden
/// fixture `shared/fixtures/formatting/formatting.json`.
///
/// The Windows port formats the same durations and date ranges in each
/// language and compares with the recorded text, so a panel reads alike on
/// both apps. `DurationFormat` takes no language: it reads `Bundle.tabbi`
/// and `Locale.current`, which a process fixes once. So the fixture formats
/// durations through `FormattingDurationMirror`, the same catalog keys and
/// rules looked up in each language's compiled strings, and
/// `testDurationMirrorMatchesDurationFormat` keeps the mirror honest against
/// the real function in this process's language. Run with
/// `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class FormattingGoldenTests: XCTestCase {
    func testFormattingMatchesGoldenFixture() throws {
        let url = FormattingGoldenFixture.url
        let current = FormattingGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(FormattingGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Formatting constants changed")
        XCTAssertEqual(stored.languages, current.languages, "The shipped languages changed")
        XCTAssertEqual(stored.durations.inputs, current.durations.inputs, "Duration inputs changed")
        XCTAssertEqual(stored.durations.outputs.map(\.language), current.durations.outputs.map(\.language))
        for (old, new) in zip(stored.durations.outputs, current.durations.outputs) {
            XCTAssertEqual(old.minutes, new.minutes, "Durations in \(old.language): minutes")
            XCTAssertEqual(old.seconds, new.seconds, "Durations in \(old.language): seconds")
            XCTAssertEqual(old.countdown, new.countdown, "Durations in \(old.language): countdown")
            XCTAssertEqual(old.progress, new.progress, "Durations in \(old.language): progress")
            XCTAssertEqual(old.quantities, new.quantities, "Durations in \(old.language): quantities")
        }
        XCTAssertEqual(stored.dateRanges.cases, current.dateRanges.cases, "Date range cases changed")
        XCTAssertEqual(stored.dateRanges.outputs.map(\.language), current.dateRanges.outputs.map(\.language))
        for (old, new) in zip(stored.dateRanges.outputs, current.dateRanges.outputs) {
            for (index, (oldDays, newDays)) in zip(old.days, new.days).enumerated() {
                XCTAssertEqual(oldDays, newDays, "Date range \(stored.dateRanges.cases[index].name) in \(old.language)")
            }
            XCTAssertEqual(old, new, "Date ranges in \(old.language)")
        }
        XCTAssertEqual(stored, current, "Formatting no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// and the locale ids from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(FormattingGoldenFixture.self,
                                              from: Data(contentsOf: FormattingGoldenFixture.url))
        for output in stored.durations.outputs {
            let language = try XCTUnwrap(stored.languages.first { $0.language == output.language })
            XCTAssertEqual(FormattingGoldenFixture.durations(stored.durations.inputs, in: language), output,
                           "Durations in \(output.language)")
        }
        for output in stored.dateRanges.outputs {
            let language = try XCTUnwrap(stored.languages.first { $0.language == output.language })
            XCTAssertEqual(FormattingGoldenFixture.dateRanges(stored.dateRanges.cases, in: language), output,
                           "Date ranges in \(output.language)")
        }
    }

    /// The mirror the fixture formats durations with, given the strings and
    /// locale this process uses, writes exactly what `DurationFormat` does.
    /// It reads the process's language only to compare the two, and records
    /// nothing, so the check holds whatever language the machine runs in.
    func testDurationMirrorMatchesDurationFormat() {
        let inputs = FormattingGoldenFixture.durationInputs
        let mirror = FormattingDurationMirror(strings: .tabbi, locale: .current)
        for value in inputs.minutes {
            XCTAssertEqual(mirror.minutes(value), DurationFormat.minutes(value), "minutes(\(value))")
        }
        for value in inputs.seconds {
            XCTAssertEqual(mirror.seconds(value), DurationFormat.seconds(value), "seconds(\(value))")
        }
        for value in inputs.countdownMinutes {
            XCTAssertEqual(mirror.countdown(minutes: value), DurationFormat.countdown(minutes: value),
                           "countdown(minutes: \(value))")
        }
        for pair in inputs.progress {
            XCTAssertEqual(mirror.progress(pair.done, of: pair.total), DurationFormat.progress(pair.done, of: pair.total),
                           "progress(\(pair.done), of: \(pair.total))")
        }
        for quantity in inputs.quantities {
            XCTAssertEqual(mirror.quantity(quantity.value, unit: quantity.unit),
                           DurationFormat.quantity(quantity.value, unit: quantity.unit),
                           "quantity(\(quantity.value), unit: \(quantity.unit))")
        }
    }
}

/// `DurationFormat`, with the language passed in: each catalog key it uses
/// is looked up in one language's compiled strings and formatted with that
/// language's locale, which picks the plural form, as
/// `String(localized:bundle:)` does with `Locale.current`.
struct FormattingDurationMirror {
    let strings: Bundle
    let locale: Locale

    private func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: strings.localizedString(forKey: key, value: nil, table: nil), locale: locale, arguments: arguments)
    }

    func minutes(_ value: Int) -> String {
        let value = max(value, 0)
        guard value >= 60 else { return text("%lld min", value) }
        let hours = value / 60, rest = value % 60
        return rest == 0 ? text("%lldh", hours) : text("%lldh %lldm", hours, rest)
    }

    func progress(_ done: Int, of total: Int) -> String {
        let done = max(done, 0), total = max(total, 0)
        guard max(done, total) >= 60 else { return text("%@ of %@", minutes(done), minutes(total)) }
        return text("%@ of %@", compact(done), compact(total))
    }

    private func compact(_ value: Int) -> String {
        guard value >= 60 else { return text("%lldm", value) }
        return minutes(value)
    }

    func seconds(_ value: TimeInterval) -> String {
        guard value >= 60 else { return text("<1 min") }
        return minutes(Int((value / 60).rounded(.up)))
    }

    func countdown(minutes value: Int) -> String {
        text("in %@", minutes(value))
    }

    func quantity(_ value: Int, unit: String) -> String {
        switch unit {
        case DurationFormat.minuteUnit: minutes(value)
        case DurationFormat.cardUnit: text("%lld cards", value)
        default: "\(value.formatted(.number.locale(locale))) \(unit)"
        }
    }
}

/// Durations and date ranges, written in every shipped language.
struct FormattingGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.formatting.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/formatting/formatting.json")
    }

    struct Constants: Codable, Equatable {
        var minuteUnit: String
        var cardUnit: String
        var sourceLanguage: String
    }

    /// A shipped language: its `.lproj` name, the Foundation locale id the
    /// app runs it with (`--locale` sets `AppleLocale` to it), and the same
    /// locale as a BCP 47 tag for `Intl`.
    struct Language: Codable, Equatable {
        var language: String
        var locale: String
        var bcp47: String
    }

    // MARK: Durations

    struct Progress: Codable, Equatable {
        var done: Int
        var total: Int
    }

    struct Quantity: Codable, Equatable {
        var value: Int
        var unit: String
    }

    struct DurationInputs: Codable, Equatable {
        var minutes: [Int]
        var seconds: [Double]
        var countdownMinutes: [Int]
        var progress: [Progress]
        var quantities: [Quantity]
    }

    /// One language's text for each input, in input order.
    struct DurationOutputs: Codable, Equatable {
        var language: String
        var minutes: [String]
        var seconds: [String]
        var countdown: [String]
        var progress: [String]
        var quantities: [String]
    }

    struct Durations: Codable, Equatable {
        var inputs: DurationInputs
        var outputs: [DurationOutputs]
    }

    // MARK: Date ranges

    /// `DateRangeFormat.days(from: first, to: last)` in a Gregorian calendar
    /// in `timeZone` (an IANA name).
    struct DateRangeCase: Codable, Equatable {
        var name: String
        var timeZone: String
        var first: Double
        var last: Double
    }

    /// One language's text for each case, in case order.
    struct DateRangeOutputs: Codable, Equatable {
        var language: String
        var days: [String]
    }

    struct DateRanges: Codable, Equatable {
        var cases: [DateRangeCase]
        var outputs: [DateRangeOutputs]
    }

    var schema = Self.schemaName
    var version = 1
    var constants: Constants
    var languages: [Language]
    var durations: Durations
    var dateRanges: DateRanges

    static func current() -> FormattingGoldenFixture {
        let languages = L10n.languages.map { language in
            let identifier = language.replacingOccurrences(of: "-", with: "_")
            return Language(language: language, locale: identifier,
                            bcp47: Locale(identifier: identifier).identifier(.bcp47))
        }
        let cases = dateRangeCases()
        return FormattingGoldenFixture(
            constants: Constants(minuteUnit: DurationFormat.minuteUnit, cardUnit: DurationFormat.cardUnit,
                                 sourceLanguage: L10n.sourceLanguage),
            languages: languages,
            durations: Durations(inputs: durationInputs,
                                 outputs: languages.map { durations(durationInputs, in: $0) }),
            dateRanges: DateRanges(cases: cases, outputs: languages.map { dateRanges(cases, in: $0) })
        )
    }

    // MARK: Inputs

    /// Around every rounding edge and plural form: 0, 1, 2, 3, 5, 11, 21,
    /// 22 and 100 of a unit, under and over an hour, whole days (which stay
    /// hours), and negatives, which clamp to zero.
    static let durationInputs = DurationInputs(
        minutes: [-90, -1, 0, 1, 2, 3, 5, 11, 21, 22, 25, 45, 59, 60, 61, 62, 75, 90, 119, 120, 122, 125, 180, 300,
                  1260, 1281, 1320, 1440, 1441, 2880, 6000],
        seconds: [-3600, -1, -0.5, 0, 0.001, 1, 30, 59, 59.5, 59.999, 60, 60.001, 61, 89.5, 90, 119.5, 120, 3540,
                  3599, 3599.5, 3600, 3600.5, 3601, 3660, 5400, 7985, 86400, 90061, 259_200],
        countdownMinutes: [-5, 0, 1, 2, 12, 59, 60, 61, 94, 120, 1440],
        progress: [
            Progress(done: 20, total: 45), Progress(done: 0, total: 240), Progress(done: 45, total: 120),
            Progress(done: 64, total: 120), Progress(done: 75, total: 45), Progress(done: -3, total: 30),
            Progress(done: 0, total: 0), Progress(done: 1, total: 1), Progress(done: 2, total: 5),
            Progress(done: 59, total: 59), Progress(done: 59, total: 60), Progress(done: 60, total: 0),
            Progress(done: 0, total: 60), Progress(done: 120, total: 120), Progress(done: 21, total: 22),
        ],
        quantities: [
            Quantity(value: 75, unit: DurationFormat.minuteUnit), Quantity(value: 30, unit: DurationFormat.minuteUnit),
            Quantity(value: -5, unit: DurationFormat.minuteUnit),
            Quantity(value: 0, unit: DurationFormat.cardUnit), Quantity(value: 1, unit: DurationFormat.cardUnit),
            Quantity(value: 2, unit: DurationFormat.cardUnit), Quantity(value: 3, unit: DurationFormat.cardUnit),
            Quantity(value: 5, unit: DurationFormat.cardUnit), Quantity(value: 11, unit: DurationFormat.cardUnit),
            Quantity(value: 21, unit: DurationFormat.cardUnit), Quantity(value: 22, unit: DurationFormat.cardUnit),
            Quantity(value: 100, unit: DurationFormat.cardUnit), Quantity(value: 128, unit: DurationFormat.cardUnit),
            Quantity(value: 1234, unit: DurationFormat.cardUnit),
            Quantity(value: 12, unit: "questions"), Quantity(value: 1234, unit: "questions"),
            Quantity(value: 1_000_000, unit: "steps"),
        ]
    )

    /// Ranges in named zones: one day, across midnight, a month and a year,
    /// all-day events as calendars store them (end at the next midnight),
    /// reversed ends, and the days clocks change, north and south.
    static func dateRangeCases() -> [DateRangeCase] {
        func at(_ zone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                _ second: Int = 0) -> Double {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            return calendar.date(from: components)!.timeIntervalSince1970
        }
        func range(_ name: String, _ zone: String, _ first: Double, _ last: Double) -> DateRangeCase {
            DateRangeCase(name: name, timeZone: zone, first: first, last: last)
        }
        let newYork = "America/New_York", berlin = "Europe/Berlin", tokyo = "Asia/Tokyo"
        let sydney = "Australia/Sydney", saoPaulo = "America/Sao_Paulo", kolkata = "Asia/Kolkata"
        // The night New York's clocks fall back, 01:30 happens twice, an hour apart.
        let fallBackMidnight = at(newYork, 2026, 11, 1)
        return [
            range("same-instant", newYork, at(newYork, 2026, 10, 5, 9), at(newYork, 2026, 10, 5, 9)),
            range("same-day", newYork, at(newYork, 2026, 10, 5), at(newYork, 2026, 10, 5, 23, 59, 59)),
            range("crossing-midnight", newYork, at(newYork, 2026, 10, 5, 23, 30), at(newYork, 2026, 10, 6, 0, 30)),
            range("week", newYork, at(newYork, 2026, 10, 5), at(newYork, 2026, 10, 11)),
            range("crossing-month", newYork, at(newYork, 2026, 9, 28), at(newYork, 2026, 10, 4)),
            range("crossing-year", newYork, at(newYork, 2025, 12, 29), at(newYork, 2026, 1, 4)),
            range("several-years", newYork, at(newYork, 2024, 2, 29), at(newYork, 2026, 3, 1)),
            range("all-day-one-day", newYork, at(newYork, 2026, 10, 5), at(newYork, 2026, 10, 6)),
            range("all-day-three-days", newYork, at(newYork, 2026, 10, 30), at(newYork, 2026, 11, 2)),
            range("reversed", newYork, at(newYork, 2026, 10, 11), at(newYork, 2026, 10, 5)),
            range("dst-spring-forward-new-york", newYork, at(newYork, 2026, 3, 7, 12), at(newYork, 2026, 3, 9, 12)),
            range("dst-fall-back-new-york", newYork, at(newYork, 2026, 10, 31, 12), at(newYork, 2026, 11, 2, 12)),
            range("dst-repeated-hour-new-york", newYork, fallBackMidnight + 5400, fallBackMidnight + 9000),
            range("dst-spring-forward-berlin", berlin, at(berlin, 2026, 3, 28), at(berlin, 2026, 3, 30)),
            range("dst-southern-sydney", sydney, at(sydney, 2026, 10, 3), at(sydney, 2026, 10, 5)),
            range("missing-midnight-sao-paulo", saoPaulo, at(saoPaulo, 2018, 11, 3, 12), at(saoPaulo, 2018, 11, 5, 12)),
            range("zone-moves-the-days", tokyo, at(newYork, 2026, 10, 5, 20), at(newYork, 2026, 10, 11, 20)),
            range("half-hour-zone-crossing-month", kolkata, at(kolkata, 2026, 1, 31, 23, 45), at(kolkata, 2026, 2, 1, 0, 15)),
        ]
    }

    // MARK: Running

    static func durations(_ inputs: DurationInputs, in language: Language) -> DurationOutputs {
        let mirror = FormattingDurationMirror(strings: L10n.strings(for: language.language)!,
                                              locale: Locale(identifier: language.locale))
        return DurationOutputs(
            language: language.language,
            minutes: inputs.minutes.map { mirror.minutes($0) },
            seconds: inputs.seconds.map { mirror.seconds($0) },
            countdown: inputs.countdownMinutes.map { mirror.countdown(minutes: $0) },
            progress: inputs.progress.map { mirror.progress($0.done, of: $0.total) },
            quantities: inputs.quantities.map { mirror.quantity($0.value, unit: $0.unit) }
        )
    }

    static func dateRanges(_ cases: [DateRangeCase], in language: Language) -> DateRangeOutputs {
        let locale = Locale(identifier: language.locale)
        return DateRangeOutputs(language: language.language, days: cases.map { range in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: range.timeZone)!
            return DateRangeFormat.days(from: Date(timeIntervalSince1970: range.first),
                                        to: Date(timeIntervalSince1970: range.last),
                                        calendar: calendar, locale: locale)
        })
    }
}
