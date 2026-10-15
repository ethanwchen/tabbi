//! Now Playing on Windows: the system media session (Spotify, browsers and any
//! app that publishes one) through `GlobalSystemMediaTransportControlsSessionManager`.
//!
//! The UI reads a snapshot, sends controls, and turns a subscription on while
//! the Now Playing tab or the ticker needs it. The subscription listens to the
//! session's own change events (no polling) on one thread, folds bursts of
//! them together, and emits `media:changed` only when the snapshot differs.
//! Album art is scaled down to at most 256 px and sent as a JPEG data URL,
//! re-encoded only when the track changes. The conversions are pure and
//! tested below; the WinRT calls need a desktop session.

use crate::error::{HostError, HostResult};
use serde::{Deserialize, Serialize};
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex, Once};
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};
use windows::Foundation::TypedEventHandler;
use windows::Graphics::Imaging::{
    BitmapAlphaMode, BitmapDecoder, BitmapEncoder, BitmapInterpolationMode, BitmapPixelFormat,
    BitmapTransform, ColorManagementMode, ExifOrientationMode,
};
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as SessionManager,
};
use windows::Media::MediaPlaybackAutoRepeatMode;
use windows::Storage::Streams::{
    Buffer, DataReader, IRandomAccessStreamReference, InMemoryRandomAccessStream,
    InputStreamOptions,
};
use windows::Win32::System::Com::CoIncrementMTAUsage;

pub const EVENT: &str = "media:changed";

/// The longest side of the artwork sent to the UI, in pixels.
pub const THUMBNAIL_MAX: u32 = 256;

/// Change events arrive in bursts (a new track fires properties, playback and
/// timeline at once); one snapshot covers each burst.
const COALESCE: Duration = Duration::from_millis(120);

/// The playback state, the names of `GlobalSystemMediaTransportControlsSessionPlaybackStatus`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Status {
    Closed,
    Opened,
    Changing,
    Stopped,
    Playing,
    Paused,
}

impl Status {
    pub fn from_raw(value: i32) -> Self {
        match value {
            1 => Self::Opened,
            2 => Self::Changing,
            3 => Self::Stopped,
            4 => Self::Playing,
            5 => Self::Paused,
            _ => Self::Closed,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Repeat {
    None,
    Track,
    List,
}

impl Repeat {
    pub fn from_raw(mode: MediaPlaybackAutoRepeatMode) -> Option<Self> {
        match mode {
            MediaPlaybackAutoRepeatMode::None => Some(Self::None),
            MediaPlaybackAutoRepeatMode::Track => Some(Self::Track),
            MediaPlaybackAutoRepeatMode::List => Some(Self::List),
            _ => None,
        }
    }

    pub fn raw(self) -> MediaPlaybackAutoRepeatMode {
        match self {
            Self::None => MediaPlaybackAutoRepeatMode::None,
            Self::Track => MediaPlaybackAutoRepeatMode::Track,
            Self::List => MediaPlaybackAutoRepeatMode::List,
        }
    }
}

/// Which controls the playing app accepts right now.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Controls {
    pub play: bool,
    pub pause: bool,
    pub toggle: bool,
    pub next: bool,
    pub previous: bool,
    pub shuffle: bool,
    pub repeat: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaSnapshot {
    /// The app that owns the session, such as `Spotify.exe` or a browser's
    /// app id, so the UI can name and badge it.
    pub app_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    /// A `data:image/jpeg;base64,...` URL, at most 256 px on its longer side.
    pub thumbnail: Option<String>,
    pub status: Status,
    /// The position at `updatedAt`; while playing, the UI advances it itself.
    pub position_seconds: f64,
    /// Zero when the app does not report a timeline (a live stream).
    pub duration_seconds: f64,
    /// When the app last reported the position, in Unix milliseconds.
    pub updated_at: f64,
    pub shuffle: Option<bool>,
    pub repeat: Option<Repeat>,
    pub controls: Controls,
}

/// A control the UI sends.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Action {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    Shuffle { on: bool },
    Repeat { mode: Repeat },
}

/// WinRT `DateTime` ticks (100 ns since 1601-01-01 UTC) to Unix milliseconds.
pub fn unix_millis(universal_time: i64) -> f64 {
    const UNIX_EPOCH_TICKS: i64 = 116_444_736_000_000_000;
    (universal_time - UNIX_EPOCH_TICKS) as f64 / 10_000.0
}

/// Position and duration in seconds from the timeline's `TimeSpan`s (100 ns
/// units). The position counts from the start time and stays inside the
/// track when the app reports a duration.
pub fn timeline(start: i64, end: i64, position: i64) -> (f64, f64) {
    let duration = end.saturating_sub(start).max(0);
    let mut offset = position.saturating_sub(start).max(0);
    if duration > 0 {
        offset = offset.min(duration);
    }
    (offset as f64 / 1e7, duration as f64 / 1e7)
}

/// The size to scale an image to so its longer side is at most `max`,
/// keeping its shape and never scaling up.
pub fn fit(width: u32, height: u32, max: u32) -> (u32, u32) {
    let longer = width.max(height);
    if longer <= max || longer == 0 {
        return (width.max(1), height.max(1));
    }
    let scale = |side: u32| {
        ((u64::from(side) * u64::from(max) + u64::from(longer) / 2) / u64::from(longer)).max(1)
            as u32
    };
    (scale(width), scale(height))
}

/// Standard base64 with padding (RFC 4648).
pub fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for (i, shift) in [18u32, 12, 6, 0].into_iter().enumerate() {
            if i <= chunk.len() {
                out.push(char::from(ALPHABET[((n >> shift) & 63) as usize]));
            } else {
                out.push('=');
            }
        }
    }
    out
}

