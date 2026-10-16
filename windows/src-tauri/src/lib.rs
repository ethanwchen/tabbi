//! The Tabbi for Windows host: the island window, the tray icon, the global
//! hotkey and the `tabbi://` links. The UI (React, in `windows/src`) owns the
//! island's state machine; the host places the window, shapes it, watches the
//! pointer and displays, and reports what it sees as events.

mod ai_paths;
mod autostart;
mod credentials;
mod error;
mod http;
mod media;
mod notify;
mod placement;
mod storage;
mod system;
mod watcher;
mod win;

use placement::{Monitor, Rect};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, RunEvent, WebviewUrl,
    WebviewWindow, WebviewWindowBuilder,
};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
use watcher::{Signal, Watcher};

const ISLAND: &str = "island";
/// The Settings window's label; the window exists only while it is open.
const SETTINGS: &str = "settings";

/// The Settings window's size in logical pixels: room for the five sections'
/// sidebar and a form, and no smaller than its narrowest layout.
const SETTINGS_SIZE: (f64, f64) = (760.0, 540.0);
const SETTINGS_MIN_SIZE: (f64, f64) = (640.0, 440.0);

/// The open canvases the panel sizes ask for (compact 512 x 224 up to large
/// 640 x 272), with room to spare; anything outside is a UI bug, refused.
const CANVAS_LIMITS: (f64, f64, f64, f64) = (320.0, 160.0, 1200.0, 800.0);

/// The Mac's default, Control+Option+Space.
const DEFAULT_HOTKEY: &str = "ctrl+alt+space";

/// A rectangle in logical pixels relative to the island window, as the UI
/// measures its shape.
#[derive(Debug, Clone, Copy, Deserialize)]
struct ShapeRect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

