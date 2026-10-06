import TabbiKitCore

/// Every module this build has, one per line, in canonical order (the order
/// Settings lists modules a kit doesn't mention). Adding a module means
/// adding its line here; titles, symbols, accents, layouts and kit
/// validation all read the catalog built from this list.
@MainActor
enum ModuleList {
    static let all: [any NotchModule.Type] = [
        NowPlayingModule.self,
        SystemModule.self,
        ClaudeUsageModule.self,
        TodayModule.self,
        AskClaudeModule.self,
        FocusModule.self,
        StudyModule.self,
        AnkiModule.self,
        PartyModule.self,
        ClosetModule.self,
        ScheduleModule.self,
    ]

    /// The listed modules' descriptors, for layouts, kits and the tab bar.
    static let catalog = catalog(of: all)

    /// The descriptors of `modules`, in list order. Tests use it to run the
    /// app with a module list of their own.
    static func catalog(of modules: [any NotchModule.Type]) -> ModuleCatalog {
        ModuleCatalog(modules.map { $0.descriptor })
    }
}
