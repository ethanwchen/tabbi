//! The Tabbi for Windows host: the island window, the tray icon, the global
//! hotkey and the `tabbi://` links. The UI (React, in `windows/src`) owns the
//! island's state machine; the host places the window, shapes it, watches the
//! pointer and displays, and reports what it sees as events.

mod placement;
mod watcher;
mod win;

use placement::{Monitor, Rect};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, RunEvent, WebviewWindow};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
use watcher::{Signal, Watcher};

const ISLAND: &str = "island";

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
    let rect = placement::island_rect(&display);
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
    let origin = placement::island_rect(&display);
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
    /// (`TABBI_NOTCH_MODE=alwaysVisible`), until Settings > Look offers it.
    /// Release builds ignore it.
    notch_mode: Option<String>,
}

/// The UI calls this once it has drawn its first frame, so the window never
/// flashes an unstyled page.
#[tauri::command]
fn island_ready(app: AppHandle) -> Startup {
    let _ = island_window(&app).show();
    let hotkey = app
        .state::<Island>()
        .state
        .lock()
        .expect("island lock")
        .hotkey
        .clone();
    let notch_mode = if cfg!(debug_assertions) {
        std::env::var("TABBI_NOTCH_MODE").ok()
    } else {
        None
    };
    Startup { hotkey, notch_mode }
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
    let quit_item = MenuItem::with_id(app, "quit", "Quit Tabbi", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&open_item, &separator, &quit_item])?;
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
        .invoke_handler(tauri::generate_handler![
            island_set_shape,
            island_set_open,
            island_activate,
            island_restore_focus,
            island_arm_hot_zone,
            island_ready
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