/// What opened or toggled the island, so the UI can apply the Mac's rules
/// (only a hover-opened panel closes when the pointer leaves).
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
enum Source {
    Hotkey,
    Tray,
    Launch,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct HotkeyStatus {
    shortcut: String,
    registered: bool,
}

/// Where the island is and what the UI last asked of it.
#[derive(Default)]
struct IslandState {
    display: Option<Monitor>,
    shape: Option<ShapeRect>,
    open: bool,
    previous_foreground: isize,
    hotkey: Option<HotkeyStatus>,
    /// The open canvas in logical pixels, from the user's panel size; the
    /// window is always this size and only its region changes.
    canvas: Option<(f64, f64)>,
}

impl IslandState {
    fn canvas(&self) -> (f64, f64) {
        self.canvas
            .unwrap_or((placement::CANVAS_WIDTH, placement::CANVAS_HEIGHT))
    }
}

/// What the host reads from its environment once at launch and hands every
/// window through `Startup`, so no module reads the environment itself.
#[derive(Debug, Clone, Default)]
struct Launch {
    notch_mode: Option<String>,
    demo: bool,
    party_server: Option<String>,
}

impl Launch {
    fn from_environment() -> Self {
        let debug = cfg!(debug_assertions);
        Self {
            notch_mode: debug
                .then(|| std::env::var("TABBI_NOTCH_MODE").ok())
                .flatten(),
            demo: demo_requested(std::env::var("TABBI_DEMO").ok().as_deref()),
            party_server: dev_party_server(
                debug,
                std::env::var("TABBI_PARTY_SERVER").ok().as_deref(),
            ),
        }
    }
}

/// `TABBI_DEMO=1` turns on demo data, as on the Mac; any other value does not.
fn demo_requested(value: Option<&str>) -> bool {
    value == Some("1")
}

/// `TABBI_PARTY_SERVER` for the UI: debug builds only, and only a plain-http
/// loopback address, so a development run can never reach a deployed server
/// by mistake. Written without a trailing slash.
fn dev_party_server(debug: bool, value: Option<&str>) -> Option<String> {
    if !debug {
        return None;
    }
    let url = http::dev_worker_origin(value?)?;
    Some(url.as_str().trim_end_matches('/').to_owned())
}

/// Whether a canvas the UI asks for is one a panel size can produce.
fn valid_canvas(width: f64, height: f64) -> bool {
    let (min_width, min_height, max_width, max_height) = CANVAS_LIMITS;
    width.is_finite()
        && height.is_finite()
        && (min_width..=max_width).contains(&width)
        && (min_height..=max_height).contains(&height)
}

/// The island window on `display` for a canvas of `canvas` logical pixels:
/// centered on the work area like `placement::island_rect` and hanging from
/// its top edge.
fn canvas_rect(display: &Monitor, canvas: (f64, f64)) -> Rect {
    let width = (canvas.0 * display.scale).round() as i32;
    let height = (canvas.1 * display.scale).round() as i32;
    let left = display.work.left + (display.work.width() - width) / 2;
    let top = display.work.top;
    Rect::new(left, top, left + width, top + height)
}

struct Island {
    state: Mutex<IslandState>,
    watcher: Watcher,
    window: isize,
}

fn island_window(app: &AppHandle) -> WebviewWindow {
    app.get_webview_window(ISLAND)
        .expect("the island window exists")
}

/// Moves the island window onto a display: canvas-sized and hanging from the
/// top of its work area. Position, size, then position again, because moving
/// onto a display with another scale lets Windows resize the window on the way.
fn place(app: &AppHandle, display: Monitor) {
    let window = island_window(app);
    let canvas = app
        .state::<Island>()
        .state
        .lock()
        .expect("island lock")
        .canvas();
    let rect = canvas_rect(&display, canvas);
    let position = PhysicalPosition::new(rect.left, rect.top);
    let _ = window.set_position(position);
    let _ = window.set_size(PhysicalSize::new(rect.width() as u32, rect.height() as u32));
    let _ = window.set_position(position);

    let island = app.state::<Island>();
    let mut state = island.state.lock().expect("island lock");
    state.display = Some(display);
    apply_shape(&island, &state);
    island.watcher.update(|watch| watch.display = Some(display));
    drop(state);
    let _ = app.emit("island:placed", display.scale);
}

/// Applies the UI's shape as the window region, and tells the watcher where
/// the open panel is so it can see clicks outside it.
fn apply_shape(island: &Island, state: &IslandState) {
    let Some(display) = state.display else { return };
    let region = state
        .shape
        .map(|s| placement::region_rect(s.x, s.y, s.width, s.height, display.scale))
        .filter(|r| r.width() > 0 && r.height() > 0);
    win::set_region(island.window, region);
    let origin = canvas_rect(&display, state.canvas());
    let open_shape: Option<Rect> = if state.open {
        region.map(|r| r.offset(origin.left, origin.top))
    } else {
        None
    };
    island.watcher.update(|watch| watch.open_shape = open_shape);
}

/// Before the island opens from the hotkey or the tray, it moves to the
/// display under the pointer, the way the Mac opens on the active screen.
fn follow_pointer(app: &AppHandle) {
    let island = app.state::<Island>();
    if island.state.lock().expect("island lock").open {
        return;
    }
    let monitors = win::monitors();
    let target = win::cursor().and_then(|(x, y)| placement::monitor_at(&monitors, x, y).copied());
    let current = island.state.lock().expect("island lock").display;
    if let Some(target) = target
        && Some(target) != current
    {
        place(app, target);
    }
}

fn toggle(app: &AppHandle, source: Source) {
    follow_pointer(app);
    let _ = app.emit("island:toggle", source);
}

fn open(app: &AppHandle, source: Source) {
    follow_pointer(app);
    let _ = app.emit("island:open", source);
}

fn on_signal(app: &AppHandle, signal: Signal) {
    match signal {
        Signal::HotZone(display) => {
            let current = app
                .state::<Island>()
                .state
                .lock()
                .expect("island lock")
                .display;
            if current != Some(display) {
                place(app, display);
            }
            let _ = app.emit("island:hot-zone", ());
        }
        Signal::OutsideClick => {
            let _ = app.emit("island:outside-click", ());
        }
        Signal::Fullscreen(active) => {
            let _ = app.emit("island:fullscreen", active);
        }
        Signal::DisplaysChanged(monitors) => {
            let current = app
                .state::<Island>()
                .state
                .lock()
                .expect("island lock")
                .display;
            if let Some(display) = placement::same_or_primary(&monitors, current.as_ref()).copied()
            {
                place(app, display);
            }
        }
    }
}

/// The UI's shape: the rectangle the visible island fills, or `None` when
/// nothing is drawn. Clicks outside it reach the app below.
#[tauri::command]
fn island_set_shape(app: AppHandle, shape: Option<ShapeRect>) {
    let island = app.state::<Island>();
    let mut state = island.state.lock().expect("island lock");
    state.shape = shape;
    apply_shape(&island, &state);
    if shape.is_some() {
        win::raise(island.window);
    }
}

/// Open lets the panel take keyboard focus and watches for clicks outside it;
/// closed gives focus back and never takes it.
#[tauri::command]
fn island_set_open(app: AppHandle, open: bool) {
    let island = app.state::<Island>();
    let mut state = island.state.lock().expect("island lock");
    state.open = open;
    win::set_activatable(island.window, open);
    apply_shape(&island, &state);
}

/// Takes keyboard focus, remembering who had it to give it back on close.
#[tauri::command]
fn island_activate(app: AppHandle) {
    let island = app.state::<Island>();
    let front = win::foreground();
    if front != island.window {
        island
            .state
            .lock()
            .expect("island lock")
            .previous_foreground = front;
    }
    let _ = island_window(&app).set_focus();
}

#[tauri::command]
fn island_restore_focus(app: AppHandle) {
    let island = app.state::<Island>();
    let previous = std::mem::take(
        &mut island
            .state
            .lock()
            .expect("island lock")
            .previous_foreground,
    );
    win::restore_foreground(island.window, previous);
}

#[tauri::command]
fn island_arm_hot_zone(app: AppHandle, armed: bool) {
    app.state::<Island>()
        .watcher
        .update(|watch| watch.hot_zone = armed);
}

/// What the UI needs from the host when it starts.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Startup {
    hotkey: Option<HotkeyStatus>,
    /// A development override of the closed-island mode
    /// (`TABBI_NOTCH_MODE=alwaysVisible`). Release builds ignore it.
    notch_mode: Option<String>,
    /// `TABBI_DEMO=1`: sample data, and no network, media or calendars.
    demo: bool,
    /// A development Party Worker on loopback (debug builds only).
    party_server: Option<String>,
}

