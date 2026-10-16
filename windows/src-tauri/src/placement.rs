//! Where the island sits on a display, in physical pixels.
//!
//! Pure math with no Win32 calls, so every display layout the island must
//! handle (scaling, a taskbar docked on any edge, monitors left of or above the
//! primary one) is covered by `cargo test` on any machine.

/// The open canvas in logical pixels: the Mac's `Theme.Layout.expandedSize`
/// (560 x 236 pt, the regular panel size). The island window is always this
/// size, and only its region (the visible shape) changes, so the webview
/// never reflows while the panel animates.
pub const CANVAS_WIDTH: f64 = 560.0;
pub const CANVAS_HEIGHT: f64 = 236.0;

/// The invisible strip at the top-center edge that opens the island when the
/// pointer rests in it. The Mac's hot zone is the closed notch plus 24 pt on
/// each side (a 190 pt virtual notch plus 12 pt of top flare when there is no
/// hardware notch); it is only a few pixels tall here because the top of a
/// Windows screen holds browser tabs and title bars.
pub const HOT_ZONE_WIDTH: f64 = 250.0;
pub const HOT_ZONE_HEIGHT: f64 = 4.0;

/// A rectangle in physical screen pixels, right and bottom exclusive (the
/// Win32 `RECT` convention).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl Rect {
    pub const fn new(left: i32, top: i32, right: i32, bottom: i32) -> Self {
        Self {
            left,
            top,
            right,
            bottom,
        }
    }

    pub const fn width(&self) -> i32 {
        self.right - self.left
    }

    pub const fn height(&self) -> i32 {
        self.bottom - self.top
    }

    pub const fn contains(&self, x: i32, y: i32) -> bool {
        x >= self.left && x < self.right && y >= self.top && y < self.bottom
    }

    pub const fn covers(&self, other: &Rect) -> bool {
        self.left <= other.left
            && self.top <= other.top
            && self.right >= other.right
            && self.bottom >= other.bottom
    }

    pub const fn offset(&self, dx: i32, dy: i32) -> Rect {
        Rect::new(
            self.left + dx,
            self.top + dy,
            self.right + dx,
            self.bottom + dy,
        )
    }
}

/// One display: its full bounds, its work area (the bounds minus docked
/// taskbars and app bars) and its scale (1.0 at 100 percent, 1.5 at 150).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Monitor {
    pub bounds: Rect,
    pub work: Rect,
    pub scale: f64,
}

/// Rounds a logical length to whole physical pixels.
fn physical(logical: f64, scale: f64) -> i32 {
    (logical * scale).round() as i32
}

/// The island window: the canvas centered on the work area and hanging from
/// its top edge, so a taskbar docked at the top pushes it down instead of
/// covering it, and one docked at a side keeps it centered over the apps.
pub fn island_rect(monitor: &Monitor) -> Rect {
    let width = physical(CANVAS_WIDTH, monitor.scale);
    let height = physical(CANVAS_HEIGHT, monitor.scale);
    let left = monitor.work.left + (monitor.work.width() - width) / 2;
    let top = monitor.work.top;
    Rect::new(left, top, left + width, top + height)
}

/// The hot zone sits centered under the island's top edge, so it lines up with
/// where the panel will drop down.
pub fn hot_zone(monitor: &Monitor) -> Rect {
    let island = island_rect(monitor);
    let width = physical(HOT_ZONE_WIDTH, monitor.scale);
    let height = physical(HOT_ZONE_HEIGHT, monitor.scale).max(2);
    let left = island.left + (island.width() - width) / 2;
    Rect::new(left, island.top, left + width, island.top + height)
}

/// A rectangle given in logical pixels relative to the island window, turned
/// into physical pixels relative to the same window (what `SetWindowRgn`
/// takes). The edges round outward so a shape is never clipped by a pixel.
pub fn region_rect(x: f64, y: f64, width: f64, height: f64, scale: f64) -> Rect {
    Rect::new(
        (x * scale).floor() as i32,
        (y * scale).floor() as i32,
        ((x + width) * scale).ceil() as i32,
        ((y + height) * scale).ceil() as i32,
    )
}

/// The monitor that contains a point, if any.
pub fn monitor_at(monitors: &[Monitor], x: i32, y: i32) -> Option<&Monitor> {
    monitors.iter().find(|m| m.bounds.contains(x, y))
}

/// The primary monitor is the one whose bounds hold the origin.
pub fn primary(monitors: &[Monitor]) -> Option<&Monitor> {
    monitor_at(monitors, 0, 0).or_else(|| monitors.first())
}

