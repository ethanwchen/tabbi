import Foundation
import TabbiKit
import TabbiKitCore

/// Marks the start of a seasonal event with one small moment: the first
/// time Tabbi runs during the event, the pet beside the closed notch does a
/// little dance (a `PetCheer`). If a panel is open then, it waits for the
/// notch to close. Each run is greeted once (`SeasonalEventGreeting`), so
/// it is never repeated; the Closet's banner says the rest.
@MainActor
final class SeasonalEventGreeter {
    private let celebrations: CelebrationCenter?
    /// The moment to read events at: the Closet's `seasonNow`, which a demo pins.
    private let now: () -> Date
    private let saveURL: URL?
    private let isDemo: Bool
    private var greeting: SeasonalEventGreeting
    /// Set when the save could not be read: greet from memory, never overwrite.
    private let saveIsUnreadable: Bool
    private lazy var alarm = WallClockAlarm { [weak self] in self?.check() }

    /// A beat after launch, so the closed notch is up before the pet dances.
    static let launchDelay: TimeInterval = 4

    init(storage: EditionStorage, runMode: RunMode, celebrations: CelebrationCenter?,
         now: @escaping () -> Date) {
        self.celebrations = celebrations
        self.now = now
        isDemo = runMode.isDemo
        saveURL = runMode.isEphemeral ? nil : Self.saveURL(in: storage)
        var unreadable = false
        var greeting = SeasonalEventGreeting()
        if let saveURL {
            do {
                greeting = try SeasonalEventGreeting.load(from: saveURL) ?? greeting
            } catch {
                unreadable = true
            }
        }
        self.greeting = greeting
        saveIsUnreadable = unreadable
    }

    /// `~/Library/Application Support/<edition>/Pet/events.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("events.json", in: "Pet")
    }

    func start() {
        alarm.schedule(at: Date.now.addingTimeInterval(Self.launchDelay))
    }

    func stop() {
        alarm.cancel()
    }

    /// Greets a run that just started (or was never greeted), then waits
    /// for the next one to start. A demo's pinned moment never moves, so a
    /// demo greets once per launch and sets no alarm.
    func check() {
        let moment = now()
        if !greeting.greet(at: moment).isEmpty {
            celebrations?.cheer(.dance, waitsForClose: true)
            persist()
        }
        guard !isDemo, let next = SeasonalEventGreeting.nextCheck(after: moment) else { return }
        alarm.schedule(at: next, tolerance: 60)
    }

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        try? greeting.write(to: saveURL)
    }
}
