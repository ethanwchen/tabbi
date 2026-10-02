import Foundation

/// Merges the state of every player app into the one the panel shows.
///
/// Rules, in order: a playing app wins (if several play, the one that started
/// most recently); otherwise the app that was playing most recently; then an
/// app with a track loaded or something actionable to show (permission,
/// connecting); then the current selection, so the panel doesn't flip
/// between equally idle apps. Apps that aren't running are never selected.
public struct MediaSourceTracker: Equatable, Sendable {
    public private(set) var statuses: [MediaSource: SpotifyStatus] = [:]
    /// The app the panel follows; nil while no player app is running.
    public private(set) var selected: MediaSource?
    /// When each app last went from not playing to playing.
    private var playingSince: [MediaSource: Date] = [:]
    /// The last moment each app was known to be playing.
    private var lastPlaying: [MediaSource: Date] = [:]

    public init() {}

    /// Records `source`'s newest status, observed at `date`, and reselects.
    public mutating func update(_ source: MediaSource, status: SpotifyStatus, at date: Date) {
        let wasPlaying = statuses[source]?.isPlaying ?? false
        if status.isPlaying {
            if !wasPlaying { playingSince[source] = date }
            lastPlaying[source] = date
        } else if wasPlaying {
            // It played right up until this observation.
            lastPlaying[source] = date
        }
        statuses[source] = status
        selected = select()
    }

    /// What the panel shows: the selected app's status, or, with no player
    /// running, `notRunning` when any known app is installed.
    public var status: SpotifyStatus {
        if let selected, let status = statuses[selected] { return status }
        return statuses.values.contains(.notRunning) ? .notRunning : .notInstalled
    }

    /// Apps that are installed (known from their last status).
    public var installedSources: [MediaSource] {
        MediaSource.allCases.filter { source in
            guard let status = statuses[source] else { return false }
            return status != .notInstalled
        }
    }

    private func select() -> MediaSource? {
        let running = MediaSource.allCases.filter { statuses[$0]?.isRunning ?? false }
        let playing = running.filter { statuses[$0]?.isPlaying ?? false }
        if !playing.isEmpty {
            return best(of: playing) { playingSince[$0] }
        }
        return best(of: running) { lastPlaying[$0] }
    }

    /// The candidate with the newest date; ties go to the more useful status,
    /// then the current selection, then `MediaSource.allCases` order.
    private func best(of candidates: [MediaSource], date: (MediaSource) -> Date?) -> MediaSource? {
        candidates.enumerated().max { lhs, rhs in
            rank(lhs.element, order: lhs.offset, date: date) < rank(rhs.element, order: rhs.offset, date: date)
        }?.element
    }

    private func rank(_ source: MediaSource, order: Int,
                      date: (MediaSource) -> Date?) -> (Double, Int, Int, Int) {
        let time = date(source)?.timeIntervalSinceReferenceDate ?? -.infinity
        return (time, statuses[source]?.usefulness ?? 0, source == selected ? 1 : 0, -order)
    }
}

extension SpotifyStatus {
    /// The app's process is running (any state but not running/installed).
    public var isRunning: Bool {
        switch self {
        case .notInstalled, .notRunning: false
        case .connecting, .permissionDenied, .connected: true
        }
    }

    /// How much an idle app has to show, for breaking selection ties.
    fileprivate var usefulness: Int {
        switch self {
        case .notInstalled, .notRunning: 0
        case .connected(let playback): playback.track == nil ? 1 : 4
        case .connecting: 2
        case .permissionDenied: 3
        }
    }
}
