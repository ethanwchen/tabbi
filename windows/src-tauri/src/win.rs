//! The few Win32 calls the island needs, kept in one place behind plain types.
//!
//! Window handles cross threads as `isize` because `HWND` is a raw pointer and
//! not `Send`; every function here turns it back into an `HWND` at the call.

use crate::placement::{Monitor, Rect};
use windows::Win32::Foundation::{HWND, LPARAM, POINT, RECT};
use windows::Win32::Graphics::Gdi::{
    CreateRectRgn, EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, HRGN, MONITORINFO,
    SetWindowRgn,
};
use windows::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, VK_LBUTTON, VK_MBUTTON, VK_RBUTTON,
};
use windows::Win32::UI::Shell::{
    QUNS_PRESENTATION_MODE, QUNS_RUNNING_D3D_FULL_SCREEN, SHQueryUserNotificationState,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GWL_EXSTYLE, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongPtrW,
    GetWindowRect, HWND_TOPMOST, IsIconic, IsWindow, IsWindowVisible, IsZoomed, SWP_FRAMECHANGED,
    SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER, SetForegroundWindow, SetWindowLongPtrW,
    SetWindowPos, WS_EX_APPWINDOW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};
use windows::core::BOOL;

fn hwnd(raw: isize) -> HWND {
    HWND(raw as *mut core::ffi::c_void)
}

fn rect(r: RECT) -> Rect {
    Rect::new(r.left, r.top, r.right, r.bottom)
}

/// Every display with its bounds, work area and effective scale.
pub fn monitors() -> Vec<Monitor> {
    unsafe extern "system" fn collect(
        monitor: HMONITOR,
        _: HDC,
        _: *mut RECT,
        data: LPARAM,
    ) -> BOOL {
        let list = unsafe { &mut *(data.0 as *mut Vec<Monitor>) };
        let mut info = MONITORINFO {
            cbSize: size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        if unsafe { GetMonitorInfoW(monitor, &mut info) }.as_bool() {
            let (mut dpi_x, mut dpi_y) = (96u32, 96u32);
            let scale = match unsafe {
                GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut dpi_x, &mut dpi_y)
            } {
                Ok(()) => f64::from(dpi_x) / 96.0,
                Err(_) => 1.0,
            };
            list.push(Monitor {
                bounds: rect(info.rcMonitor),
                work: rect(info.rcWork),
                scale,
            });
        }
        true.into()
    }

    let mut list: Vec<Monitor> = Vec::new();
    unsafe {
        let _ = EnumDisplayMonitors(
            None,
            None,
            Some(collect),
            LPARAM(&mut list as *mut _ as isize),
        );
    }
    list
}

/// The pointer position in physical screen pixels, or `None` while the
/// desktop is locked or on the secure desktop.
pub fn cursor() -> Option<(i32, i32)> {
    let mut point = POINT::default();
    unsafe { GetCursorPos(&mut point) }
        .ok()
        .map(|()| (point.x, point.y))
}

/// Whether any mouse button is down now or was pressed since the last call,
/// so a click shorter than the polling interval still counts.
pub fn mouse_pressed() -> bool {
    [VK_LBUTTON, VK_RBUTTON, VK_MBUTTON]
        .iter()
        .any(|key| unsafe { GetAsyncKeyState(i32::from(key.0)) } as u16 & 0x8001 != 0)
}

/// Hides the window from Alt+Tab and the taskbar (a tool window) and keeps
/// clicks from activating it while the island is closed.
pub fn make_tool_window(window: isize) {
    update_ex_style(window, |style| {
        (style | WS_EX_TOOLWINDOW.0 | WS_EX_NOACTIVATE.0) & !WS_EX_APPWINDOW.0
    });
}

/// While the panel is open it may take keyboard focus (Escape, arrow keys and,
/// later, text fields); while closed it never does.
pub fn set_activatable(window: isize, activatable: bool) {
    update_ex_style(window, |style| {
        if activatable {
            style & !WS_EX_NOACTIVATE.0
        } else {
            style | WS_EX_NOACTIVATE.0
        }
    });
}