fn startup(app: &AppHandle) -> Startup {
    let hotkey = app
        .state::<Island>()
        .state
        .lock()
        .expect("island lock")
        .hotkey
        .clone();
    let launch = app.state::<Launch>();
    Startup {
        hotkey,
        notch_mode: launch.notch_mode.clone(),
        demo: launch.demo,
        party_server: launch.party_server.clone(),
    }
}

/// The UI calls this once it has drawn its first frame, so the window never
/// flashes an unstyled page.
#[tauri::command]
fn island_ready(app: AppHandle) -> Startup {
    let _ = island_window(&app).show();
    startup(&app)
}

/// Resizes the island to the open canvas of the user's panel size and puts
/// it back in place on its display.
#[tauri::command]
fn island_set_canvas(app: AppHandle, width: f64, height: f64) {
    if !valid_canvas(width, height) {
        eprintln!("tabbi: refused a {width} x {height} canvas");
        return;
    }
    let island = app.state::<Island>();
    let mut state = island.state.lock().expect("island lock");
    if state.canvas == Some((width, height)) {
        return;
    }
    state.canvas = Some((width, height));
    let display = state.display;
    drop(state);
    if let Some(display) = display {
        place(&app, display);
    }
}

/// The section the Settings window opens at, until it reports ready.
#[derive(Default)]
struct PendingSection(Mutex<Option<String>>);

/// What the Settings window starts with.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct SettingsLaunch {
    startup: Startup,
    section: Option<String>,
}

