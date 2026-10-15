//! One background thread that watches the pointer and the displays.
//!
//! It wakes only as often as the island's state needs: every 16 ms while the
//! panel is open (to see a click outside it), every 50 ms while the hidden
//! island's hot zone is armed (to see the pointer rest at the top edge), and
//! once a second otherwise (fullscreen apps and display changes). The rules
//! that decide what a reading means are pure functions below, so they are
//! tested without a desktop.

use crate::placement::{self, Monitor, Rect};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

/// How long the pointer must rest in the hot zone before the island opens, so
/// flicking up to a browser tab does not open it.
pub const HOT_ZONE_DWELL: Duration = Duration::from_millis(300);

const OPEN_TICK: Duration = Duration::from_millis(16);
const HOT_ZONE_TICK: Duration = Duration::from_millis(50);
const SLOW_TICK: Duration = Duration::from_secs(1);

/// What the watcher reports. The host turns each into an event for the UI.
#[derive(Debug, Clone, PartialEq)]
pub enum Signal {
    /// The pointer rested in the hot zone of this display.
    HotZone(Monitor),
    /// A mouse button went down outside the open panel's shape.
    OutsideClick,
    /// A fullscreen app took or left the island's display.
    Fullscreen(bool),
    /// Displays were added, removed, moved or rescaled, or a taskbar moved.
    DisplaysChanged(Vec<Monitor>),
}

/// What the host tells the watcher to look for.
#[derive(Debug, Clone, Default)]
pub struct Watch {
    /// Whether the hidden island's hot zone opens it.
    pub hot_zone: bool,
    /// The open panel's shape in physical screen pixels, while it is open.
    pub open_shape: Option<Rect>,
    /// The display the island is on, for the fullscreen check.
    pub display: Option<Monitor>,
    /// The island window, so it never counts as a fullscreen app.
    pub own_window: isize,
}

struct Shared {
    watch: Mutex<(Watch, bool)>,
    wake: Condvar,
}

/// A handle to the watcher thread. Changing what it watches wakes it at once.
#[derive(Clone)]
pub struct Watcher {
    shared: Arc<Shared>,
}

impl Watcher {
    pub fn spawn(emit: impl Fn(Signal) + Send + 'static) -> Self {
        let shared = Arc::new(Shared {
            watch: Mutex::new((Watch::default(), false)),
            wake: Condvar::new(),
        });
        let thread_shared = shared.clone();
        thread::Builder::new()
            .name("tabbi-watcher".into())
            .spawn(move || run(&thread_shared, &emit))
            .expect("the watcher thread starts");
        Self { shared }
    }

    pub fn update(&self, change: impl FnOnce(&mut Watch)) {
        let mut guard = self.shared.watch.lock().expect("watcher lock");
        change(&mut guard.0);
        drop(guard);
        self.shared.wake.notify_one();
    }

    pub fn stop(&self) {
        self.shared.watch.lock().expect("watcher lock").1 = true;
        self.shared.wake.notify_one();
    }
}

/// Tracks how long the pointer has rested in a hot zone. It fires once per
/// visit: the pointer has to leave the zone before it can fire again.
#[derive(Debug, Default)]
pub struct Dwell {
    since: Option<(Instant, Rect)>,
    fired: bool,
}

impl Dwell {
    /// Feeds one reading: the hot zone the pointer is in, if any. Returns true
    /// when the pointer has rested in the same zone for the dwell time.
    pub fn feed(&mut self, zone: Option<Rect>, now: Instant) -> bool {
        match (zone, self.since) {
            (None, _) => {
                self.since = None;
                self.fired = false;
                false
            }
            (Some(zone), Some((start, current))) if zone == current => {
                if !self.fired && now.duration_since(start) >= HOT_ZONE_DWELL {
                    self.fired = true;
                    return true;
                }
                false
            }
            (Some(zone), _) => {
                self.since = Some((now, zone));
                self.fired = false;
                false
            }
        }
    }
}

/// Detects a new press outside the open shape. A press that began inside the
/// panel (dragging out of it) does not count, and neither does a held button.
#[derive(Debug, Default)]
pub struct OutsidePress {
    was_pressed: bool,
}

impl OutsidePress {
    pub fn feed(&mut self, pressed: bool, pointer: Option<(i32, i32)>, shape: Rect) -> bool {
        let fresh = pressed && !self.was_pressed;
        self.was_pressed = pressed;
        fresh && pointer.is_some_and(|(x, y)| !shape.contains(x, y))
    }

    pub fn reset(&mut self) {
        self.was_pressed = false;
    }
}

/// The hot zone under the pointer, on any display.
pub fn zone_under(monitors: &[Monitor], pointer: Option<(i32, i32)>) -> Option<(Rect, Monitor)> {
    let (x, y) = pointer?;
    monitors
        .iter()
        .map(|m| (placement::hot_zone(m), *m))
        .find(|(zone, _)| zone.contains(x, y))
}

