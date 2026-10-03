@preconcurrency import Combine
import SwiftUI
import XCTest
import NotchKitCore
@testable import NotchDeck

/// A module that only provides, fed by a subject the test controls.
@MainActor
private final class ProvidingModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "providing", title: "Providing", symbol: "circle", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.5)
    )
    let subject: CurrentValueSubject<ModuleProvision, Never>

    init(_ initial: ModuleProvision = .empty) {
        subject = CurrentValueSubject(initial)
    }

    func makePanel() -> AnyView { AnyView(EmptyView()) }
    var provision: AnyPublisher<ModuleProvision, Never>? { subject.eraseToAnyPublisher() }
}

@MainActor
final class ProviderHubTests: XCTestCase {
    private func task(_ id: String) -> ProvidedTask {
        ProvidedTask(id: id, source: ModuleID("unset"), title: id)
    }

    func testFirstSnapshotIncludesValuesEmittedOnSubscribe() {
        let module = ProvidingModule(ModuleProvision(tasks: [task("a")]))
        let hub = ProviderHub(registry: ModuleRegistry([module]))
        hub.update(enabled: [module.id])
        XCTAssertEqual(hub.snapshot.tasks.map(\.id), ["a"])
    }

    func testBackgroundEmissionsAreDeliveredOnTheMainActor() {
        let module = ProvidingModule()
        let hub = ProviderHub(registry: ModuleRegistry([module]))
        hub.update(enabled: [module.id])
        let delivered = expectation(description: "background value merged")
        let watch = hub.$snapshot.dropFirst().sink { snapshot in
            XCTAssertTrue(Thread.isMainThread)
            if snapshot.tasks.map(\.id) == ["from-network"] { delivered.fulfill() }
        }
        let subject = module.subject
        let task = task("from-network")
        DispatchQueue.global().async {
            subject.send(ModuleProvision(tasks: [task]))
        }
        wait(for: [delivered], timeout: 5)
        watch.cancel()
    }

    func testConcurrentBackgroundEmissionsSettleOnTheLatestValue() {
        let module = ProvidingModule()
        let hub = ProviderHub(registry: ModuleRegistry([module]))
        hub.update(enabled: [module.id])
        let subject = module.subject
        let tasks = (0..<200).map { task("t\($0)") }
        DispatchQueue.concurrentPerform(iterations: 4) { lane in
            for task in tasks where Int(task.id.dropFirst())! % 4 == lane {
                subject.send(ModuleProvision(tasks: [task]))
            }
        }
        subject.send(ModuleProvision(tasks: [task("last")]))
        drainMainQueue()
        XCTAssertEqual(hub.snapshot.tasks.map(\.id), ["last"])
    }

    /// Sends `provision` from a background thread and blocks the main
    /// thread (without spinning its run loop) until it was sent, so its
    /// delivery is still queued when this returns.
    private func sendFromBackground(_ provision: ModuleProvision, to module: ProvidingModule) {
        let subject = module.subject
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            subject.send(provision)
            sent.signal()
        }
        sent.wait()
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    func testValueQueuedBeforeTheModuleIsTurnedOffIsDropped() {
        let module = ProvidingModule()
        let hub = ProviderHub(registry: ModuleRegistry([module]))
        hub.update(enabled: [module.id])
        sendFromBackground(ModuleProvision(tasks: [task("stale")]), to: module)
        hub.update(enabled: [])
        drainMainQueue()
        XCTAssertTrue(hub.snapshot.tasks.isEmpty)
    }

    func testValueQueuedBeforeTheModuleIsTurnedOffAndOnDoesNotOverwriteNewerData() {
        let module = ProvidingModule()
        let hub = ProviderHub(registry: ModuleRegistry([module]))
        hub.update(enabled: [module.id])
        sendFromBackground(ModuleProvision(tasks: [task("stale")]), to: module)
        hub.update(enabled: [])
        module.subject.send(ModuleProvision(tasks: [task("fresh")]))
        hub.update(enabled: [module.id])
        drainMainQueue()
        XCTAssertEqual(hub.snapshot.tasks.map(\.id), ["fresh"])
    }
}