pub fn jpeg_data_url(bytes: &[u8]) -> String {
    format!("data:image/jpeg;base64,{}", base64(bytes))
}

/// What identifies a track's artwork, so it is only re-encoded on a new track.
type ArtKey = (String, String, String, String);

#[derive(Default)]
struct ArtCache(Mutex<Option<(ArtKey, Option<String>)>>);

/// WinRT on any thread without setting up COM on each one: keep the
/// process-wide multithreaded apartment alive for the app's lifetime.
fn ensure_apartment() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let _ = unsafe { CoIncrementMTAUsage() };
    });
}

fn manager() -> windows::core::Result<SessionManager> {
    ensure_apartment();
    SessionManager::RequestAsync()?.join()
}

/// Scales the artwork down and re-encodes it as JPEG.
fn thumbnail(reference: &IRandomAccessStreamReference) -> windows::core::Result<String> {
    let stream = reference.OpenReadAsync()?.join()?;
    let decoder = BitmapDecoder::CreateAsync(&stream)?.join()?;
    let (width, height) = fit(decoder.PixelWidth()?, decoder.PixelHeight()?, THUMBNAIL_MAX);
    let transform = BitmapTransform::new()?;
    transform.SetScaledWidth(width)?;
    transform.SetScaledHeight(height)?;
    transform.SetInterpolationMode(BitmapInterpolationMode::Fant)?;
    let pixels = decoder
        .GetPixelDataTransformedAsync(
            BitmapPixelFormat::Bgra8,
            BitmapAlphaMode::Ignore,
            &transform,
            ExifOrientationMode::IgnoreExifOrientation,
            ColorManagementMode::ColorManageToSRgb,
        )?
        .join()?
        .DetachPixelData()?;

    let output = InMemoryRandomAccessStream::new()?;
    let encoder = BitmapEncoder::CreateAsync(BitmapEncoder::JpegEncoderId()?, &output)?.join()?;
    encoder.SetPixelData(
        BitmapPixelFormat::Bgra8,
        BitmapAlphaMode::Ignore,
        width,
        height,
        96.0,
        96.0,
        &pixels,
    )?;
    encoder.FlushAsync()?.join()?;

    let size = u32::try_from(output.Size()?).unwrap_or(u32::MAX);
    let buffer = Buffer::Create(size)?;
    let read = output
        .GetInputStreamAt(0)?
        .ReadAsync(&buffer, size, InputStreamOptions::None)?
        .join()?;
    let mut bytes = vec![0u8; read.Length()? as usize];
    DataReader::FromBuffer(&read)?.ReadBytes(&mut bytes)?;
    Ok(jpeg_data_url(&bytes))
}