/// After displays change, the island stays on the display it was on when that
/// display still exists (matched by its bounds), and moves to the primary one
/// otherwise.
pub fn same_or_primary<'a>(
    monitors: &'a [Monitor],
    previous: Option<&Monitor>,
) -> Option<&'a Monitor> {
    previous
        .and_then(|p| monitors.iter().find(|m| m.bounds == p.bounds))
        .or_else(|| primary(monitors))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn monitor(bounds: Rect, work: Rect, scale: f64) -> Monitor {
        Monitor {
            bounds,
            work,
            scale,
        }
    }

    /// A 1920 x 1080 display with a 48 px taskbar at the bottom.
    fn full_hd(scale: f64) -> Monitor {
        let bounds = Rect::new(0, 0, 1920, 1080);
        monitor(bounds, Rect::new(0, 0, 1920, 1032), scale)
    }

    #[test]
    fn island_is_the_canvas_at_every_common_scale() {
        for (scale, width, height) in [
            (1.0, 560, 236),
            (1.25, 700, 295),
            (1.5, 840, 354),
            (2.0, 1120, 472),
        ] {
            let rect = island_rect(&full_hd(scale));
            assert_eq!(
                (rect.width(), rect.height()),
                (width, height),
                "scale {scale}"
            );
            assert_eq!(rect.top, 0, "hangs from the top edge at scale {scale}");
            assert_eq!(
                rect.left + rect.width() / 2,
                960,
                "centered at scale {scale}"
            );
        }
    }

    #[test]
    fn odd_widths_round_and_stay_centered_within_a_pixel() {
        /* 560 x 1.75 = 980, 236 x 1.75 = 413; a 1366 px wide work area leaves an odd remainder. */
        let m = monitor(Rect::new(0, 0, 1366, 768), Rect::new(0, 0, 1366, 728), 1.75);
        let rect = island_rect(&m);
        assert_eq!((rect.width(), rect.height()), (980, 413));
        let left_gap = rect.left;
        let right_gap = 1366 - rect.right;
        assert!(
            (left_gap - right_gap).abs() <= 1,
            "gaps {left_gap} and {right_gap}"
        );
    }

    #[test]
    fn a_taskbar_docked_at_the_top_pushes_the_island_down() {
        let m = monitor(
            Rect::new(0, 0, 1920, 1080),
            Rect::new(0, 48, 1920, 1080),
            1.0,
        );
        assert_eq!(island_rect(&m).top, 48);
        assert_eq!(hot_zone(&m).top, 48);
    }

    #[test]
    fn a_taskbar_docked_at_a_side_centers_the_island_over_the_apps() {
        let m = monitor(
            Rect::new(0, 0, 1920, 1080),
            Rect::new(62, 0, 1920, 1080),
            1.0,
        );
        let rect = island_rect(&m);
        assert_eq!(rect.left, 62 + (1858 - 560) / 2);
        assert_eq!(rect.top, 0);
    }

    #[test]
    fn monitors_left_of_and_above_the_primary_use_their_own_coordinates() {
        /* A 2560 x 1440 display at 150 percent to the left of the primary, and one above it. */
        let left = monitor(
            Rect::new(-2560, 0, 0, 1440),
            Rect::new(-2560, 0, 0, 1392),
            1.5,
        );
        let rect = island_rect(&left);
        assert_eq!(rect, Rect::new(-1280 - 420, 0, -1280 + 420, 354));

        let above = monitor(
            Rect::new(0, -1080, 1920, 0),
            Rect::new(0, -1080, 1920, -40),
            1.0,
        );
        assert_eq!(island_rect(&above).top, -1080);
        assert!(hot_zone(&above).contains(960, -1080));
    }

    #[test]
    fn the_hot_zone_is_a_thin_strip_centered_at_the_top_edge() {
        let m = full_hd(1.0);
        let zone = hot_zone(&m);
        assert_eq!(zone, Rect::new(835, 0, 1085, 4));
        assert!(zone.contains(960, 0));
        assert!(
            !zone.contains(960, 4),
            "a pointer over a browser tab just below the edge stays out"
        );
        assert!(!zone.contains(700, 0), "the corners of the screen stay out");

        let hidpi = hot_zone(&full_hd(2.0));
        assert_eq!((hidpi.width(), hidpi.height()), (500, 8));
    }

    #[test]
    fn the_hot_zone_is_never_thinner_than_two_pixels() {
        assert_eq!(hot_zone(&full_hd(0.25)).height(), 2);
    }

    #[test]
    fn region_rects_round_outward() {
        assert_eq!(
            region_rect(179.0, 0.0, 202.0, 32.0, 1.0),
            Rect::new(179, 0, 381, 32)
        );
        /* 179 x 1.25 = 223.75 and 381 x 1.25 = 476.25: floor the start, ceil the end. */
        assert_eq!(
            region_rect(179.0, 0.0, 202.0, 32.0, 1.25),
            Rect::new(223, 0, 477, 40)
        );
    }

    #[test]
    fn monitors_are_found_by_point_and_the_primary_holds_the_origin() {
        let primary_display = full_hd(1.0);
        let left = monitor(
            Rect::new(-2560, 0, 0, 1440),
            Rect::new(-2560, 0, 0, 1392),
            1.5,
        );
        let monitors = [left, primary_display];
        assert_eq!(monitor_at(&monitors, -10, 10), Some(&left));
        assert_eq!(monitor_at(&monitors, 1919, 1079), Some(&primary_display));
        assert_eq!(
            monitor_at(&monitors, 1920, 0),
            None,
            "right edge is exclusive"
        );
        assert_eq!(primary(&monitors), Some(&primary_display));
    }

    #[test]
    fn after_a_display_change_the_island_keeps_its_display_or_falls_back_to_the_primary() {
        let primary_display = full_hd(1.0);
        let left = monitor(
            Rect::new(-2560, 0, 0, 1440),
            Rect::new(-2560, 0, 0, 1392),
            1.5,
        );
        /* The same display with a new scale still counts as the same display. */
        let rescaled = Monitor { scale: 2.0, ..left };
        assert_eq!(
            same_or_primary(&[primary_display, rescaled], Some(&left)),
            Some(&rescaled)
        );
        assert_eq!(
            same_or_primary(&[primary_display], Some(&left)),
            Some(&primary_display)
        );
        assert_eq!(
            same_or_primary(&[primary_display], None),
            Some(&primary_display)
        );
        assert_eq!(same_or_primary(&[], None), None);
    }

    #[test]
    fn covers_is_inclusive_for_fullscreen_checks() {
        let screen = Rect::new(0, 0, 1920, 1080);
        assert!(screen.covers(&screen));
        assert!(
            Rect::new(-8, -8, 1928, 1088).covers(&screen),
            "a maximized-style frame overhang still covers"
        );
        assert!(
            !Rect::new(0, 0, 1920, 1032).covers(&screen),
            "a maximized window above the taskbar does not"
        );
    }
}
