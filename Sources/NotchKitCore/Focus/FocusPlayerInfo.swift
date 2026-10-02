import Foundation

/// Reads the player state out of Spotify's and Music's playback
/// notifications, so focus mode can follow the music apps without sending
/// them Apple Events (which would launch an app that isn't running).
public enum FocusPlayerInfo {
    /// The distributed notification each app posts when playback changes.
    public static func notificationName(for source: MediaSource) -> Notification.Name {
        switch source {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .music: Notification.Name("com.apple.Music.playerInfo")
        }
    }

    /// The state in a notification's `userInfo`. Both apps send
    /// "Player State" as "Playing", "Paused" or "Stopped"; nil when missing
    /// or unrecognized.
    public static func state(from userInfo: [AnyHashable: Any]?) -> SpotifyPlayerState? {
        guard let value = userInfo?["Player State"] as? String else { return nil }
        return SpotifyPlayerState(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
