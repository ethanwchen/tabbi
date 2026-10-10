import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Renders every notch state and Settings pane to PNG without showing a window:
///
///     swift run Tabbi --snapshot ./snapshots [--kit medicine] [--theme <id>|all] [--edition <id>]
///                                          [--scale <factor>] [--transparent]
///
/// The notch renders in the kit's theme unless `--theme` names one; with
/// `--theme all` every notch shot is rendered once per theme into a
/// subfolder named after the theme id.
///
/// `--scale` sets the pixels per point of the notch shots (2 by default), and
/// `--transparent` leaves out their stand-in desktop, so marketing images
/// (`docs/appstore/make-media.swift`) can place the panel crisply at
/// any size on a backdrop of their own.
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
                    notchStyle: NotchStyle = NotchStyle(), settle: TimeInterval = 1.5) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog(for: .current), kitID: kitID))
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
        var shots: [Shot] = []
        let closed = NotchViewModel(geometry: geometry, layout: layout)
        closed.preview = services.ticker.item
        shots.append(Shot("closed", closed))
        // One closed shot per preview kind that has data. Demo usage sits
        // below the 80% threshold, so demo mode fills that one in.
        let now = Date()
        let isDemo = RunMode.current.isDemo
        let closet = services.modules.module(ClosetModule.self)
        for kind in TickerKind.all(in: services.settings.catalog) {
            let live = services.ticker.sources.items(at: now, enabled: [kind]).first
            let demoUsage: TickerItem? = isDemo && kind == .highlights(from: .claudeUsage)
                ? .highlight(ClaudeUsageHighlights.highlight(window: .fiveHour, utilization: 0.86)) : nil
            // A kit with the Closet off publishes no pet, so the pet comes
            // from the shared save, as if the Closet were on.
            let offKitPet: TickerItem? = kind == .pet
                ? closet.map { .pet(TickerPet(profile: $0.store.profile, mood: .awake)) } : nil
            guard let item = live ?? demoUsage ?? offKitPet else { continue }
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.preview = item
            shots.append(Shot("closed-\(snapshotName(kind))", model))
            // The pet's other looks: typing through a focus block, sipping
            // coffee on a break, and dozing after a quiet spell.
            if case .pet(var pet) = item {
                let looks = [(PetMood.studying, "studying"), (.onBreak, "break"), (.asleep, "asleep")]
                for (mood, name) in looks where mood != pet.mood {
                    pet.mood = mood
                    let model = NotchViewModel(geometry: geometry, layout: layout)
                    model.preview = .pet(pet)
                    shots.append(Shot("closed-pet-\(name)", model))
                }
                // A finished focus session: the pet hops among sparkles
                // (stamped mid-cheer when rendered, see renderNotchShots).
                let model = NotchViewModel(geometry: geometry, layout: layout)
                model.preview = .pet(TickerPet(profile: pet.profile, mood: .onBreak))
                shots.append(Shot("closed-pet-cheer", model))
                // A goal reached: the pet hops in a tiny crown.
                let crowned = NotchViewModel(geometry: geometry, layout: layout)
                crowned.preview = .pet(TickerPet(profile: pet.profile, mood: .awake))
                shots.append(Shot("closed-pet-crown", crowned))
                // The Mac started charging: the pet sips from its mug.
                let sipping = NotchViewModel(geometry: geometry, layout: layout)
                sipping.preview = .pet(TickerPet(profile: pet.profile, mood: .onBreak))
                shots.append(Shot("closed-pet-charging", sipping))
            }
        }
        // The closed timer's ring part-way through a Pomodoro and a break,
        // whether or not a clock runs when the shots are taken.
        let rings = [
            ("closed-focus-ring", TickerFocus(phase: .focus, time: 15 * 60, isRunning: true, length: 25 * 60)),
            ("closed-focus-ring-break", TickerFocus(phase: .rest, time: 60, isRunning: false, length: 5 * 60)),
        ]
        for (name, focus) in rings {
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.preview = .focus(focus)
            shots.append(Shot(name, model))
        }
        // The "leave now" glow on a call about to start, with its Join button.
        let call = MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/1")!)
        let nudge = NotchViewModel(geometry: geometry, layout: layout)
        nudge.preview = .meeting(TickerMeeting(title: "Standup", timing: .startsIn(minutes: 4), canJoin: true,
                                               link: call, isNudging: true))
        shots.append(Shot("closed-meeting-nudge", nudge))
        // One open shot per tab of the active kit.
        for module in layout.enabled {
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.open(module)
            shots.append(Shot("open-\(module.rawValue)", model))
        }
        // And one per tab the kit leaves off (e.g. Focus), as if turned on,
        // so every module's panel can be reviewed under any kit.
        for module in layout.order where !layout.isEnabled(module) {
            var withModule = layout
            _ = withModule.setEnabled(module, true)
            let model = NotchViewModel(geometry: geometry, layout: withModule)
            model.open(module)
            shots.append(Shot("open-\(module.rawValue)", model))
        }

        // Every tab again at the other panel sizes, so each one can be
        // reviewed in the narrower Compact canvas and the roomier Large one.
        for size in PanelSize.allCases where size != .default {
            for module in layout.order {
                var withModule = layout
                _ = withModule.setEnabled(module, true)
                let model = NotchViewModel(geometry: geometry, layout: withModule)
                model.panelSize = size
                model.open(module)
                shots.append(Shot("open-\(size.rawValue)-\(module.rawValue)", model))
            }
        }

        // The Timer in a party's shared session and the team's celebration
        // when one ends, rendered after the others because both are store
        // state. Both show as if Party were on, which no bundled kit does.
        for (module, name) in [(ModuleID.study, "open-study-party"), (.party, "open-party-celebrating")]
        where layout.order.contains(module) {
            var withModule = layout
            _ = withModule.setEnabled(module, true)
            let model = NotchViewModel(geometry: geometry, layout: withModule)
            model.open(module)
            shots.append(Shot(name, model))
        }

        // The Closet's other sections, rendered after the others because
        // the open section is store state.
        if layout.order.contains(.closet) {
            var withCloset = layout
            _ = withCloset.setEnabled(.closet, true)
            let wardrobe = NotchViewModel(geometry: geometry, layout: withCloset)
            wardrobe.open(.closet)
            shots.append(Shot("open-closet-wardrobe", wardrobe))
            let model = NotchViewModel(geometry: geometry, layout: withCloset)
            model.open(.closet)
            shots.append(Shot("open-closet-look", model))
            let limited = NotchViewModel(geometry: geometry, layout: withCloset)
            limited.open(.closet)
            shots.append(Shot("open-closet-limited", limited))
            let streak = NotchViewModel(geometry: geometry, layout: withCloset)
            streak.open(.closet)
            shots.append(Shot("open-closet-streak", streak))
            let weeks = NotchViewModel(geometry: geometry, layout: withCloset)
            weeks.open(.closet)
            shots.append(Shot("open-closet-weeks", weeks))
            // An animated item (the flapping angel wings) on the big pet.
            let animated = NotchViewModel(geometry: geometry, layout: withCloset)
            animated.open(.closet)
            shots.append(Shot("open-closet-animated", animated))
            // The pet's paw at the far right of the header while another tab is open.
            let withPaw = NotchViewModel(geometry: geometry, layout: withCloset)
            withPaw.open(withCloset.tabs.first)
            shots.append(Shot("open-pet-shortcut", withPaw))
        }

        // Ask AI's chat history, rendered after the others because the
        // list showing is session state.
        if layout.order.contains(.claudeAsk) {
            var withAsk = layout
            _ = withAsk.setEnabled(.claudeAsk, true)
            let model = NotchViewModel(geometry: geometry, layout: withAsk)
            model.open(.claudeAsk)
            shots.append(Shot("open-claudeAsk-history", model))
            // The large chat view the tab can grow into.
            let large = NotchViewModel(geometry: geometry, layout: withAsk)
            large.open(.claudeAsk)
            large.requestOpenSize(ClaudeAskPanel.largeSize)
            shots.append(Shot("open-claudeAsk-large", large))
            // A screenshot waiting to be sent, one sent with an answered
            // question, and the Screen Recording priming screen shown
            // before the system is asked.
            for name in ["open-claudeAsk-screenshot", "open-claudeAsk-screenshot-sent", "open-claudeAsk-screen-access"] {
                let model = NotchViewModel(geometry: geometry, layout: withAsk)
                model.open(.claudeAsk)
                shots.append(Shot(name, model))
            }
        }

        // Today stepped back to yesterday and ahead to tomorrow, rendered
        // after the others because the day shown is store state.
        if layout.order.contains(.planner) {
            var withToday = layout
            _ = withToday.setEnabled(.planner, true)
            for name in ["open-planner-yesterday", "open-planner-tomorrow", "open-planner-tomorrow-plan"] {
                let model = NotchViewModel(geometry: geometry, layout: withToday)
                model.open(.planner)
                shots.append(Shot(name, model))
            }
        }

        // Now Playing following SoundCloud in Safari, playing and with
        // JavaScript from Apple Events turned off, rendered after the others
        // because the player shown is store state.
        #if !APPSTORE
        if layout.order.contains(.spotify) {
            var withNowPlaying = layout
            _ = withNowPlaying.setEnabled(.spotify, true)
            for name in ["open-spotify-soundcloud", "open-spotify-soundcloud-javascript-off"] {
                let model = NotchViewModel(geometry: geometry, layout: withNowPlaying)
                model.open(.spotify)
                shots.append(Shot(name, model))
            }
        }
        #endif

        // Schedule's Day view stepped back to yesterday and ahead to tomorrow,
        // with a plan for tomorrow on offer.
        if layout.order.contains(.schedule) {
            var withSchedule = layout
            _ = withSchedule.setEnabled(.schedule, true)
            for name in ["open-schedule-yesterday", "open-schedule-tomorrow", "open-schedule-tomorrow-plan"] {
                let model = NotchViewModel(geometry: geometry, layout: withSchedule)
                model.open(.schedule)
                shots.append(Shot(name, model))
            }
        }

        shots += headerShots(geometry: geometry, catalog: services.settings.catalog)

        // First-run setup in the notch, one shot per step of the active kit.
        shots += onboardingShots(services: services, geometry: geometry, layout: layout)
        shots += recapShots(geometry: geometry, layout: layout)

        // What a Party invite link opens, one shot per step worth seeing.
        if services.modules.module(PartyModule.self) != nil {
            shots += inviteShots(geometry: geometry, layout: layout)
        }

        for (theme, folder) in themeFolders {
            Theme.apply(theme)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            renderNotchShots(shots, services: services, closet: closet, style: notchStyle, to: folder)
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

        // The weekly recap's exported images, each shape in a heavy and a light week.
        let recapArchive = RecapArchive.demo(now: Date())
        if let heavy = recapArchive.recaps.first,
           let light = recapArchive.recaps.min(by: { $0.focusMinutes < $1.focusMinutes }) {
            for format in RecapShareFormat.allCases {
                for (name, recap) in [("heavy", heavy), ("light", light)] {
                    let image = RecapShareImage(recap: recap, cheer: recapArchive.cheer(for: recap),
                                                pet: closet?.store.profile, format: format)
                    guard let png = image.png() else { continue }
                    let url = outputDirectory.appendingPathComponent("recap-share-\(format.rawValue)-\(name).png")
                    try? png.write(to: url)
                    print(url.path)
                }
            }
        }

        // Frame strips of the shared motion (celebrations), reviewed frame by frame.
        for (name, view) in MotionSnapshots.shots() {
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

        // Every costume on every body shape, and every pet animation frame by frame.
        for (name, gallery) in [("pets-costumes", PetGallery.costumes()), ("pets-animations", PetGallery.animations())] {
            guard let png = gallery.png(scale: 2) else { continue }
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }

        let settingsWindow = SettingsWindowController(settings: services.settings, modules: services.modules,
                                                      onboarding: services.onboarding, account: services.accountSync,
                                                      ai: services.ai)
        for pane in settingsWindow.paneIDs {
            guard let png = await settingsWindow.snapshot(of: pane) else { continue }
            let url = outputDirectory.appendingPathComponent("settings-\(pane).png")
            try? png.write(to: url)
            print(url.path)
        }
        // General with the notch hidden, whose caption shows the way back.
        let notchMode = services.settings.settings.notchMode
        services.settings.settings.notchMode = .hidden
        if let png = await settingsWindow.snapshot(of: AppSettingsPane.general.rawValue) {
            let url = outputDirectory.appendingPathComponent("settings-general-notch-hidden.png")
            try? png.write(to: url)
            print(url.path)
        }
        services.settings.settings.notchMode = notchMode
        // General's privacy switches, under More options, with screen sharing hidden.
        let privacy = (services.settings.settings.hideFromScreenCapture, services.settings.settings.hideInMissionControl)
        services.settings.settings.hideFromScreenCapture = true
        if let png = await sheetSnapshot(Form { PrivacySection() }.formStyle(.grouped)
            .frame(width: paneWidth).environmentObject(services.settings)) {
            let url = outputDirectory.appendingPathComponent("settings-general-privacy.png")
            try? png.write(to: url)
            print(url.path)
        }
        (services.settings.settings.hideFromScreenCapture, services.settings.settings.hideInMissionControl) = privacy
        // General's feedback options, under More options, with the Fast pace picked.
        let pace = services.settings.settings.motionPace
        services.settings.settings.motionPace = .fast
        if let png = await sheetSnapshot(Form { FeedbackSection() }.formStyle(.grouped)
            .frame(width: paneWidth).environmentObject(services.settings)) {
            let url = outputDirectory.appendingPathComponent("settings-general-feedback.png")
            try? png.write(to: url)
            print(url.path)
        }
        services.settings.settings.motionPace = pace
        // The age check before Sign in with Apple: asked, passed, too young.
        let tooYoung = Calendar.current.date(byAdding: .month, value: 18, to: Date()) ?? Date()
        for (name, status) in [("ask", PartyAgeCheck.Status.unanswered), ("ready", .passed),
                               ("too-young", .tooYoung(until: tooYoung))] {
            let sheet = AccountAgeSheet(status: status, answer: { _ in }, close: {}) {
                AppleSignInButton(account: services.accountSync)
            }
            if let png = await sheetSnapshot(sheet) {
                let url = outputDirectory.appendingPathComponent("settings-account-age-\(name).png")
                try? png.write(to: url)
                print(url.path)
            }
        }
        // The Account row once the age check passed in Party: the Apple
        // button with the Terms and Privacy Policy it agrees to.
        services.accountSync.answerAge(birthMonth: 1, year: 1990)
        if let png = await settingsWindow.snapshot(of: AppSettingsPane.general.rawValue) {
            let url = outputDirectory.appendingPathComponent("settings-general-account-ready.png")
            try? png.write(to: url)
            print(url.path)
        }
        // Connections with an API provider waiting for its key, a command
        // line tool and Ollama picked, as far as this build offers them.
        let aiShots = [("api-key", AIProviderID.gemini), ("cli", .claudeCLI), ("local", .ollama)]
        for (name, provider) in aiShots where services.ai.availableProviders.contains(provider) {
            services.settings.settings.ai.choose(provider)
            if let png = await settingsWindow.snapshot(of: AppSettingsPane.connections.rawValue) {
                let url = outputDirectory.appendingPathComponent("settings-connections-ai-\(name).png")
                try? png.write(to: url)
                print(url.path)
            }
        }
        services.settings.settings.ai.choose(nil)

        // Each enabled module's own settings, as the sheet Tabs opens them in.
        let moduleOptions = AppSettingsPane.moduleOptions(settings: services.settings, modules: services.modules,
                                                          onboarding: services.onboarding)
        var optionPanes: Set<String> = []
        for module in services.settings.settings.modules.enabled {
            guard let pane = moduleOptions(module), optionPanes.insert(pane.id).inserted else { continue }
            try? await Task.sleep(for: pane.settleTime)
            guard let png = await sheetSnapshot(ModuleOptionsSheet(pane: pane, done: {})) else { continue }
            let url = outputDirectory.appendingPathComponent("settings-tabs-\(pane.id).png")
            try? png.write(to: url)
            print(url.path)
        }

        let kitID = services.settings.settings.kitID
        // The same questions as the sheet Settings shows when switching kits.
        if let kit = services.settings.kits[kitID], !kit.onboarding.isEmpty,
           let png = await sheetSnapshot(KitQuestionsView(kit: kit, cancel: {}, start: { _ in })
               .environment(\.moduleCatalog, services.settings.catalog)
               .frame(width: 520)) {
            let url = outputDirectory.appendingPathComponent("settings-kit-questions.png")
            try? png.write(to: url)
            print(url.path)
        }
        await renderKitImportReview(services, to: outputDirectory)
        await renderConnectionSheets(to: outputDirectory)
        if let png = await CrashReportPrompt.snapshot(of: CrashReportPrompt.sample) {
            let url = outputDirectory.appendingPathComponent("crash-report-prompt.png")
            try? png.write(to: url)
            print(url.path)
        }
    }

    /// How the notch shots are drawn: pixels per point, and whether they sit
    /// on the grey stand-in desktop or on nothing (transparent pixels).
    struct NotchStyle {
        var scale: CGFloat = 2
        var transparent = false
    }

    /// One notch shot: its file name, the notch state, and the onboarding
    /// flow, weekly recap or Party invite showing in it, if any.
    private struct Shot {
        let name: String
        let model: NotchViewModel
        var onboarding: OnboardingFlow?
        var recap: (WeeklyRecap, RecapCheer)?
        /// The Party invite link's confirmation showing in it, if any.
        var invite: PartyInviteFlow?

        init(_ name: String, _ model: NotchViewModel, onboarding: OnboardingFlow? = nil,
             recap: (WeeklyRecap, RecapCheer)? = nil, invite: PartyInviteFlow? = nil) {
            self.name = name
            self.model = model
            self.onboarding = onboarding
            self.recap = recap
            self.invite = invite
        }
    }

    /// The weekly recap card in a heavy week (the demo's best yet) and a
    /// light one, at every panel size.
    private static func recapShots(geometry: NotchGeometry, layout: ModuleLayout) -> [Shot] {
        let archive = RecapArchive.demo(now: Date())
        guard let heavy = archive.recaps.first,
              let light = archive.recaps.min(by: { $0.focusMinutes < $1.focusMinutes }) else { return [] }
        var shots: [Shot] = []
        for size in PanelSize.allCases {
            let prefix = size == .default ? "open-recap" : "open-recap-\(size.rawValue)"
            for (name, recap) in [("heavy", heavy), ("light", light)] {
                let model = NotchViewModel(geometry: geometry, layout: layout)
                model.panelSize = size
                model.showsTakeover = true
                shots.append(Shot("\(prefix)-\(name)", model, recap: (recap, archive.cheer(for: recap))))
            }
        }
        return shots
    }

    /// Walks onboarding from the name and kit steps through the active kit's
    /// questions, the tab step, every setup step its tabs need and the extras.
    private static func onboardingShots(services: AppServices, geometry: NotchGeometry, layout: ModuleLayout) -> [Shot] {
        let settings = services.settings
        guard let kit = settings.activeKit else { return [] }
        var flow = OnboardingFlow(catalog: settings.catalog, layout: layout, kit: kit, asksName: true,
                                  extras: OnboardingExtra.all)
        var shots: [Shot] = []
        var questions = 0
        while flow.stage != .finished {
            let name: String = switch flow.stage {
            case .name: "onboarding-name"
            case .kit: "onboarding-kit"
            case .question:
                { questions += 1; return "onboarding-question-\(questions)" }()
            case .modules: "onboarding-modules"
            case .setup(let id): "onboarding-setup-\(id)"
            case .extras: "onboarding-extras"
            case .finished: ""
            }
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.showsTakeover = true
            shots.append(Shot(name, model, onboarding: flow))
            if flow.stage == .kit { flow.choose(kit) } else { flow.next() }
        }
        return shots
    }

    /// A friend link asking to turn Party on, then to add the friend, then
    /// added; a party link asking to join; and an expired friend link.
    private static func inviteShots(geometry: NotchGeometry, layout: ModuleLayout) -> [Shot] {
        let now = Date()
        let invitee = PartyProfile.demoInvitee
        let add = PartyInvite.addFriend(code: invitee.code)
        var confirming = PartyInviteFlow(invite: add, partyIsOn: true)
        confirming.update(with: PartyState.demo(.lobby, now: now), blocked: [])
        var added = confirming
        _ = added.begin()
        added.didAddFriend(invitee, added: true)
        var expired = confirming
        _ = expired.begin()
        expired.didFail(.unknownCode)
        var join = PartyInviteFlow(invite: .joinParty(code: "ZX7M2P"), partyIsOn: true)
        join.update(with: PartyState.demo(now: now), blocked: [])
        let flows: [(String, PartyInviteFlow)] = [
            ("party-invite-turn-on", PartyInviteFlow(invite: add, partyIsOn: false)),
            ("party-invite-add", confirming),
            ("party-invite-added", added),
            ("party-invite-join", join),
            ("party-invite-expired", expired),
        ]
        return flows.map { name, flow in
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.showsTakeover = true
            return Shot(name, model, invite: flow)
        }
    }

    /// Renders each notch shot in the active theme into `folder`.
    private static func renderNotchShots(_ shots: [Shot], services: AppServices,
                                         closet: ClosetModule?, style: NotchStyle, to folder: URL) {
        let firstSection = closet?.store.section
        let askClaude = services.modules.module(AskClaudeModule.self)?.session
        let timer = services.modules.module(StudyModule.self)
        let today = services.modules.module(TodayModule.self)?.store
        let party = services.modules.module(PartyModule.self)?.store
        let schedule = services.modules.module(ScheduleModule.self)
        let nowPlaying = services.modules.module(NowPlayingModule.self)
        let now = Date()
        let partySession = PartyState.demo(.member, now: now).session(at: now)
        for shot in shots {
            let (name, model) = (shot.name, shot.model)
            services.onboarding.show(shot.onboarding)
            askClaude?.isShowingHistory = name == "open-claudeAsk-history"
            askClaude?.showForSnapshot(name == "open-claudeAsk-screenshot" ? .pendingScreenshot
                : name == "open-claudeAsk-screenshot-sent" ? .sentScreenshot
                : name == "open-claudeAsk-screen-access" ? .screenAccess : .chat)
            timer?.showForSnapshot(partySession: name == "open-study-party" ? partySession : nil)
            party?.showCelebrationForSnapshot(name == "open-party-celebrating")
            party?.showInviteForSnapshot(shot.invite)
            today?.showForSnapshot(name == "open-planner-yesterday" ? .yesterday
                : name.hasPrefix("open-planner-tomorrow") ? .tomorrow : .today,
                planning: name == "open-planner-tomorrow-plan")
            schedule?.showForSnapshot(name == "open-schedule-yesterday" ? .yesterday
                : name.hasPrefix("open-schedule-tomorrow") ? .tomorrow : .today,
                planning: name == "open-schedule-tomorrow-plan")
            nowPlaying?.showForSnapshot(name == "open-spotify-soundcloud" ? .soundCloud
                : name == "open-spotify-soundcloud-javascript-off" ? .soundCloudJavaScriptOff : .players)
            if let firstSection {
                closet?.store.section = name == "open-closet-wardrobe" ? .wardrobe
                    : name == "open-closet-look" ? .look
                    : name == "open-closet-limited" ? .limited
                    : name == "open-closet-streak" ? .streak : name == "open-closet-weeks" ? .weeks : firstSection
            }
            closet?.store.tryOn(name == "open-closet-animated" ? .accessory(.angelWings) : nil)
            model.themeID = Theme.current.id
            if name == "closed-pet-cheer", case .pet(var pet) = model.preview {
                // Mid first hop, with the sparkles out.
                pet.cheer = PetCheer(kind: .dance, id: 1, startedAt: Date().addingTimeInterval(-0.45))
                model.preview = .pet(pet)
            }
            if name == "closed-pet-crown", case .pet(var pet) = model.preview {
                // Mid hop, crowned as `TickerSources.cheering` does it.
                pet.cheer = PetCheer(kind: .crown, id: 1, startedAt: Date().addingTimeInterval(-0.45))
                pet.profile.wear(.tinyCrown)
                model.preview = .pet(pet)
            }
            if name == "closed-pet-charging", case .pet(var pet) = model.preview {
                // Past the hop, with the mug raised for the sip.
                pet.cheer = PetCheer(kind: .sip, id: 1, startedAt: Date().addingTimeInterval(-3.5))
                model.preview = .pet(pet)
            }
            var content = ModuleViews.notchContent(services: services)
            if let (recap, cheer) = shot.recap {
                content.takeover = RecapViews.takeover(recap: recap, cheer: cheer, providers: services.providers,
                                                       done: {})
            }
            let view = NotchView(content: content)
                .environmentObject(model)
                .environment(\.drawsLiquidGlass, false)
                .environment(\.loaderRevealDelay, 0) // rendered the moment it appears
                .frame(width: model.openSize.width + 40,
                       height: model.openSize.height + 24, alignment: .top)
                .background(style.transparent ? Color.clear : Color(white: 0.16)) // stand-in for a desktop
            let renderer = ImageRenderer(content: view)
            renderer.scale = style.scale
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            let url = folder.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }
        services.onboarding.show(nil)
        timer?.showForSnapshot(partySession: nil)
        party?.showCelebrationForSnapshot(false)
        party?.showInviteForSnapshot(nil)
        today?.show(.today)
        schedule?.showForSnapshot(.today)
        nowPlaying?.showForSnapshot(.players)
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

    /// The open header at growing tab counts, with the pet's paw, to check
    /// that no tab reaches under the camera; past what fits, the last tabs
    /// move behind "more", shown once more with its list open at every tab
    /// the catalog has (nine today; `NotchHeaderLayoutTests` covers up to twelve).
    private static func headerShots(geometry: NotchGeometry, catalog: ModuleCatalog) -> [Shot] {
        let tabModules = catalog.ids.filter { catalog.descriptor(for: $0).headerShortcut == nil }
        var shots: [Shot] = []
        for count in Set([4, 5, 7, tabModules.count]).sorted() where count <= tabModules.count {
            let on = Set(tabModules.prefix(count)).union([.closet])
            let layout = ModuleLayout(order: catalog.ids, disabled: Set(catalog.ids).subtracting(on), catalog: catalog)
            let model = NotchViewModel(geometry: geometry, layout: layout)
            model.open(layout.tabs.first)
            shots.append(Shot("open-header-\(count)-tabs", model))
            if count == tabModules.count {
                let menu = NotchViewModel(geometry: geometry, layout: layout)
                menu.open(layout.tabs.last)
                menu.showsMoreTabs = true
                shots.append(Shot("open-header-\(count)-tabs-more", menu))
            }
        }
        return shots
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
