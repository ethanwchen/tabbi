import Foundation

/// A browser Tabbi can find SoundCloud in. SoundCloud has no Mac app, so
/// its web player is read and controlled through the browser's AppleScript,
/// which runs JavaScript in the SoundCloud tab. Both browsers only allow
/// that once the user turns on "Allow JavaScript from Apple Events".
public enum SoundCloudBrowser: String, CaseIterable, Equatable, Hashable, Sendable {
    case safari
    case chrome

    public var bundleIdentifier: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        }
    }

    public var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        }
    }

    /// Where the user turns on JavaScript from Apple Events, for the panel's hint.
    public var javaScriptSettingPath: String {
        switch self {
        case .safari: "Develop > Allow JavaScript from Apple Events"
        case .chrome: "View > Developer > Allow JavaScript from Apple Events"
        }
    }

    /// The AppleScript phrase that runs `javaScript` (an AppleScript string
    /// literal) in the tab held by the variable `tabVariable`.
    fileprivate func run(_ javaScript: String, in tabVariable: String) -> String {
        switch self {
        case .safari: "do JavaScript \(javaScript) in \(tabVariable)"
        case .chrome: "execute \(tabVariable) javascript \(javaScript)"
        }
    }
}

/// What a SoundCloud script found in one browser.
public enum SoundCloudReading: Equatable, Sendable {
    /// No soundcloud.com tab is open.
    case noTab
    /// A SoundCloud tab is open, but the browser refuses to run JavaScript
    /// from Apple Events, so Tabbi can neither read nor control it.
    case javaScriptOff
    /// The web player's state. `stopped` means the tab has nothing loaded.
    case playback(SpotifyPlayback)
}

/// The scripts that read and control the SoundCloud web player in a browser
/// tab, and the parser for their output.
///
/// Each script picks the tab the same way: the first soundcloud.com tab that
/// is playing, else the first soundcloud.com tab. So a command reaches the
/// tab the panel shows. Everything goes through the player bar at the bottom
/// of every SoundCloud page (`.playControls`), the one part of the page that
/// is the same on every route; its buttons are clicked like a user would.
public enum SoundCloudScript {
    /// Prefix for track ids, so a SoundCloud path never collides with a
    /// Spotify URI or a Music persistent ID.
    public static let trackIDPrefix = "soundcloud:"
    /// Returned instead of a record when no soundcloud.com tab is open.
    static let noTabMarker = "no-tab"
    /// Returned when the browser won't run JavaScript from Apple Events.
    static let javaScriptOffMarker = "javascript-off"

    /// Returns `no-tab`, `javascript-off`, `stopped`, or every field below
    /// separated by U+001F: state (`playing` / `paused`), track id (the
    /// track's path), title, artist, artwork url, duration (s), position (s),
    /// shuffling, repeat (`off` / `one` / `all`), liked (`true` / `false`, or
    /// empty when signed out, since liking then only opens a sign-in prompt).
    public static func readState(in browser: SoundCloudBrowser) -> String {
        script(.read, in: browser)
    }

    public static func playPause(in browser: SoundCloudBrowser) -> String {
        script(.playPause, in: browser)
    }

    public static func nextTrack(in browser: SoundCloudBrowser) -> String {
        script(.next, in: browser)
    }

    public static func previousTrack(in browser: SoundCloudBrowser) -> String {
        script(.previous, in: browser)
    }

    /// Jumps to `seconds` into the track `trackID` names, by clicking the
    /// timeline at that point. Does nothing once another track is playing.
    public static func seek(to seconds: TimeInterval, forTrackID trackID: String,
                            in browser: SoundCloudBrowser) -> String {
        script(.seek(seconds: max(seconds, 0), trackID: trackID), in: browser)
    }

    /// Likes or unlikes the track `trackID` names; pinned to it like `seek`.
    public static func setLiked(_ isLiked: Bool, forTrackID trackID: String,
                                in browser: SoundCloudBrowser) -> String {
        script(.like(isLiked, trackID: trackID), in: browser)
    }

    public static func setShuffle(_ isOn: Bool, in browser: SoundCloudBrowser) -> String {
        script(.shuffle(isOn), in: browser)
    }

