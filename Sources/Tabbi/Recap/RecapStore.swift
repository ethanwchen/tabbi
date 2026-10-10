import Combine
import Foundation
import TabbiKit
import TabbiKitCore

/// The weekly recaps: builds each finished week's numbers from the shared
/// activity log on Sunday evening, keeps them in a `RecapArchive` saved in
/// the edition's `Recaps` folder, and says which recap the notch should
/// show once and which still needs its notification.
///
/// It reads only `ActivityLog`, so a recap counts whatever any module
/// logged. Demo runs show `RecapArchive.demo` and build nothing; demo and
/// snapshot runs never read or write the file.
@MainActor
final class RecapStore: ObservableObject {
    @Published private(set) var archive: RecapArchive

    private let activity: ActivityLog
    private let saveURL: URL?
    private let builds: Bool
    private let calendar: Calendar
    private let now: () -> Date
    /// A file that exists but can't be read is left alone, so a newer
    /// format or a damaged file is never replaced by a fresh archive.
    private let saveIsUnreadable: Bool
    private lazy var alarm = WallClockAlarm { [weak self] in
        self?.buildOnSchedule()
        self?.scheduleNextBuild()
    }

    /// Runs after a build on start or at Sunday evening, not after the one
    /// on opening the notch, which shows the card instead. The notification
    /// for a ready recap goes out from here.
    var onScheduledBuild: (() -> Void)?

    /// - Parameters:
    ///   - now: the clock, so tests can step through a week.
    init(storage: EditionStorage, runMode: RunMode, activity: ActivityLog, calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.activity = activity
        self.calendar = calendar
        self.now = now
        builds = !runMode.isDemo
        let url = runMode.isEphemeral ? nil : RecapStore.saveURL(in: storage)
        var unreadable = false
        var archive = RecapArchive()
        if runMode.isDemo {
            archive = .demo(now: now(), calendar: calendar)
        } else if let url {
            do {
                archive = try RecapArchive.load(from: url) ?? RecapArchive()
            } catch {
                unreadable = true
            }
        }
        self.archive = archive
        saveURL = url
        saveIsUnreadable = unreadable
    }

    static func saveURL(in storage: EditionStorage) -> URL {
        RecapArchive.fileURL(in: storage.folder(RecapArchive.folderName))
    }

    /// Builds the weeks that are ready now and saves when anything changed.
    /// Called on start, at each Sunday evening and when the notch opens, so
    /// a Mac that slept through Sunday still gets its recap.
    func refresh() {
        guard builds else { return }
        let date = now()
        var changed = false
        for week in archive.weeksToBuild(at: date, calendar: calendar) {
            let records = activity.records(from: week.start, through: week.end(calendar: calendar))
            let recap = WeeklyRecap(week: week, records: records, calendar: calendar)
            changed = archive.record(recap, builtAt: date, calendar: calendar) || changed
        }
        if changed { save() }
    }

    /// The newest recap, when the user hasn't seen its card yet.
    var unseen: WeeklyRecap? { archive.unseen }

    /// The newest recap, when it still needs its notification.
    var unnotified: WeeklyRecap? { archive.unnotified }

    /// `recap`'s warm line, against the weeks before it.
    func cheer(for recap: WeeklyRecap) -> RecapCheer { archive.cheer(for: recap, calendar: calendar) }

    func markSeen(_ week: RecapWeek) {
        if archive.markSeen(week) { save() }
    }

    func markNotified(_ week: RecapWeek) {
        if archive.markNotified(week) { save() }
    }

    /// Builds what is ready and wakes again for the next Sunday evening.
    func start() {
        buildOnSchedule()
        scheduleNextBuild()
    }

    func stop() { alarm.cancel() }

    /// When the archive next has work: Monday midnight while the newest
    /// ready week can still change (to settle it), else next Sunday evening.
    var nextBuildDate: Date {
        let date = now()
        let latest = RecapWeek.latestReady(at: date, calendar: calendar)
        let next = latest.adding(weeks: 1, calendar: calendar)
        if archive.weeksToBuild(at: date, calendar: calendar).contains(latest) {
            return next.start.startDate(calendar: calendar)
        }
        return next.readyDate(calendar: calendar)
    }

    private func buildOnSchedule() {
        refresh()
        onScheduledBuild?()
    }

    private func scheduleNextBuild() {
        guard builds else { return }
        // A minute of slack is fine for a weekly card and lets macOS batch it.
        alarm.schedule(at: nextBuildDate, tolerance: 60)
    }

    private func save() {
        guard let saveURL, !saveIsUnreadable else { return }
        try? archive.write(to: saveURL)
    }
}

extension ModuleContext {
    /// The one recap store, built from the shared activity log.
    var weeklyRecaps: RecapStore {
        shared.resolve { RecapStore(storage: storage, runMode: runMode, activity: activityLog) }
    }
}
