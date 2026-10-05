import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Renders every notch state and Settings pane to PNG without showing a window:
///
///     swift run Tabbi --snapshot ./snapshots [--kit medicine] [--theme <id>|all] [--edition <id>]
///
/// The notch renders in the kit's theme unless `--theme` names one; with
/// `--theme all` every notch shot is rendered once per theme into a
/// subfolder named after the theme id.
///
/// Used to review UI changes (by people and by agents) without Screen
/// Recording permission. Live data sources run as usual, so panels show
/// whatever state they reach within `settle` seconds.
@MainActor
enum SnapshotRenderer {
    /// Which themes the notch shots are rendered in.
    enum ThemeSelection {
        /// The active kit's theme.
        case kit
        case one(AppTheme)
        /// Every theme, each in its own subfolder.
        case all

        /// Parses `--theme`'s value; an unknown id falls back to the kit's.
        init(argument: String?) {
            switch argument {
            case "all": self = .all
            case let id?: self = ThemeCatalog.theme(ThemeID(rawValue: id)).map(Self.one) ?? .kit
            case nil: self = .kit
            }
        }
    }

    /// - Parameter kitID: the kit whose tabs are rendered, as on first run.
    static func run(outputDirectory: URL, kitID: String = KitLibrary.defaultKitID, themes: ThemeSelection = .kit,
                    settle: TimeInterval = 1.5) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog, kitID: kitID))
        let kitTheme = ThemeCatalog.resolve(services.settings.settings.themeID)
        let themeFolders: [(AppTheme, URL)] = switch themes {
        case .kit: [(kitTheme, outputDirectory)]
        case .one(let theme): [(theme, outputDirectory)]
        case .all: ThemeCatalog.all.map { ($0, outputDirectory.appendingPathComponent($0.id.rawValue)) }
        }
        // 14"/16" MacBook Pro notch.
        let geometry = NotchGeometry(
            notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864
        )
        try? await Task.sleep(for: .seconds(settle))

        // Every shot uses the active kit's tab layout.
        let layout = services.settings.settings.modules
        var shots: [(String, NotchViewModel)] = []
        let closed = NotchViewModel(geometry: geometry, layout: layout)
        closed.preview = services.ticker.item
        shots.append(("closed", closed))
        // One closed shot per preview kind that has data. Demo usage sits
        // below the 80% threshold, so demo mode fills that one in.
        let now = Date()
        let isDemo = RunMode.current.isDemo
        for kind in TickerKind.all(in: services.settings.catalog) {
            let live = services.ticker.sources.items(at: now, enabled: [kind]).first
            let demoUsage: TickerItem? = isDemo && kind == .highlights(from: .claudeUsage)
                ? .highlight(ClaudeUsageHighlights.highlight(window: .fiveHour, utilization: 0.86)) : nil
            guard let item = live ?? demoUsage else { continue }
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.preview = item
            shots.append(("closed-\(snapshotName(kind))", model))
            // The pet's other look: dozing after a quiet spell.
            if case .pet(var pet) = item, pet.mood != .asleep {
                pet.mood = .asleep
                let asleep = NotchViewModel(geometry: geometry, layout: layout)
                asleep.preview = .pet(pet)
                shots.append(("closed-pet-asleep", asleep))
            }
        }
        // One open shot per tab of the active kit.
        for module in layout.enabled {
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.open(module)
            shots.append(("open-\(module.rawValue)", model))
        }
        // And one per tab the kit leaves off (e.g. Focus), as if turned on,
        // so every module's panel can be reviewed under any kit.
        for module in layout.order where !layout.isEnabled(module) {
            var withModule = layout
            _ = withModule.setEnabled(module, true)
            let model = NotchViewModel(geometry: geometry, layout: withModule)
            model.open(module)
            shots.append(("open-\(module.rawValue)", model))
        }

        // The Closet's second section, rendered after the others because
        // the open section is store state.
        if layout.order.contains(.closet) {
            var withCloset = layout
            _ = withCloset.setEnabled(.closet, true)
            let model = NotchViewModel(geometry: geometry, layout: withCloset)
            model.open(.closet)
            shots.append(("open-closet-look", model))
        }

        let closet = services.modules.module(ClosetModule.self)
        for (theme, folder) in themeFolders {
            Theme.apply(theme)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            renderNotchShots(shots, services: services, closet: closet, to: folder)
        }
        Theme.apply(kitTheme)

        // The pet coach's overlay: walking out, then each kind of bubble.
        let coachShots = closet.map { PetCoachSnapshots.shots(profile: $0.store.profile, lines: $0.coach.lines) } ?? []
        for (name, view) in coachShots {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }

        let settingsWindow = SettingsWindowController(settings: services.settings, modules: services.modules)
        for pane in settingsWindow.paneIDs {
            guard let png = await settingsWindow.snapshot(of: pane) else { continue }
            let url = outputDirectory.appendingPathComponent("settings-\(pane).png")
            try? png.write(to: url)
            print(url.path)
        }

        // The first-run kit picker, before anything is chosen.
        if let png = await WelcomeWindowController(settings: services.settings).snapshot() {
            let url = outputDirectory.appendingPathComponent("welcome.png")
            try? png.write(to: url)
            print(url.path)
        }
        // Its second step: the active kit's onboarding questions.
        let kitID = services.settings.settings.kitID
        if services.settings.kits[kitID]?.onboarding.isEmpty == false,
           let png = await WelcomeWindowController(settings: services.settings, questionsFor: kitID).snapshot() {
            let url = outputDirectory.appendingPathComponent("welcome-questions.png")
            try? png.write(to: url)
            print(url.path)
        }
        // The same questions as the sheet Settings shows when switching kits.
        if let kit = services.settings.kits[kitID], !kit.onboarding.isEmpty,
           let png = await sheetSnapshot(KitQuestionsView(kit: kit, dismissal: .cancel, back: {}, start: { _ in })
               .environment(\.moduleCatalog, services.settings.catalog)
               .frame(width: 520)) {
            let url = outputDirectory.appendingPathComponent("settings-kit-questions.png")
            try? png.write(to: url)
            print(url.path)
        }
        await renderKitImportReview(services, to: outputDirectory)
    }

    /// Renders each notch shot in the active theme into `folder`.
    private static func renderNotchShots(_ shots: [(String, NotchViewModel)], services: AppServices,
                                         closet: ClosetModule?, to folder: URL) {
        let firstSection = closet?.store.section
        for (name, model) in shots {
            if let firstSection { closet?.store.section = name == "open-closet-look" ? .look : firstSection }
            model.themeID = Theme.current.id
            let view = NotchView(content: ModuleViews.notchContent(services: services))
                .environmentObject(model)
                .environment(\.drawsLiquidGlass, false)
                .frame(width: Theme.Layout.expandedSize.width + 40,
                       height: Theme.Layout.expandedSize.height + 24, alignment: .top)
                .background(Color(white: 0.16)) // stand-in for a desktop
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            let url = folder.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }
    }

    /// The review Settings shows before applying an imported kit: another
    /// bundled kit posing as an update of an earlier import, so every row
    /// shows.
    private static func renderKitImportReview(_ services: AppServices, to outputDirectory: URL) async {
        let settings = services.settings
        let others = settings.kits.kits.filter { $0.id != settings.settings.kitID }
        guard var kit = others.first(where: { !$0.starterTasks.isEmpty }) ?? others.first else { return }
        var earlier = kit
        earlier.version = "1.2"
        kit.version = "1.3"
        let candidate = KitImportCandidate(kit: kit, data: Data(), fileName: "\(kit.id).json", replaces: earlier)
        let review = KitImportReviewView(
            candidate: candidate, preview: settings.preview(of: kit), issues: settings.issues(of: kit),
            isActiveKit: false, back: nil, cancel: {}, addOnly: {}, apply: {}
        )
        if let png = await sheetSnapshot(review.environment(\.moduleCatalog, settings.catalog).frame(width: 520)) {
            let url = outputDirectory.appendingPathComponent("settings-kit-import.png")
            try? png.write(to: url)
            print(url.path)
        }
    }

    /// Renders a sheet's content in an off-screen titleless window, since
    /// ImageRenderer can't draw AppKit-backed controls such as buttons.
    private static func sheetSnapshot(_ content: some View) async -> Data? {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        try? await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)
        else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// A module's highlights are named after the module.
    private static func snapshotName(_ kind: TickerKind) -> String {
        switch kind {
        case .nowPlaying: "music"
        case .highlights(from: .claudeUsage): "usage"
        default: kind.rawValue
        }
    }
}