/// Opens the Settings window at `section`, or brings it forward and shows
/// that section. The window is created on demand and destroyed when closed,
/// so it costs no memory while nobody has it open.
fn open_settings(app: &AppHandle, section: Option<String>) {
    if let Some(window) = app.get_webview_window(SETTINGS) {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
        if let Some(section) = section {
            let _ = app.emit_to(SETTINGS, "settings:section", section);
        }
        return;
    }
    *app.state::<PendingSection>()
        .0
        .lock()
        .expect("settings lock") = section;
    let built = WebviewWindowBuilder::new(app, SETTINGS, WebviewUrl::App("index.html".into()))
        .title("Tabbi Settings")
        .inner_size(SETTINGS_SIZE.0, SETTINGS_SIZE.1)
        .min_inner_size(SETTINGS_MIN_SIZE.0, SETTINGS_MIN_SIZE.1)
        .theme(Some(tauri::Theme::Dark))
        .background_color(tauri::window::Color(18, 18, 20, 255))
        .center()
        .visible(false)
        .build();
    if let Err(error) = built {
        eprintln!("tabbi: the Settings window did not open: {error}");
    }
}

/// Async on purpose: a synchronous command runs on the main thread, and
/// creating a webview window there deadlocks on Windows (wry#583), leaving
/// the new window blank.
#[tauri::command]
async fn settings_open(app: AppHandle, section: Option<String>) {
    open_settings(&app, section);
}

/// The Settings window calls this as its page starts, and it is shown then:
/// its dark background color keeps it from flashing white before the first
/// frame, and the page needs the startup values to build its stores.
#[tauri::command]
fn settings_ready(app: AppHandle) -> SettingsLaunch {
    if let Some(window) = app.get_webview_window(SETTINGS) {
        let _ = window.show();
        let _ = window.set_focus();
    }
    let section = app
        .state::<PendingSection>()
        .0
        .lock()
        .expect("settings lock")
        .take();
    SettingsLaunch {
        startup: startup(&app),
        section,
    }
}

fn register_hotkey(app: &AppHandle) -> HotkeyStatus {
    let registered = app
        .global_shortcut()
        .on_shortcut(DEFAULT_HOTKEY, |app, _shortcut, event| {
            if event.state() == ShortcutState::Pressed {
                toggle(app, Source::Hotkey);
            }
        })
        .map_err(|error| eprintln!("tabbi: the hotkey {DEFAULT_HOTKEY} is taken: {error}"))
        .is_ok();
    HotkeyStatus {
        shortcut: DEFAULT_HOTKEY.into(),
        registered,
    }
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let open_item = MenuItem::with_id(app, "open", "Open Tabbi", true, None::<&str>)?;
    let settings_item = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit Tabbi", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&open_item, &settings_item, &separator, &quit_item])?;
    TrayIconBuilder::with_id("tabbi")
        .icon(
            app.default_window_icon()
                .cloned()
                .expect("the bundle has an icon"),
        )
        .tooltip("Tabbi")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => open(app, Source::Tray),
            "settings" => open_settings(app, None),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle(tray.app_handle(), Source::Tray);
            }
        })
        .build(app)?;
    Ok(())
}

fn setup(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let window = island_window(app);
    let raw = window.hwnd()?.0 as isize;
    win::make_tool_window(raw);
    win::set_activatable(raw, false);
    win::set_region(raw, None);
    app.manage(Launch::from_environment());
    app.manage(PendingSection::default());

    let signal_app = app.clone();
    let watcher = Watcher::spawn(move |signal| {
        let app = signal_app.clone();
        let _ = signal_app.run_on_main_thread(move || on_signal(&app, signal));
    });
    watcher.update(|watch| watch.own_window = raw);
    app.manage(Island {
        state: Mutex::new(IslandState::default()),
        watcher,
        window: raw,
    });

    let monitors = win::monitors();
    if let Some(display) = placement::primary(&monitors).copied() {
        place(app, display);
    }

    let hotkey = register_hotkey(app);
    app.state::<Island>()
        .state
        .lock()
        .expect("island lock")
        .hotkey = Some(hotkey);

    build_tray(app)?;

    app.manage(storage::Storage::for_app(app)?);
    app.manage(http::Http::new());
    app.manage(media::Media::default());
    app.manage(system::SystemSampler::default());

    /* The installer registers tabbi:// per user; a dev build registers itself. */
    #[cfg(debug_assertions)]
    app.deep_link().register_all()?;
    let link_app = app.clone();
    app.deep_link().on_open_url(move |event| {
        for url in event.urls() {
            let _ = link_app.emit("island:link", url.to_string());
        }
    });
    Ok(())
}

