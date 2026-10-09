import Foundation

/// How close a usage window is to its limit; drives the ring color.
public enum ClaudeUsageLevel: Equatable, Sendable {
    /// Under 70%.
    case normal
    /// 70% up to 90%.
    case warning
    /// Above 90%.
    case critical

    public init(utilization: Double) {
        switch utilization {
        case ..<0.7: self = .normal
        case ...0.9: self = .warning
        default: self = .critical
        }
    }
}

/// Text formatting for the Claude Usage panel. Pure functions so they can be
/// tested with a fixed clock, calendar, and locale.
public enum ClaudeUsageFormat {
    /// Compact token count: 950, 12.3K, 1.2M, 3.4B. One decimal below 100 of
    /// a unit, none above, and never a trailing ".0".
    public static func compactTokens(_ count: Int) -> String {
        let value = Double(max(count, 0))
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        // Thresholds sit just below each unit so 999,950 reads "1M", not "1000K".
        for (size, suffix) in units where value >= size * 0.9995 {
            return number(value / size) + suffix
        }
        return String(Int(value))
    }

    private static func number(_ value: Double) -> String {
        if value >= 99.95 { return String(Int(value.rounded())) }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// Whole percent, clamped at 0 but allowed above 100 (over the limit).
    public static func percent(_ utilization: Double) -> String {
        "\(Int((max(utilization, 0) * 100).rounded()))%"
    }

    /// "resets in 2h 14m" when the reset is within a day, otherwise the
    /// weekday and time, e.g. "resets Thu 9:00".
    public static func resetDescription(
        resetsAt: Date?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "resets now" }
        if seconds < 24 * 3600 { return "resets in " + duration(seconds) }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
        return "resets " + resetsAt.formatted(style)
    }

    /// Short duration rounded up to the minute: "<1 min", "14 min", "2h 14m", "3h".
    public static func duration(_ seconds: TimeInterval) -> String {
        DurationFormat.seconds(seconds)
    }

    /// "Updated just now", "Updated 3m ago", "Updated 2h ago", "Updated 3d ago".
    public static func updatedDescription(fetchedAt: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(fetchedAt), 0)
        switch seconds {
        case ..<60: return "Updated just now"
        case ..<3600: return "Updated \(Int(seconds / 60))m ago"
        case ..<(24 * 3600): return "Updated \(Int(seconds / 3600))h ago"
        default: return "Updated \(Int(seconds / 86400))d ago"
        }
    }

    /// Human model name from an API model id:
    /// "claude-opus-4-5-20251101" → "Opus 4.5", "claude-3-5-sonnet-20241022" → "Sonnet 3.5".
    /// Unknown ids are returned unchanged.
    public static func modelName(_ id: String) -> String {
        var parts = id.lowercased().split(separator: "-").map(String.init)
        guard parts.first == "claude" else { return id }
        parts.removeFirst()
        // Drop a trailing date stamp (YYYYMMDD) and context suffixes like "[1m]".
        parts = parts.filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        guard let familyIndex = parts.firstIndex(where: { $0.first?.isLetter == true }) else { return id }
        let family = parts[familyIndex].replacingOccurrences(of: "[1m]", with: "")
        let version = parts.enumerated()
            .filter { $0.offset != familyIndex }
            .map { $0.element.replacingOccurrences(of: "[1m]", with: "") }
            .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard !family.isEmpty else { return id }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
    }
}
