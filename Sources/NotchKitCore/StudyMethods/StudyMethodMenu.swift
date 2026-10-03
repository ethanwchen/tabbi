import Foundation

/// The study methods the Study timer offers and the one it starts on.
///
/// A kit picks these in its Study section (`moduleSettings.study.methods`
/// and `method`), so a
/// medicine kit can lead with Anki sprints and question blocks while a
/// general student kit offers only the classic timers, without the Study
/// module hardcoding either. The menu is never empty: a kit that names no
/// known method offers every preset.
public struct StudyMethodMenu: Equatable, Sendable {
    /// Offered methods in order, without duplicates; never empty.
    public let kinds: [StudyMethodKind]
    /// Where a fresh timer starts; always one of `kinds`.
    public let startingKind: StudyMethodKind

    /// - Parameters:
    ///   - kinds: methods to offer in order, or nil (or none known) for every preset.
    ///   - starting: the method to start on; ignored unless offered, in
    ///     which case the first offered method is used.
    public init(kinds: [StudyMethodKind]? = nil, starting: StudyMethodKind? = nil) {
        var seen = Set<StudyMethodKind>()
        let offered = (kinds ?? []).filter { seen.insert($0).inserted }
        let kinds = offered.isEmpty ? StudyMethod.presets.map(\.kind) : offered
        self.kinds = kinds
        startingKind = starting.flatMap { kinds.contains($0) ? $0 : nil } ?? kinds[0]
    }

    /// The menu a kit sets up; every preset when the kit says nothing.
    /// Unknown method names are skipped.
    public init(kit defaults: KitDefaults?) {
        let section = defaults?.settings(for: .study)
        self.init(kinds: Self.kitKinds(in: section), starting: Self.kitStartingKind(of: defaults))
    }

    /// The method a kit starts on: its `method` if known, otherwise the
    /// first known one in `methods`; nil when it names neither. Today plans
    /// study blocks on it too.
    public static func kitStartingKind(of defaults: KitDefaults?) -> StudyMethodKind? {
        let section = defaults?.settings(for: .study)
        return section?["method"]?.stringValue.flatMap(StudyMethodKind.init(rawValue:)) ?? kitKinds(in: section)?.first
    }

    /// The keys the menu reads from the Study section, for its descriptor.
    public static let kitSettingFields: [String: KitSettingType] = [
        "methods": .list(methodChoice, maxCount: StudyMethodKind.allCases.count),
        "method": methodChoice,
    ]

    private static let methodChoice = KitSettingType.choice(StudyMethodKind.allCases.map(\.rawValue))

    /// Known methods from `methods`, or nil when the kit has no list.
    private static func kitKinds(in section: KitValue?) -> [StudyMethodKind]? {
        section?["methods"]?.arrayValue.map { $0.compactMap { $0.stringValue.flatMap(StudyMethodKind.init(rawValue:)) } }
    }

    /// Every preset, starting on Pomodoro.
    public static let all = StudyMethodMenu()

    /// The offered methods' presets, for the picker.
    public var methods: [StudyMethod] { kinds.map(StudyMethod.preset) }

    public func offers(_ kind: StudyMethodKind) -> Bool { kinds.contains(kind) }

    /// The method a session on `session.method` should move to when this
    /// menu takes effect, or nil to leave it alone.
    ///
    /// A session whose clock has started (running, paused, or on a break)
    /// is never interrupted. A stopped one moves to `startingKind` when the
    /// kit was just applied (`kitApplied`), so picking a kit starts it the
    /// way the kit intends, and otherwise only when its method is no longer
    /// offered.
    public func replacement(for session: StudySession, kitApplied: Bool) -> StudyMethodKind? {
        guard session.runState == .idle, session.phase == .focus else { return nil }
        let current = session.method.kind
        if kitApplied { return current == startingKind ? nil : startingKind }
        return offers(current) ? nil : startingKind
    }
}