fn snapshot(session: &Session, art: &ArtCache) -> windows::core::Result<MediaSnapshot> {
    let app_id = session.SourceAppUserModelId()?.to_string();
    let properties = session.TryGetMediaPropertiesAsync()?.join()?;
    let title = properties.Title()?.to_string();
    let artist = properties.Artist()?.to_string();
    let album = properties.AlbumTitle()?.to_string();

    let key: ArtKey = (app_id.clone(), title.clone(), artist.clone(), album.clone());
    let cached = art
        .0
        .lock()
        .expect("media art lock")
        .as_ref()
        .filter(|(k, _)| *k == key)
        .map(|(_, url)| url.clone());
    let thumbnail = match cached {
        Some(url) => url,
        None => {
            /* No artwork, or artwork that does not decode, is simply no artwork. */
            let url = properties
                .Thumbnail()
                .ok()
                .and_then(|t| self::thumbnail(&t).ok());
            *art.0.lock().expect("media art lock") = Some((key, url.clone()));
            url
        }
    };

    let playback = session.GetPlaybackInfo()?;
    let controls = playback.Controls()?;
    let timeline_properties = session.GetTimelineProperties()?;
    let (position_seconds, duration_seconds) = timeline(
        timeline_properties.StartTime()?.Duration,
        timeline_properties.EndTime()?.Duration,
        timeline_properties.Position()?.Duration,
    );

    Ok(MediaSnapshot {
        app_id,
        title,
        artist,
        album,
        thumbnail,
        status: Status::from_raw(playback.PlaybackStatus()?.0),
        position_seconds,
        duration_seconds,
        updated_at: unix_millis(timeline_properties.LastUpdatedTime()?.UniversalTime),
        shuffle: playback
            .IsShuffleActive()
            .and_then(|value| value.Value())
            .ok(),
        repeat: playback
            .AutoRepeatMode()
            .and_then(|value| value.Value())
            .ok()
            .and_then(Repeat::from_raw),
        controls: Controls {
            play: controls.IsPlayEnabled()?,
            pause: controls.IsPauseEnabled()?,
            toggle: controls.IsPlayPauseToggleEnabled()?,
            next: controls.IsNextEnabled()?,
            previous: controls.IsPreviousEnabled()?,
            shuffle: controls.IsShuffleEnabled()?,
            repeat: controls.IsRepeatEnabled()?,
        },
    })
}

fn current_snapshot(manager: &SessionManager, art: &ArtCache) -> Option<MediaSnapshot> {
    let session = manager.GetCurrentSession().ok()?;
    snapshot(&session, art).ok()
}

#[derive(Clone, Copy)]
enum Message {
    /// Something about the current session changed.
    Changed,
    /// The current session may be a different one now.
    Session,
    Stop,
}

/// An event handler that only posts `message` to the subscription thread;
/// the thread does the work, never the WinRT callback.
fn signal<S, A>(sender: &Sender<Message>, message: Message) -> TypedEventHandler<S, A>
where
    S: windows::core::RuntimeType + 'static,
    A: windows::core::RuntimeType + 'static,
{
    let sender = sender.clone();
    TypedEventHandler::new(move |_, _| {
        let _ = sender.send(message);
        Ok(())
    })
}

/// The current session and the change handlers attached to it.
struct Attached {
    session: Session,
    tokens: [i64; 3],
}

impl Attached {
    fn new(session: Session, sender: &Sender<Message>) -> windows::core::Result<Self> {
        let tokens = [
            session.MediaPropertiesChanged(&signal(sender, Message::Changed))?,
            session.PlaybackInfoChanged(&signal(sender, Message::Changed))?,
            session.TimelinePropertiesChanged(&signal(sender, Message::Changed))?,
        ];
        Ok(Self { session, tokens })
    }
}

impl Drop for Attached {
    fn drop(&mut self) {
        let [properties, playback, timeline] = self.tokens;
        let _ = self.session.RemoveMediaPropertiesChanged(properties);
        let _ = self.session.RemovePlaybackInfoChanged(playback);
        let _ = self.session.RemoveTimelinePropertiesChanged(timeline);
    }
}

