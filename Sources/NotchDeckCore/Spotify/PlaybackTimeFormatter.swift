import Foundation

/// Formats track times as `m:ss` (or `h:mm:ss` for long episodes).
public enum PlaybackTimeFormatter {
    public static func string(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(Int(seconds.rounded(.down)), 0) : 0
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Time left, prefixed with a minus sign (`-1:05`).
    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        "-" + string(max(duration - position, 0).rounded(.up))
    }
}