    /// SoundCloud's repeat button steps off, one, all; this clicks it until
    /// it shows `mode`.
    public static func setRepeat(_ mode: MediaRepeatMode, in browser: SoundCloudBrowser) -> String {
        script(.repeatMode(mode), in: browser)
    }

    /// Parses the output of any SoundCloud script. Nil for unrecognized output.
    public static func parse(_ output: String) -> SoundCloudReading? {
        let fields = output.split(separator: SpotifyScript.fieldSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard let first = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if fields.count == 1 {
            switch first {
            case noTabMarker: return .noTab
            case javaScriptOffMarker: return .javaScriptOff
            case "stopped": return .playback(.nothingPlaying)
            default: return nil
            }
        }
        guard fields.count == 10, let state = SpotifyPlayerState(rawValue: first), state != .stopped,
              let liked = liked(fields[9]) else { return nil }
        let path = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else { return nil }

        let artwork = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let track = SpotifyTrack(
            id: trackIDPrefix + path,
            title: fields[2],
            artist: fields[3],
            album: "",
            artworkURL: artwork.hasPrefix("https://") ? URL(string: artwork) : nil,
            duration: max(number(fields[5]) ?? 0, 0),
            isFavorite: liked
        )
        var playback = SpotifyPlayback(
            state: state, track: track, position: 0,
            isShuffling: fields[7].trimmingCharacters(in: .whitespaces) == "true",
            repeatMode: MediaRepeatMode(scriptValue: fields[8])
        )
        playback.position = playback.clampedPosition(number(fields[6]) ?? 0)
        return .playback(playback)
    }

    // MARK: - Building scripts

    /// One thing a script does in the SoundCloud tab.
    enum Action: Equatable {
        case read
        case playPause
        case next
        case previous
        case seek(seconds: TimeInterval, trackID: String)
        case like(Bool, trackID: String)
        case shuffle(Bool)
        case repeatMode(MediaRepeatMode)

        /// The `player(action, value, pin)` call for this action.
        var call: String {
            switch self {
            case .read: "player('read', null, '')"
            case .playPause: "player('playpause', null, '')"
            case .next: "player('next', null, '')"
            case .previous: "player('previous', null, '')"
            case .seek(let seconds, let trackID):
                "player('seek', \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)), \(pin(trackID)))"
            case .like(let isLiked, let trackID): "player('like', \(isLiked), \(pin(trackID)))"
            case .shuffle(let isOn): "player('shuffle', \(isOn), '')"
            case .repeatMode(let mode): "player('repeat', '\(mode.rawValue)', '')"
            }
        }

        /// The track's path as a JavaScript string literal, or `''` (no pin)
        /// for an id that isn't a SoundCloud one.
        private func pin(_ trackID: String) -> String {
            guard trackID.hasPrefix(SoundCloudScript.trackIDPrefix),
                  let data = try? JSONEncoder().encode(String(trackID.dropFirst(SoundCloudScript.trackIDPrefix.count))),
                  let literal = String(data: data, encoding: .utf8)
            else { return "'-'" }
            return literal
        }
    }

    /// The web player as one function, so every action reads the page the
    /// same way. `pin` is the path of the track a seek or like is meant for;
    /// the action is skipped when another track is playing by then.
    /// Commands return `ok`; the controller reads the state afterwards.
    static let player = """
    function player(action, value, pin) {
      var q = function (s) { return document.querySelector(s); };
      var link = q('.playbackSoundBadge__titleLink');
      var path = link ? (link.getAttribute('href') || '').split('?')[0] : '';
      var pinned = pin === '' || pin === path;
      var play = q('.playControls__play');
      var playing = !!play && play.classList.contains('playing');
      var shuffle = q('button.shuffleControl');
      var repeatButton = q('button.repeatControl');
      var like = q('.playbackSoundBadge__like');
      var bar = q('.playbackTimeline__progressWrapper');
      var duration = bar ? Number(bar.getAttribute('aria-valuemax')) || 0 : 0;
      var repeatMode = function () {
        if (!repeatButton) return 'off';
        if (repeatButton.classList.contains('m-one')) return 'one';
        if (repeatButton.classList.contains('m-all')) return 'all';
        return 'off';
      };
      var click = function (element) { if (element) element.click(); };
      if (action === 'isplaying') return playing && !!link ? 'true' : 'false';
      if (action === 'playpause') click(play);
      if (action === 'next') click(q('.skipControl__next'));
      if (action === 'previous') click(q('.skipControl__previous'));
      if (action === 'seek' && pinned && bar && duration > 0) {
        var box = bar.getBoundingClientRect();
        var x = box.left + box.width * Math.min(Math.max(value / duration, 0), 1);
        var y = box.top + box.height / 2;
        ['mousedown', 'mouseup', 'click'].forEach(function (type) {
          bar.dispatchEvent(new MouseEvent(type, { bubbles: true, clientX: x, clientY: y, button: 0 }));
        });
      }
      if (action === 'like' && pinned && like && like.classList.contains('sc-button-selected') !== value) click(like);
      if (action === 'shuffle' && shuffle && shuffle.classList.contains('m-shuffling') !== value) click(shuffle);
      if (action === 'repeat' && repeatButton) {
        var order = ['off', 'one', 'all'];
        var steps = (order.indexOf(value) - order.indexOf(repeatMode()) + 3) % 3;
        for (var i = 0; i < steps; i++) click(repeatButton);
      }
      if (action !== 'read') return 'ok';
      if (!link || !path) return 'stopped';
      var title = link.getAttribute('title') || link.textContent.trim();
      var artistLink = q('.playbackSoundBadge__lightLink');
      var artist = artistLink ? (artistLink.getAttribute('title') || artistLink.textContent.trim()) : '';
      var artwork = '';
      var metadata = navigator.mediaSession && navigator.mediaSession.metadata;
      if (metadata && metadata.title === title && metadata.artwork && metadata.artwork.length) {
        artwork = metadata.artwork[0].src;
      } else {
        var cover = q('.playbackSoundBadge__avatar span.sc-artwork');
        var parts = cover ? cover.style.backgroundImage.split('"') : [];
        if (parts.length > 1) artwork = parts[1].replace(/-t[0-9]+x[0-9]+[.]/, '-t500x500.');
      }
      var signedOut = !!q('.header__loginMenu');
      var liked = signedOut || !like ? '' : String(like.classList.contains('sc-button-selected'));
      var position = bar ? Number(bar.getAttribute('aria-valuenow')) || 0 : 0;
      return [playing ? 'playing' : 'paused', path, title, artist, artwork, duration, position,
              String(!!shuffle && shuffle.classList.contains('m-shuffling')), repeatMode(), liked]
        .join(String.fromCharCode(31));
    }
    """

    /// The full AppleScript for `action` in `browser`: find the tab, then
    /// run the player function there.
    static func script(_ action: Action, in browser: SoundCloudBrowser) -> String {
        let probe = appleScriptLiteral(player + "\nplayer('isplaying', null, '');")
        let command = appleScriptLiteral(player + "\n" + action.call + ";")
        return """
        tell application id "\(browser.bundleIdentifier)"
            set target to missing value
            repeat with w in windows
                set found to false
                try
                    repeat with t in tabs of w
                        set u to ""
                        try
                            set u to (URL of t) as text
                        end try
                        if u starts with "https://soundcloud.com/" or u starts with "https://m.soundcloud.com/" then
                            if target is missing value then set target to contents of t
                            try
                                if (\(browser.run(probe, in: "t"))) is "true" then
                                    set target to contents of t
                                    set found to true
                                    exit repeat
                                end if
                            on error number n
                                if n is in {-1743, -600, -609, -1712} then error number n
                                return "\(javaScriptOffMarker)"
                            end try
                        end if
                    end repeat
                on error number n
                    if n is in {-1743, -600, -609, -1712} then error number n
                end try
                if found then exit repeat
            end repeat
            if target is missing value then return "\(noTabMarker)"
            set t to target
            try
                return (\(browser.run(command, in: "t"))) as text
            on error number n
                if n is in {-1743, -600, -609, -1712} then error number n
                return "\(javaScriptOffMarker)"
            end try
        end tell
        """
    }

    /// `text` as an AppleScript string literal.
    static func appleScriptLiteral(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// The liked field: `true`, `false`, or empty for "can't like". Anything
    /// else means the record is broken, so the outer optional is nil.
    private static func liked(_ text: String) -> Bool?? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": .some(true)
        case "false": .some(false)
        case "": .some(nil)
        default: nil
        }
    }

    private static func number(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