fn watch(
    app: &AppHandle,
    art: &ArtCache,
    sender: &Sender<Message>,
    inbox: &mpsc::Receiver<Message>,
) {
    let Ok(manager) = manager() else {
        let _ = app.emit(EVENT, None::<MediaSnapshot>);
        return;
    };
    let current_token = manager.CurrentSessionChanged(&signal(sender, Message::Session));
    let sessions_token = manager.SessionsChanged(&signal(sender, Message::Session));

    let mut attached: Option<Attached> = None;
    let mut reattach = true;
    let mut last: Option<Option<MediaSnapshot>> = None;
    'watching: loop {
        if reattach {
            /* Detach from the old session before attaching to the new one. */
            drop(attached.take());
            attached = manager
                .GetCurrentSession()
                .ok()
                .and_then(|session| Attached::new(session, sender).ok());
            reattach = false;
        }
        let now = attached
            .as_ref()
            .and_then(|a| snapshot(&a.session, art).ok());
        if last.as_ref() != Some(&now) {
            let _ = app.emit(EVENT, &now);
            last = Some(now);
        }

        let mut first = true;
        loop {
            let message = if first {
                inbox.recv().map_err(|_| RecvTimeoutError::Disconnected)
            } else {
                inbox.recv_timeout(COALESCE)
            };
            first = false;
            match message {
                Ok(Message::Changed) => {}
                Ok(Message::Session) => reattach = true,
                Err(RecvTimeoutError::Timeout) => break,
                Ok(Message::Stop) | Err(RecvTimeoutError::Disconnected) => break 'watching,
            }
        }
    }

    drop(attached);
    if let Ok(token) = current_token {
        let _ = manager.RemoveCurrentSessionChanged(token);
    }
    if let Ok(token) = sessions_token {
        let _ = manager.RemoveSessionsChanged(token);
    }
}

#[derive(Default)]
pub struct Media {
    art: Arc<ArtCache>,
    subscription: Mutex<Option<Sender<Message>>>,
}

fn failure(error: windows::core::Error) -> HostError {
    HostError::new("media", error.message())
}

/// The current session now, or `None` when nothing publishes one.
#[tauri::command(async)]
pub fn media_snapshot(app: AppHandle) -> HostResult<Option<MediaSnapshot>> {
    let manager = manager().map_err(failure)?;
    Ok(current_snapshot(&manager, &app.state::<Media>().art))
}

/// Sends a control to the current session; false when there is no session
/// or the app turned the request down.
#[tauri::command(async)]
pub fn media_control(action: Action) -> HostResult<bool> {
    let manager = manager().map_err(failure)?;
    let Ok(session) = manager.GetCurrentSession() else {
        return Ok(false);
    };
    let request = match action {
        Action::Play => session.TryPlayAsync(),
        Action::Pause => session.TryPauseAsync(),
        Action::Toggle => session.TryTogglePlayPauseAsync(),
        Action::Next => session.TrySkipNextAsync(),
        Action::Previous => session.TrySkipPreviousAsync(),
        Action::Shuffle { on } => session.TryChangeShuffleActiveAsync(on),
        Action::Repeat { mode } => session.TryChangeAutoRepeatModeAsync(mode.raw()),
    };
    request
        .and_then(|operation| operation.join())
        .map_err(failure)
}