fn update_ex_style(window: isize, change: impl Fn(u32) -> u32) {
    let handle = hwnd(window);
    unsafe {
        let old = GetWindowLongPtrW(handle, GWL_EXSTYLE) as u32;
        let new = change(old);
        if new != old {
            SetWindowLongPtrW(handle, GWL_EXSTYLE, new as isize);
            let _ = SetWindowPos(
                handle,
                None,
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
            );
        }
    }
}

/// Puts the island on top of other always-on-top windows (a pinned Task
/// Manager, a picture-in-picture video) without activating it, the way the
/// notch is never covered on the Mac.
pub fn raise(window: isize) {
    unsafe {
        let _ = SetWindowPos(
            hwnd(window),
            Some(HWND_TOPMOST),
            0,
            0,
            0,
            0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
        );
    }
}

/// Limits the window, for both drawing and hit testing, to a rectangle in
/// physical pixels relative to the window. `None` leaves an empty region: the
/// window draws nothing and every click goes to the app below.
pub fn set_region(window: isize, region: Option<Rect>) {
    let r = region.unwrap_or(Rect::new(0, 0, 0, 0));
    unsafe {
        let rgn: HRGN = CreateRectRgn(r.left, r.top, r.right, r.bottom);
        /* The system owns the region after this call, so it is not deleted here. */
        SetWindowRgn(hwnd(window), Some(rgn), true);
    }
}

pub fn foreground() -> isize {
    unsafe { GetForegroundWindow() }.0 as isize
}

/// Gives focus back to the window that had it before the panel opened, if it
/// still exists and the panel still holds the focus.
pub fn restore_foreground(own: isize, previous: isize) {
    unsafe {
        if previous != 0 && foreground() == own && IsWindow(Some(hwnd(previous))).as_bool() {
            let _ = SetForegroundWindow(hwnd(previous));
        }
    }
}

/// Whether a fullscreen app, game, video or presentation owns this display.
///
/// The foreground window counts when it covers the whole display and is not
/// merely maximized (a maximized window over an auto-hidden taskbar covers the
/// display too). Direct3D exclusive fullscreen and presentation mode count
/// when the foreground window is on this display, as Windows itself reports
/// them for the whole session.
pub fn fullscreen_on(display: &Monitor, own: isize) -> bool {
    unsafe {
        let front = GetForegroundWindow();
        if front.is_invalid() || front.0 as isize == own || is_shell(front) {
            return false;
        }
        if !IsWindowVisible(front).as_bool() || IsIconic(front).as_bool() {
            return false;
        }
        let mut frame = RECT::default();
        if GetWindowRect(front, &mut frame).is_err() {
            return false;
        }
        let frame = rect(frame);
        if frame.covers(&display.bounds) && !IsZoomed(front).as_bool() {
            return true;
        }
        let center = (
            (frame.left + frame.right) / 2,
            (frame.top + frame.bottom) / 2,
        );
        if !display.bounds.contains(center.0, center.1) {
            return false;
        }
        matches!(
            SHQueryUserNotificationState(),
            Ok(state) if state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE
        )
    }
}

/// The desktop and the taskbar cover the display without being fullscreen apps.
fn is_shell(window: HWND) -> bool {
    let mut buffer = [0u16; 64];
    let length = unsafe { GetClassNameW(window, &mut buffer) };
    let class = String::from_utf16_lossy(&buffer[..length.max(0) as usize]);
    matches!(
        class.as_str(),
        "Progman" | "WorkerW" | "Shell_TrayWnd" | "Shell_SecondaryTrayWnd"
    )
}

