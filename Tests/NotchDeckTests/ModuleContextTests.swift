import Combine
import SwiftUI
import XCTest
import NotchKitCore
@testable import NotchDeck

/// A timer-like service two fixture modules share through the context.
@MainActor
private final class CountingService {
    static var made = 0
    init() { Self.made += 1 }
}

extension ModuleContext {
    fileprivate var counting: CountingService { shared.resolve { CountingService() } }
}

/// A module that builds everything it needs from its context.
@MainActor
private final class SelfContainedModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "self-contained", title: "Self-contained", symbol: "circle", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.5)
    )
    let context: ModuleContext
    let service: CountingService
    var kitsApplied: [String] = []
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        self.context = context
        service = context.counting
        context.kitApplied
            .sink { [weak self] in self?.kitsApplied.append($0.kit.id) }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView { AnyView(EmptyView()) }
    var provision: AnyPublisher<ModuleProvision, Never>? {
        Just(ModuleProvision(tasks: [ProvidedTask(id: "t", source: context.id, title: "From context")]))
            .eraseToAnyPublisher()
    }
}

/// A second module sharing the same service.
@MainActor
private final class SiblingModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "sibling", title: "Sibling", symbol: "circle", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.5)
    )
    let service: CountingService

    init(context: ModuleContext) { service = context.counting }

    func makePanel() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
final class ModuleContextTests: XCTestCase {
    private let types: [any NotchModule.Type] = [SelfContainedModule.self, SiblingModule.self]

    /// Builds modules the way `AppServices` does: one context per module,
    /// sharing one hub and one set of services.
    private func makeModules(settings: SettingsStore) -> (ModuleRegistry, ProviderHub) {
        let hub = ProviderHub()
        let shared = SharedServices()
        let registry = ModuleRegistry(types.map { type in
            type.init(context: ModuleContext(id: type.descriptor.id, edition: .notchDeck, settings: settings,
                                             providers: hub, shared: shared, isDemo: true, isSnapshot: false))
        })
        hub.attach(registry)
        return (registry, hub)
    }

    private func settings() -> SettingsStore {
        .ephemeral(catalog: ModuleCatalog(types.map { $0.descriptor }))
    }

    func testEachModuleGetsAContextForItsOwnId() throws {
        let (registry, _) = makeModules(settings: settings())
        let module = try XCTUnwrap(registry.module(SelfContainedModule.self))
        XCTAssertEqual(module.context.id, "self-contained")
        XCTAssertNil(registry.module(ProvidingModuleStandIn.self))
    }

    func testSharedServicesAreMadeOnceAndShared() throws {
        CountingService.made = 0
        let (registry, _) = makeModules(settings: settings())
        let first = try XCTUnwrap(registry.module(SelfContainedModule.self))
        let second = try XCTUnwrap(registry.module(SiblingModule.self))
        XCTAssertTrue(first.service === second.service)
        XCTAssertEqual(CountingService.made, 1)
    }

    func testHubAttachedAfterCreationMergesWhatModulesProvide() {
        let (_, hub) = makeModules(settings: settings())
        hub.update(enabled: ["self-contained", "sibling"])
        XCTAssertEqual(hub.snapshot.tasks.map(\.title), ["From context"])
        XCTAssertEqual(hub.snapshot.tasks.map(\.source), ["self-contained"])
    }

    func testModulesHearKitApplications() throws {
        let store = settings()
        let (registry, _) = makeModules(settings: store)
        let module = try XCTUnwrap(registry.module(SelfContainedModule.self))
        let kit = try XCTUnwrap(store.kits.kits.first)
        store.switchKit(to: kit.id)
        XCTAssertEqual(module.kitsApplied, [kit.id])
    }
}

/// A module type that is never registered, for the typed lookup.
@MainActor
private final class ProvidingModuleStandIn: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "absent", title: "Absent", symbol: "circle", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.5)
    )
    init(context: ModuleContext) {}
    func makePanel() -> AnyView { AnyView(EmptyView()) }
}
