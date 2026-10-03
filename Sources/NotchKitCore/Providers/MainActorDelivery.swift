import Combine
import Foundation

extension Publisher where Failure == Never {
    /// Subscribes and hands every value to `receiveValue` on the main actor,
    /// whatever thread the publisher emits on, in emission order.
    ///
    /// Values emitted on the main thread are delivered synchronously (so a
    /// publisher that emits on subscribe is seen before this returns), and
    /// values from any other thread, say a network callback, hop to the main
    /// queue. A main-thread value never overtakes a background one still
    /// queued, so the last value sent is the last one delivered. Use it
    /// wherever a main-actor object follows a publisher it does not control,
    /// such as a module's `provision`, instead of `MainActor.assumeIsolated`,
    /// which traps off the main thread.
    public func sinkOnMainActor(
        _ receiveValue: @escaping @MainActor (Output) -> Void
    ) -> AnyCancellable {
        let queue = MainDeliveryQueue()
        return sink { value in
            if Thread.isMainThread, queue.isIdle {
                MainActor.assumeIsolated { receiveValue(value) }
            } else {
                // A box keeps Swift 5 mode from asking `Output` to be Sendable;
                // the value crosses to the main queue once, unshared.
                let box = UncheckedBox(value)
                queue.enqueue {
                    MainActor.assumeIsolated { receiveValue(box.value) }
                }
            }
        }
    }
}

/// Counts deliveries queued for the main thread, so a later main-thread
/// value waits its turn behind them instead of arriving first.
private final class MainDeliveryQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0

    var isIdle: Bool { lock.withLock { pending == 0 } }

    func enqueue(_ work: @escaping @Sendable () -> Void) {
        lock.withLock { pending += 1 }
        DispatchQueue.main.async {
            work()
            self.lock.withLock { self.pending -= 1 }
        }
    }
}

/// Carries a value across one thread hop that the caller knows is safe.
private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