/// Starts or stops the change subscription. While on, `media:changed`
/// carries a snapshot (or `null`) at once and after every change.
#[tauri::command]
pub fn media_watch(app: AppHandle, on: bool) {
    let media = app.state::<Media>();
    let mut subscription = media.subscription.lock().expect("media lock");
    match (on, subscription.take()) {
        (true, Some(running)) => *subscription = Some(running),
        (true, None) => {
            let (sender, inbox) = mpsc::channel();
            let thread_sender = sender.clone();
            let thread_app = app.clone();
            let art = media.art.clone();
            thread::Builder::new()
                .name("tabbi-media".into())
                .spawn(move || watch(&thread_app, &art, &thread_sender, &inbox))
                .expect("the media thread starts");
            *subscription = Some(sender);
        }
        (false, Some(running)) => {
            let _ = running.send(Message::Stop);
        }
        (false, None) => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn winrt_times_become_unix_milliseconds() {
        assert_eq!(unix_millis(116_444_736_000_000_000), 0.0);
        /* 2026-10-15T00:00:00Z */
        assert_eq!(
            unix_millis(116_444_736_000_000_000 + 1_792_022_400_000 * 10_000),
            1_792_022_400_000.0
        );
    }

    #[test]
    fn the_timeline_counts_from_the_start_and_stays_inside_the_track() {
        assert_eq!(timeline(0, 2_000_000_000, 450_000_000), (45.0, 200.0));
        assert_eq!(
            timeline(10_000_000, 210_000_000, 60_000_000),
            (5.0, 20.0),
            "offset start"
        );
        assert_eq!(
            timeline(0, 100_000_000, 150_000_000),
            (10.0, 10.0),
            "past the end"
        );
        assert_eq!(
            timeline(0, 0, 30_000_000),
            (3.0, 0.0),
            "no duration, a live stream"
        );
        assert_eq!(timeline(0, 100, -5), (0.0, 0.00001));
    }

    #[test]
    fn artwork_scales_down_to_fit_and_never_up() {
        assert_eq!(fit(640, 640, 256), (256, 256));
        assert_eq!(fit(1280, 720, 256), (256, 144));
        assert_eq!(fit(300, 1000, 256), (77, 256));
        assert_eq!(fit(120, 90, 256), (120, 90));
        assert_eq!(fit(10_000, 1, 256), (256, 1), "never zero pixels");
        assert_eq!(fit(0, 0, 256), (1, 1));
    }

    #[test]
    fn base64_matches_rfc_4648() {
        for (input, expected) in [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
            ("fooba", "Zm9vYmE="),
            ("foobar", "Zm9vYmFy"),
        ] {
            assert_eq!(base64(input.as_bytes()), expected);
        }
        assert_eq!(base64(&[0xff, 0xfe, 0x3e]), "//4+");
        assert_eq!(jpeg_data_url(&[0xff, 0xd8]), "data:image/jpeg;base64,/9g=");
    }

    #[test]
    fn playback_states_and_repeat_modes_map_from_winrt() {
        assert_eq!(Status::from_raw(4), Status::Playing);
        assert_eq!(Status::from_raw(5), Status::Paused);
        assert_eq!(Status::from_raw(3), Status::Stopped);
        assert_eq!(Status::from_raw(99), Status::Closed);
        for mode in [Repeat::None, Repeat::Track, Repeat::List] {
            assert_eq!(Repeat::from_raw(mode.raw()), Some(mode));
        }
        assert_eq!(Repeat::from_raw(MediaPlaybackAutoRepeatMode(7)), None);
    }

    #[test]
    fn actions_and_snapshots_use_the_ui_shapes() {
        let parse = |json: &str| serde_json::from_str::<Action>(json).unwrap();
        assert_eq!(parse(r#"{"type":"toggle"}"#), Action::Toggle);
        assert_eq!(parse(r#"{"type":"previous"}"#), Action::Previous);
        assert_eq!(
            parse(r#"{"type":"shuffle","on":true}"#),
            Action::Shuffle { on: true }
        );
        assert_eq!(
            parse(r#"{"type":"repeat","mode":"list"}"#),
            Action::Repeat { mode: Repeat::List }
        );
        assert!(serde_json::from_str::<Action>(r#"{"type":"stop"}"#).is_err());

        let snapshot = MediaSnapshot {
            app_id: "Spotify.exe".into(),
            title: "Song".into(),
            artist: "Band".into(),
            album: "Record".into(),
            thumbnail: None,
            status: Status::Playing,
            position_seconds: 1.5,
            duration_seconds: 200.0,
            updated_at: 1000.0,
            shuffle: Some(false),
            repeat: Some(Repeat::Track),
            controls: Controls {
                toggle: true,
                ..Controls::default()
            },
        };
        assert_eq!(
            serde_json::to_value(snapshot).unwrap(),
            serde_json::json!({
                "appId": "Spotify.exe", "title": "Song", "artist": "Band", "album": "Record",
                "thumbnail": null, "status": "playing", "positionSeconds": 1.5,
                "durationSeconds": 200.0, "updatedAt": 1000.0, "shuffle": false,
                "repeat": "track",
                "controls": { "play": false, "pause": false, "toggle": true, "next": false,
                    "previous": false, "shuffle": false, "repeat": false }
            })
        );
    }

    /// Reads whatever is playing now. Run on a Windows desktop with
    /// `cargo test -- --ignored --nocapture` while music plays.
    #[test]
    #[ignore = "reads the real media session"]
    fn live_snapshot() {
        let manager = manager().expect("the session manager");
        let snapshot = current_snapshot(&manager, &ArtCache::default());
        println!(
            "{:?}",
            snapshot.map(|s| (s.app_id, s.title, s.status, s.thumbnail.map(|t| t.len())))
        );
    }
}
