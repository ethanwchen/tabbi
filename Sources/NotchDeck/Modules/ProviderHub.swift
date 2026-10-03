import Combine
import Foundation
import NotchKitCore

/// Merges what the enabled modules provide (tasks, events, progress, focus)
/// into one `ProviderSnapshot`, so consumers such as the ticker read shared
/// data without depending on the module that produced it.
///
/// Only enabled modules contribute, in tab order; a disabled module's data
/// disappears with its tab. Modules may publish from any thread; the hub
/// always merges and publishes on the main actor.
@MainActor
final class ProviderHub: ObservableObject {
    @Published private(set) var snapshot = ProviderSnapshot()

    /// Set once by `attach`, after the modules (which read this hub
    /// through their context) exist.
    private var registry: ModuleRegistry?
    private var enabled: [ModuleID] = []
    private var latest: [ModuleID: ModuleProvision] = [:]
    private var subscriptions: [ModuleID: AnyCancellable] = [:]
    /// Bumped per subscription, so a value that was already queued for the
    /// main actor when its module was turned off (or off and on again) is
    /// dropped instead of reviving stale data.
    private var generation: [ModuleID: Int] = [:]

    /// A hub with no modules yet; `attach` the registry once it exists.
    init() {}

    init(registry: ModuleRegistry) {
        self.registry = registry
    }

    /// Connects the modules whose provisions this hub merges.
    func attach(_ registry: ModuleRegistry) {
        precondition(self.registry == nil, "ProviderHub is attached once")
        self.registry = registry
    }

    /// Follows the enabled tabs: subscribes to newly enabled providers and
    /// drops disabled ones. Reordering only re-merges.
    func update(enabled: [ModuleID]) {
        var seen = Set<ModuleID>()
        self.enabled = enabled.filter { seen.insert($0).inserted }
        for id in subscriptions.keys where !seen.contains(id) {
            subscriptions[id] = nil
            latest[id] = nil
            generation[id, default: 0] += 1
        }
        for id in self.enabled where subscriptions[id] == nil {
            guard let provision = registry?[id]?.provision else { continue }
            // Publishers that emit on subscribe land here synchronously, so
            // the first snapshot already includes them. Values a module
            // sends from a background thread (a network callback) hop to
            // the main actor instead of trapping.
            generation[id, default: 0] += 1
            let current = generation[id, default: 0]
            subscriptions[id] = provision.sinkOnMainActor { [weak self] value in
                guard let self, self.generation[id] == current else { return }
                self.receive(value, from: id)
            }
        }
        merge()
    }

    private func receive(_ provision: ModuleProvision, from id: ModuleID) {
        guard latest[id] != provision else { return }
        latest[id] = provision
        merge()
    }

    private func merge() {
        let next = ProviderSnapshot(enabled.compactMap { id in latest[id].map { (id, $0) } })
        if next != snapshot { snapshot = next }
    }
}
