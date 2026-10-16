//! Events for the island's UI that arrive before it is listening.
//!
//! A `tabbi://` link that launches Tabbi, a tray click or the hotkey in the
//! first moments after launch would otherwise be emitted before the page has
//! registered its listeners, and lost. Until the UI calls `island_ready`
//! (which it does only once every listener is registered), events wait here
//! in order; then they are delivered and later ones go straight out.

use serde::Serialize;
use serde_json::Value;
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, Manager};

/// At most this many events wait; the oldest are dropped past it, since only
/// the latest of a burst of toggles or placements matters.
const MAX_WAITING: usize = 32;

/// Registered on the builder, before any plugin can fire, so it always exists.
#[derive(Default)]
pub struct Outbox(Mutex<Gate>);

#[derive(Default)]
struct Gate {
    open: bool,
    waiting: Vec<(&'static str, Value)>,
}

impl Gate {
    /// Holds an event while closed; returns it to send when open.
    fn admit(&mut self, event: &'static str, payload: Value) -> Option<(&'static str, Value)> {
        if self.open {
            return Some((event, payload));
        }
        if self.waiting.len() == MAX_WAITING {
            self.waiting.remove(0);
        }
        self.waiting.push((event, payload));
        None
    }

    /// Opens the gate and hands back everything that waited, oldest first.
    fn open(&mut self) -> Vec<(&'static str, Value)> {
        self.open = true;
        std::mem::take(&mut self.waiting)
    }
}

/// Sends an event to the island's UI now, or once it is ready.
pub fn send(app: &AppHandle, event: &'static str, payload: impl Serialize) {
    let Ok(payload) = serde_json::to_value(payload) else {
        return;
    };
    let now = match app.try_state::<Outbox>() {
        Some(outbox) => match outbox.0.lock() {
            Ok(mut gate) => gate.admit(event, payload),
            Err(_) => Some((event, payload)),
        },
        None => Some((event, payload)),
    };
    if let Some((event, payload)) = now {
        let _ = app.emit(event, payload);
    }
}

/// The UI is listening: deliver what waited, in order.
pub fn open(app: &AppHandle) {
    let waiting = app
        .try_state::<Outbox>()
        .and_then(|outbox| outbox.0.lock().ok().map(|mut gate| gate.open()))
        .unwrap_or_default();
    for (event, payload) in waiting {
        let _ = app.emit(event, payload);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn events_wait_until_the_gate_opens_then_go_straight_out() {
        let mut gate = Gate::default();
        assert_eq!(gate.admit("island:link", json!("tabbi://open")), None);
        assert_eq!(gate.admit("island:toggle", json!("tray")), None);
        assert_eq!(
            gate.open(),
            vec![
                ("island:link", json!("tabbi://open")),
                ("island:toggle", json!("tray"))
            ]
        );
        assert_eq!(
            gate.admit("island:hot-zone", json!(null)),
            Some(("island:hot-zone", json!(null)))
        );
        assert!(
            gate.open().is_empty(),
            "opening again delivers nothing twice"
        );
    }

    #[test]
    fn a_long_wait_keeps_the_newest_events() {
        let mut gate = Gate::default();
        for n in 0..(MAX_WAITING + 5) {
            gate.admit("island:placed", json!(n));
        }
        let waiting = gate.open();
        assert_eq!(waiting.len(), MAX_WAITING);
        assert_eq!(waiting.first().map(|(_, p)| p.clone()), Some(json!(5)));
    }
}
