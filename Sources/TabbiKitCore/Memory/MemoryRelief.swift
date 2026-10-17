import Darwin
import Dispatch

/// Hands memory Tabbi no longer uses back to macOS.
///
/// Freeing objects returns their bytes to malloc, not to the system: the
/// pages stay dirty and keep counting toward the app's footprint (what
/// Activity Monitor shows) until malloc is asked to give free pages back.
/// A short burst of work (a Settings window, a week of transcripts) can so
/// leave tens of megabytes behind for the rest of the day. Call
/// `returnFreedPages()` after such a burst, never on a timer: it walks the
/// heap's free lists, which costs a millisecond or two.
public enum MemoryRelief {
    /// Returns the heap's free pages to the system.
    public static func returnFreedPages() {
        malloc_zone_pressure_relief(nil, 0)
    }

    /// Calls `relieve` on the main queue whenever macOS reports memory
    /// pressure (warning or critical), after returning free pages itself.
    /// The handler should drop caches that can be rebuilt. Keep the returned
    /// source alive for as long as the handler should run.
    public static func onMemoryPressure(_ relieve: @escaping @MainActor @Sendable () -> Void) -> DispatchSourceMemoryPressure {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                relieve()
                returnFreedPages()
            }
        }
        source.activate()
        return source
    }
}