fn run(shared: &Shared, emit: &dyn Fn(Signal)) {
    let mut monitors = crate::win::monitors();
    let mut last_slow: Option<Instant> = None;
    let mut fullscreen = false;
    let mut dwell = Dwell::default();
    let mut outside = OutsidePress::default();

    loop {
        let (watch, stop) = {
            let guard = shared.watch.lock().expect("watcher lock");
            (guard.0.clone(), guard.1)
        };
        if stop {
            return;
        }
        let now = Instant::now();

        if last_slow.is_none_or(|t| now.duration_since(t) >= SLOW_TICK) {
            last_slow = Some(now);
            let current = crate::win::monitors();
            if current != monitors {
                monitors = current;
                emit(Signal::DisplaysChanged(monitors.clone()));
            }
            let now_fullscreen = watch
                .display
                .as_ref()
                .is_some_and(|display| crate::win::fullscreen_on(display, watch.own_window));
            if now_fullscreen != fullscreen {
                fullscreen = now_fullscreen;
                emit(Signal::Fullscreen(fullscreen));
            }
        }

        let pointer = if watch.hot_zone || watch.open_shape.is_some() {
            crate::win::cursor()
        } else {
            None
        };

        if watch.hot_zone && !fullscreen {
            let under = zone_under(&monitors, pointer);
            if dwell.feed(under.map(|(zone, _)| zone), now)
                && let Some((_, display)) = under
            {
                emit(Signal::HotZone(display));
            }
        } else {
            dwell.feed(None, now);
        }

        match watch.open_shape {
            Some(shape) => {
                if outside.feed(crate::win::mouse_pressed(), pointer, shape) {
                    emit(Signal::OutsideClick);
                }
            }
            None => outside.reset(),
        }

        let tick = if watch.open_shape.is_some() {
            OPEN_TICK
        } else if watch.hot_zone {
            HOT_ZONE_TICK
        } else {
            SLOW_TICK.saturating_sub(now.elapsed())
        };
        let guard = shared.watch.lock().expect("watcher lock");
        /* A change from the host wakes the thread early; either way it loops and re-reads. */
        let _ = shared.wake.wait_timeout(guard, tick).expect("watcher lock");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ZONE: Rect = Rect::new(835, 0, 1085, 4);
    const OTHER_ZONE: Rect = Rect::new(-1700, 0, -1325, 6);

    #[test]
    fn dwell_fires_once_after_the_pointer_rests() {
        let start = Instant::now();
        let mut dwell = Dwell::default();
        assert!(!dwell.feed(Some(ZONE), start));
        assert!(!dwell.feed(Some(ZONE), start + Duration::from_millis(250)));
        assert!(dwell.feed(Some(ZONE), start + Duration::from_millis(300)));
        assert!(
            !dwell.feed(Some(ZONE), start + Duration::from_millis(900)),
            "fires once per visit"
        );
    }

    #[test]
    fn dwell_restarts_when_the_pointer_leaves_or_changes_display() {
        let start = Instant::now();
        let mut dwell = Dwell::default();
        dwell.feed(Some(ZONE), start);
        dwell.feed(None, start + Duration::from_millis(200));
        assert!(
            !dwell.feed(Some(ZONE), start + Duration::from_millis(350)),
            "a flick does not open it"
        );
        assert!(dwell.feed(Some(ZONE), start + Duration::from_millis(650)));

        dwell.feed(None, start + Duration::from_millis(700));
        dwell.feed(Some(ZONE), start + Duration::from_millis(750));
        assert!(
            !dwell.feed(Some(OTHER_ZONE), start + Duration::from_millis(1100)),
            "a new display starts over"
        );
        assert!(dwell.feed(Some(OTHER_ZONE), start + Duration::from_millis(1400)));
    }

    #[test]
    fn outside_press_counts_new_presses_outside_the_shape_only() {
        let shape = Rect::new(680, 0, 1240, 236);
        let mut press = OutsidePress::default();
        assert!(
            !press.feed(true, Some((900, 100)), shape),
            "inside the panel"
        );
        assert!(
            !press.feed(true, Some((100, 500)), shape),
            "dragged out while held"
        );
        assert!(!press.feed(false, Some((100, 500)), shape));
        assert!(
            press.feed(true, Some((100, 500)), shape),
            "a fresh press outside"
        );
        assert!(
            !press.feed(true, Some((100, 500)), shape),
            "held, not a new press"
        );
        assert!(!press.feed(false, None, shape));
        assert!(
            !press.feed(true, None, shape),
            "no pointer reading, no click"
        );
    }

    #[test]
    fn the_zone_under_the_pointer_is_found_on_any_display() {
        let primary = Monitor {
            bounds: Rect::new(0, 0, 1920, 1080),
            work: Rect::new(0, 0, 1920, 1032),
            scale: 1.0,
        };
        let left = Monitor {
            bounds: Rect::new(-2560, 0, 0, 1440),
            work: Rect::new(-2560, 0, 0, 1392),
            scale: 1.5,
        };
        let monitors = [primary, left];
        assert_eq!(
            zone_under(&monitors, Some((960, 0))).map(|(_, m)| m),
            Some(primary)
        );
        assert_eq!(
            zone_under(&monitors, Some((-1280, 2))).map(|(_, m)| m),
            Some(left)
        );
        assert_eq!(zone_under(&monitors, Some((960, 40))), None);
        assert_eq!(zone_under(&monitors, None), None);
    }
}
