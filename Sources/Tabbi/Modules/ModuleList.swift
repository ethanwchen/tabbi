import TabbiKitCore

/// Every module this build has, one per line, in canonical order (the order
/// Settings lists modules a kit doesn't mention). Adding a module means
/// adding its line here; titles, symbols, accents, layouts and kit
/// validation all read the catalog built from this list. The App Store build
/// (`APPSTORE`) has no modules that run the claude CLI; editions can leave
/// out more through `Edition.excludedModules`.
@MainActor
enum ModuleList {
    static let all: [any NotchModule.Type] = ([
        NowPlayingModule.self,
        SystemModule.self,
        claudeUsage,
        TodayModule.self,
        askClaude,
        FocusModule.self,
        StudyModule.self,
        AnkiModule.self,
        PartyModule.self,
        ClosetModule.self,
        ScheduleModule.self,
    ] as [(any NotchModule.Type)?]).compactMap { $0 }

    // The modules that run the claude CLI, which a sandboxed app cannot.
    // The App Store build leaves them out; its catalog knows them as
    // unavailable, so kits that list them apply without a warning.
    #if APPSTORE
    private static let claudeUsage: (any NotchModule.Type)? = nil
    private static let askClaude: (any NotchModule.Type)? = nil
    private static let compiledOut: [ModuleID] = [.claudeUsage, .claudeAsk]
    #else
    private static let claudeUsage: (any NotchModule.Type)? = ClaudeUsageModule.self
    private static let askClaude: (any NotchModule.Type)? = AskClaudeModule.self
    private static let compiledOut: [ModuleID] = []
    #endif

    /// The listed modules' descriptors, for layouts, kits and the tab bar.
    static let catalog = catalog(of: all).excluding(compiledOut)

    /// The descriptors of `modules`, in list order. Tests use it to run the
    /// app with a module list of their own.
    static func catalog(of modules: [any NotchModule.Type]) -> ModuleCatalog {
        ModuleCatalog(modules.map { $0.descriptor })
    }

    /// The modules `edition` offers: `catalog` without its excluded modules.
    /// The app resolves settings, kits and the tab bar against it, and
    /// `AppServices` only creates the modules it contains.
    static func catalog(for edition: Edition) -> ModuleCatalog {
        edition.catalog(from: catalog)
    }
}