/// Asks WebView2 to keep `window`'s processes small (`low`) or back at
/// normal. While low, WebView2 trims caches and working set, which the
/// closed island and an unfocused Settings window can spare; a page that
/// draws again wakes it at once. Older runtimes without ICoreWebView2_19
/// keep the normal level.
pub fn set_memory_low(window: &tauri::WebviewWindow, low: bool) {
    use webview2_com::Microsoft::Web::WebView2::Win32::{
        COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW, COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL,
        ICoreWebView2_19,
    };
    use windows::core::Interface;
    let result = window.with_webview(move |webview| {
        let level = if low {
            COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW
        } else {
            COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL
        };
        /* SAFETY: called on the webview's own thread, which with_webview guarantees. */
        unsafe {
            let Ok(core) = webview.controller().CoreWebView2() else {
                return;
            };
            if let Ok(core) = core.cast::<ICoreWebView2_19>() {
                let _ = core.SetMemoryUsageTargetLevel(level);
            }
        }
    });
    if let Err(error) = result {
        eprintln!("tabbi: could not set the WebView2 memory level: {error}");
    }
}

/// The least time between two reloads of one webview, so a page that crashes
/// its renderer as soon as it loads is not reloaded in a tight loop.
const RELOAD_SPACING: std::time::Duration = std::time::Duration::from_secs(10);

/// Keeps a failed WebView2 process from leaving `window` blank until the app
/// restarts. Without a handler, a renderer that crashes (out of memory, a
/// driver fault) or hangs leaves WebView2's error page (a white rectangle in
/// the island's shape), and a GPU process that dies with a sleep, a display
/// change or a driver reset can leave the transparent surface undrawn.
///
/// - A renderer that exited or stopped responding: the page reloads, and the
///   window's startup runs again.
/// - The GPU process exited: WebView2 starts a new one; hiding and showing
///   the webview makes it compose its surface again.
/// - The browser process exited: every webview of the app is gone and none
///   can be revived in place, so `on_browser_exit` runs (the island restarts
///   the app; other windows leave it to the island).
pub fn watch_process_failures(
    window: &tauri::WebviewWindow,
    on_browser_exit: impl Fn() + Send + 'static,
) {
    use std::time::Instant;
    use webview2_com::Microsoft::Web::WebView2::Win32::{
        COREWEBVIEW2_PROCESS_FAILED_KIND, COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED,
        COREWEBVIEW2_PROCESS_FAILED_KIND_GPU_PROCESS_EXITED,
        COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED,
        COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE,
    };
    use webview2_com::ProcessFailedEventHandler;
    let label = window.label().to_owned();
    let result = window.with_webview(move |webview| {
        let controller = webview.controller();
        let redrawn = controller.clone();
        let mut last_reload: Option<Instant> = None;
        let handler = ProcessFailedEventHandler::create(Box::new(move |sender, args| {
            let (Some(core), Some(args)) = (sender, args) else {
                return Ok(());
            };
            let mut kind = COREWEBVIEW2_PROCESS_FAILED_KIND::default();
            /* SAFETY: WebView2 raises this event on the webview's own thread. */
            unsafe {
                args.ProcessFailedKind(&mut kind)?;
                if kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED
                    || kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE
                {
                    if last_reload.is_some_and(|at| at.elapsed() < RELOAD_SPACING) {
                        eprintln!("tabbi: the {label} renderer failed again right after a reload");
                        return Ok(());
                    }
                    eprintln!("tabbi: the {label} renderer failed ({}), reloading", kind.0);
                    last_reload = Some(Instant::now());
                    core.Reload()?;
                } else if kind == COREWEBVIEW2_PROCESS_FAILED_KIND_GPU_PROCESS_EXITED {
                    eprintln!("tabbi: the WebView2 GPU process exited, redrawing {label}");
                    let mut visible = BOOL::default();
                    redrawn.IsVisible(&mut visible)?;
                    if visible.as_bool() {
                        redrawn.SetIsVisible(false)?;
                        redrawn.SetIsVisible(true)?;
                    }
                } else if kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED {
                    eprintln!("tabbi: the WebView2 browser process exited");
                    on_browser_exit();
                }
            }
            Ok(())
        }));
        let mut token = 0i64;
        /* SAFETY: called on the webview's own thread, which with_webview guarantees. */
        unsafe {
            if let Ok(core) = controller.CoreWebView2() {
                let _ = core.add_ProcessFailed(&handler, &mut token);
            }
        }
    });
    if let Err(error) = result {
        eprintln!("tabbi: could not watch the WebView2 processes: {error}");
    }
}
