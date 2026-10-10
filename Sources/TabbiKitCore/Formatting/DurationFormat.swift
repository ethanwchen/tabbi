import Foundation

/// The one way Tabbi writes a length of time, so every panel, the ticker
/// and Settings read alike: "45 min" under an hour, "2h" and "1h 15m"
/// above it, and "in 12 min" or "in 1h 15m" for something still to come.
/// Under an hour the word "min" reads friendlier than a bare "m"; above it
/// the compact form keeps narrow rows and the closed notch short.
public enum DurationFormat {
    /// The unit `ProgressItem`s count minutes in, which `quantity` writes as a duration.
    public static let minuteUnit = "min"

    /// "0 min", "45 min", "2h", "1h 15m". Negative values read as "0 min".
    public static func minutes(_ minutes: Int) -> String {
        let minutes = max(minutes, 0)
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Progress toward a length of time: "20 min of 45 min" under an hour,
    /// and "45m of 2h" or "1h 4m of 2h" once either side reaches one, so a
    /// single label never mixes the word "min" with the compact hours form.
    public static func progress(_ done: Int, of total: Int) -> String {
        let done = max(done, 0), total = max(total, 0)
        guard max(done, total) >= 60 else { return "\(minutes(done)) of \(minutes(total))" }
        return "\(compact(done)) of \(compact(total))"
    }

    /// "0m", "45m", "2h", "1h 15m": the hours form, also under an hour.
    private static func compact(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        return Self.minutes(minutes)
    }

    /// A span in seconds rounded up to the minute, with "<1 min" for less,
    /// so a countdown never claims nothing is left while something is.
    public static func seconds(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "<1 min" }
        return minutes(Int((seconds / 60).rounded(.up)))
    }

    /// "in 12 min", "in 1h", "in 1h 15m".
    public static func countdown(minutes value: Int) -> String {
        "in " + minutes(value)
    }

    /// A count in its own unit ("320 cards"), or a duration when the unit
    /// is `minuteUnit` ("1h 15m" rather than "75 min").
    public static func quantity(_ value: Int, unit: String) -> String {
        unit == minuteUnit ? minutes(value) : "\(value.formatted()) \(unit)"
    }
}
