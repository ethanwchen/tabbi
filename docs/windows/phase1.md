# Tabbi for Windows: phase 1 (shell spike)

Status: shell spike built, October 15, 2026.
The question phase 1 answers is go or no-go on Tauri 2 ([HANDOFF.md](HANDOFF.md), section 8).

## Recommendation

**Go on Tauri 2**, with the open items below checked on the owner's hardware before phase 2 merges.
Everything measured so far is inside budget: idle CPU 0.002 percent (budget 0.1), a 3.4 MB release executable, and idle memory 73.5 MB (budget 80 MB).
Memory is the tight one: 6.5 MB of headroom, almost all of it WebView2 (68.8 MB over six processes, against 4.7 MB for the Rust host), so phase 2 must re-measure after every module lands, and the first lever is releasing the webview's memory while the island is closed (`ICoreWebView2_3::TrySuspend` or `MemoryUsageTargetLevel` low).
The risk the spike existed to retire, a transparent WebView2 window that lets clicks through and opens without flicker, is retired on this machine.

## What was built

- A borderless, transparent, always-on-top tool window, always the size of the open canvas (560 x 236 logical pixels), hanging from the top of the work area of a display and centered on it.
  It never shows in Alt+Tab or on the taskbar, and never takes focus while closed (`WS_EX_TOOLWINDOW`, `WS_EX_NOACTIVATE`).
- Click-through by window region: the host sets the window region (`SetWindowRgn`) to the visible shape (the open panel, the pill, or nothing), so drawing and hit testing both stop at the shape and the webview never reflows.
  Resizing the window per frame was avoided on purpose: that is the known source of flicker with WebView2.
- The closed state in the Windows reading of the Mac's `NotchMode`: Auto (pill only while something is live, which nothing is yet in phase 1), Always (the pill), and Only on hover or hotkey.
  When no pill is drawn, a 250 x 4 px hot zone at the top-center edge opens the island after the pointer rests there for 300 ms.
- The Mac's input rules, as a pure state machine with 20 Vitest cases: a pill opens after a 250 ms hover, a hover-opened panel closes 600 ms after the pointer leaves and never takes focus, the hotkey and the tray toggle, Escape and a click outside close, focus goes back to the previous app on close, and a click on the tray icon that closes the panel does not reopen it.
- The NotchShape silhouette (concave top flares, rounded bottom corners, radii that clamp on small shapes) animated with the Mac's springs (`MotionTokens`: open 0.45 s with bounce 0.2, close 0.38 s with no bounce, hover 0.25 s), and content that fades in after the shape starts opening.
- A tray icon (left click toggles, right click: Open Tabbi, Quit Tabbi), the global hotkey Ctrl+Alt+Space with a plain note in the panel when another app owns it, single instance, and `tabbi://` registered per user in development builds.
- Fullscreen hiding: the island's display counts as taken when the foreground window covers it and is not merely maximized, or when Windows reports Direct3D fullscreen or presentation mode for a window on it.
- Per-monitor DPI v2, placement that follows the display under the pointer when opened by hover, hotkey or tray, and re-placement when displays, scaling or the taskbar change (checked once a second).
- A stub panel: the Essentials kit's tabs read from the Mac's kit file, the Closet's paw at the far right, the selected tab's title, the default theme's palette read from `themes.json`, and a status message per tab.

## Measurements

Machine: Windows 11 Pro (build 26200), one 2560 x 1440 display at 100 percent, WebView2 Runtime 155.

| Check | Result | Budget |
| --- | --- | --- |
| Private working set, all Tabbi processes, 10 minutes idle and closed | 73.5 MB (host 4.7, WebView2 68.8 over six processes) | 80 MB |
| CPU over 60 s after that | 0.002 percent of the machine | 0.1 percent |
| Release executable | 3.4 MB | a few MB |
| Hot zone: pointer rests at the top edge | opens, panel body drawn after 466 ms (300 ms dwell plus the spring) | about 300 ms dwell |
| Hot zone: a 150 ms flick | does not open | must not open |
| Pointer leaves a hover-opened panel | closed 702 ms later (600 ms delay plus the close spring) | 600 ms delay |
| Pointer leaves and returns within 600 ms | stays open | stays open |
| Hotkey | opens, Tabbi takes focus | |
| Escape | closes, focus returns to the previous app (Chrome) | |
| Hover open | does not take focus | |
| Clicks while closed, at the top edge and where the panel would be | both reached the window below | pass through |
| Click inside the open panel | stayed in the panel | |
| Click outside the open panel | panel closed, and the click reached the window below | |

The timings were measured by a script that moves the pointer and samples the screen every 5 ms, so they include up to one 50 ms polling interval and a frame of drawing.

## Still to check on the owner's hardware

These need hardware or a virtual machine this spike did not have, and none of them can be faked by a test:

- Windows 10 22H2.
- 125, 150 and 200 percent scaling on a real display, and two displays with different scaling (the placement math for all of these is unit-tested in `placement.rs`, and the 150 percent snapshot run renders crisply).
- A fullscreen video in a browser, a game in exclusive fullscreen, and a PowerPoint slideshow: the island should hide and come back.
- The tray icon's look in the light and dark taskbar; it currently uses the full-color app icon, and a monochrome glyph for each taskbar theme comes with phase 2's icon work.
- Flicker while opening over a busy, moving window (a playing video).

## Decisions made in the spike

- The open spring's few pixels of overshoot are held at the canvas edge rather than drawn outside it, so the window and its hit area stay exactly the canvas.
- The panel takes focus only when opened on purpose (click, hotkey, tray), never on hover, so moving the pointer to the top edge never interrupts typing.
- Outside clicks are seen by polling the mouse buttons every 16 ms, only while the panel is open; the hot zone is polled every 50 ms only while armed; otherwise the watcher wakes once a second.
- A gear button and the other tray items (Settings, Pause focus, Check for Updates) arrive with the features they open, so phase 1 ships no control that does nothing.