pub fn run() {
    let app = tauri::Builder::default()
        /* First, so a second launch hands over its tabbi:// link and exits before anything else starts. */
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| open(app, Source::Launch)))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        /* Off until the user turns on Start with Windows; the plugin only registers its manager. */
        .plugin(tauri_plugin_autostart::Builder::new().app_name("Tabbi").build())
        .invoke_handler(tauri::generate_handler![
            island_set_shape,
            island_set_open,
            island_activate,
            island_restore_focus,
            island_arm_hot_zone,
            island_ready,
            island_set_canvas,
            settings_open,
            settings_ready,
            storage::storage_read,
            storage::storage_write,
            storage::storage_list,
            storage::storage_delete,
            credentials::credential_get,
            credentials::credential_set,
            credentials::credential_delete,
            notify::notify,
            media::media_snapshot,
            media::media_control,
            media::media_watch,
            system::system_watch,
            http::http_request,
            http::http_set_party_server,
            http::http_stream,
            http::http_cancel,
            http::http_fetch_calendar,
            autostart::autostart_enable,
            autostart::autostart_disable,
            autostart::autostart_is_enabled,
            ai_paths::ai_paths
        ])
        .setup(|app| setup(app.handle()))
        .build(tauri::generate_context!())
        .expect("Tabbi starts");

    app.run(|app, event| {
        if let RunEvent::Exit = event
            && let Some(island) = app.try_state::<Island>()
        {
            island.watcher.stop();
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn demo_needs_exactly_one() {
        assert!(demo_requested(Some("1")));
        assert!(!demo_requested(Some("true")));
        assert!(!demo_requested(Some("")));
        assert!(!demo_requested(None));
    }

    #[test]
    fn the_party_server_is_a_debug_loopback_address_only() {
        assert_eq!(
            dev_party_server(true, Some("http://localhost:8787")).as_deref(),
            Some("http://localhost:8787")
        );
        assert_eq!(
            dev_party_server(true, Some(" http://127.0.0.1:8787/ ")).as_deref(),
            Some("http://127.0.0.1:8787")
        );
        assert_eq!(dev_party_server(false, Some("http://localhost:8787")), None);
        assert_eq!(dev_party_server(true, Some("https://localhost:8787")), None);
        assert_eq!(
            dev_party_server(true, Some("http://example.com:8787")),
            None
        );
        assert_eq!(
            dev_party_server(true, Some("http://user@localhost:8787")),
            None
        );
        assert_eq!(dev_party_server(true, None), None);
    }

    #[test]
    fn canvases_come_from_the_panel_sizes() {
        for (width, height) in [(512.0, 224.0), (560.0, 236.0), (640.0, 272.0)] {
            assert!(valid_canvas(width, height));
        }
        assert!(!valid_canvas(0.0, 236.0));
        assert!(!valid_canvas(560.0, f64::NAN));
        assert!(!valid_canvas(5000.0, 236.0));
    }

    #[test]
    fn the_canvas_hangs_centered_from_the_work_area() {
        let display = Monitor {
            bounds: Rect::new(0, 0, 1920, 1080),
            work: Rect::new(0, 0, 1920, 1032),
            scale: 1.5,
        };
        let regular = canvas_rect(
            &display,
            (placement::CANVAS_WIDTH, placement::CANVAS_HEIGHT),
        );
        assert_eq!(regular, placement::island_rect(&display));
        let large = canvas_rect(&display, (640.0, 272.0));
        assert_eq!((large.width(), large.height(), large.top), (960, 408, 0));
        assert_eq!(large.left + large.width() / 2, 960);
    }
}
