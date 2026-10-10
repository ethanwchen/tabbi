import SwiftUI
import TabbiKitCore
import TabbiKit

/// First-run onboarding as a `NotchTakeover`: the step's title left of the
/// hardware notch, progress and Skip Setup right of it, and the step itself
/// in the panel canvas.
enum OnboardingViews {
    @MainActor
    static func takeover(store: OnboardingStore, modules: ModuleRegistry, providers: ProviderHub,
                         account: SyncStore?, openSettings: @escaping (String) -> Void) -> NotchTakeover {
        NotchTakeover(
            leading: { AnyView(OnboardingTitle().environmentObject(store)) },
            trailing: { AnyView(OnboardingProgress().environmentObject(store)) },
            body: {
                AnyView(ModuleViews.StatusPetProvider(providers: providers) {
                    OnboardingBody(modules: modules, account: account, openSettings: openSettings)
                        .environmentObject(store).environmentObject(store.settings)
                })
            }
        )
    }
}

/// The step's symbol and name.
private struct OnboardingTitle: View {
    @EnvironmentObject private var store: OnboardingStore

    var body: some View {
        if let flow = store.flow {
            let (symbol, title) = heading(flow)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.secondaryText)
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
            }
            .contentTransition(.opacity)
        }
    }

    private func heading(_ flow: OnboardingFlow) -> (String, String) {
        switch flow.stage {
        case .name: ("sparkles", "Welcome to \(Edition.current.name)")
        case .kit, .finished: flow.asksName ? ("square.stack.3d.up.fill", "Pick a kit")
                                            : ("sparkles", "Welcome to \(Edition.current.name)")
        case .question: (flow.kit?.symbol ?? "sparkles", "Set up \(flow.kit?.name ?? "your kit")")
        case .modules: ("square.grid.2x2.fill", "Your tabs")
        case .setup: (flow.currentSetupStep?.symbol ?? "gearshape.fill", flow.currentSetupStep?.title ?? "Setup")
        case .extras: ("gift.fill", "A few extras")
        }
    }
}

/// One dot per step (the current one long), then Skip Setup. A kit with
/// many steps narrows the dots, then drops them, so the label never wraps
/// inside the camera-safe zone.
private struct OnboardingProgress: View {
    @EnvironmentObject private var store: OnboardingStore
    @State private var hovering = false

    var body: some View {
        if let flow = store.flow {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.m) {
                    dots(flow, dot: 5, spacing: Theme.Spacing.xs)
                    skip
                }
                HStack(spacing: Theme.Spacing.s) {
                    dots(flow, dot: 4, spacing: 3)
                    skip
                }
                skip
            }
            .motion(Theme.Motion.snappy, value: flow.stageIndex)
        }
    }

    private func dots(_ flow: OnboardingFlow, dot: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(flow.stages.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index <= flow.stageIndex ? Theme.Palette.primaryText : Theme.Palette.tertiaryText.opacity(0.5))
                    .frame(width: index == flow.stageIndex ? 12 : dot, height: dot)
            }
        }
        .help("Step \(flow.stageIndex + 1) of \(flow.stages.count)")
        .accessibilityElement()
        .accessibilityLabel("Step \(flow.stageIndex + 1) of \(flow.stages.count)")
    }

    private var skip: some View {
        Button { store.finish() } label: {
            Text("Skip Setup")
                .font(Theme.Typography.caption)
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Start using \(Edition.current.name) with what you picked so far. Settings can run setup again.")
    }
}

/// The current step above a footer with Back and Skip or Continue.
private struct OnboardingBody: View {
    @EnvironmentObject private var store: OnboardingStore
    let modules: ModuleRegistry
    let account: SyncStore?
    let openSettings: (String) -> Void

    var body: some View {
        if let flow = store.flow {
            let setup = setupView(flow)
            VStack(spacing: Theme.Spacing.m) {
                step(flow, setup: setup)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(flow.stage)
                    .transition(AsymmetricTransition(insertion: .motionRow(from: .trailing),
                                                     removal: .opacity))
                OnboardingFooter(flow: flow, hasSetupView: setup != nil)
            }
            .motion(Theme.Motion.content, value: flow.stage)
        }
    }

    /// The current setup step as its module draws it, if one does.
    private func setupView(_ flow: OnboardingFlow) -> AnyView? {
        guard case .setup = flow.stage, let step = flow.currentSetupStep else { return nil }
        return modules.setupView(for: step, modules: flow.layout.enabled) { store.update { $0.next() } }
    }

    @ViewBuilder
    private func step(_ flow: OnboardingFlow, setup: AnyView?) -> some View {
        switch flow.stage {
        case .name:
            NameStep { store.update { $0.next() } }
        case .kit, .finished:
            KitStep(flow: flow)
        case .question:
            if let question = flow.currentQuestion { QuestionStep(flow: flow, question: question) }
        case .modules:
            ModulesStep(flow: flow)
        case .setup:
            if let setup {
                setup
            } else if let step = flow.currentSetupStep {
                SetupFallback(step: step, owner: owner(of: step, in: flow))
            }
        case .extras:
            ExtrasStep(extras: flow.currentExtras, catalog: flow.catalog, account: account,
                       signIn: { openSettings(AppSettingsPane.general.rawValue) })
        }
    }

    /// The first enabled tab that asked for `step`, named in the fallback.
    private func owner(of step: OnboardingSetupStep, in flow: OnboardingFlow) -> ModuleDescriptor? {
        flow.layout.enabled.map(flow.catalog.descriptor(for:)).first { $0.setup.contains(step) }
    }
}

/// Back on the left; Skip (or Continue where the step has no one-tap
/// answer) on the right.
private struct OnboardingFooter: View {
    @EnvironmentObject private var store: OnboardingStore
    @EnvironmentObject private var settings: SettingsStore
    let flow: OnboardingFlow
    /// True when the setup step is drawn by its module (and so has
    /// something to keep), false for the pointer-to-the-tab fallback.
    var hasSetupView = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if flow.canGoBack {
                FooterButton(title: "Back", symbol: "chevron.left", help: "Go back one step") {
                    store.update { $0.back() }
                }
            }
            Text(hint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: flow.canGoBack ? .center : .leading)
            FooterButton(title: forwardTitle, symbol: "chevron.right", isPrimary: forwardIsPrimary, help: forwardHelp) {
                store.update { $0.next() }
            }
        }
        .frame(height: 24)
    }

    private var isLastStep: Bool { flow.stageIndex == flow.stages.count - 1 }

    /// Steps without a one-tap answer say Continue; one-tap steps say Skip.
    private var forwardIsPrimary: Bool {
        switch flow.stage {
        case .modules, .extras: true
        case .name: settings.settings.cleanedDisplayName != nil
        case .question: flow.currentQuestion?.allowsMultiple == true
        case .setup: hasSetupView
        default: false
        }
    }

    private var forwardTitle: String {
        if isLastStep { return forwardIsPrimary ? "Done" : "Skip and Finish" }
        return forwardIsPrimary ? "Continue" : "Skip"
    }

    private var forwardHelp: String {
        switch flow.stage {
        case .name: forwardIsPrimary ? "Keep this name" : "Go on without a name"
        case .kit, .finished: "Keep the \(flow.kit?.name ?? "suggested") kit"
        case .question: "Leave this question unanswered"
        case .modules: isLastStep ? "Start with these tabs" : "Keep these tabs and set up what they need"
        case .setup: hasSetupView ? (isLastStep ? "Finish setup" : "Keep this and go on") : "Set this up later from its tab"
        case .extras: "Finish setup"
        }
    }

    private var hint: String {
        switch flow.stage {
        case .name: "You can change it any time in Settings > General."
        case .kit, .finished: "A kit is a set of tabs. You can change them any time."
        case .question: flow.currentQuestion?.allowsMultiple == true ? "Pick any that fit." : "One tap moves on."
        case .modules: "Click a tab to turn it on or off. Drag to reorder."
        case .setup:
            if hasSetupView, let step = flow.currentSetupStep,
               let owner = flow.layout.enabled.map(flow.catalog.descriptor(for:)).first(where: { $0.setup.contains(step) }) {
                "You can change this later in the \(owner.title) tab."
            } else {
                ""
            }
        case .extras: "All optional. Nothing to do now."
        }
    }
}

/// A small text button with a hover state, for the footer.
private struct FooterButton: View {
    let title: String
    let symbol: String
    var isPrimary = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if symbol == "chevron.left" { Image(systemName: symbol) }
                Text(title)
                if symbol != "chevron.left" { Image(systemName: symbol) }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(isPrimary || hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 24)
            .controlBackground(Capsule(), hovering: hovering,
                               tint: isPrimary ? Theme.Palette.primaryText.opacity(0.14) : nil)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// A selectable tile on the notch: a card that lights up on hover and
/// rings in `tint` when selected.
private struct OnboardingTile<Label: View>: View {
    var isSelected = false
    var tint: Color = Theme.Palette.primaryText
    /// Short tiles trim their top and bottom padding and center their label.
    var isCompact = false
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, isCompact ? Theme.Spacing.xs : Theme.Spacing.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompact ? .leading : .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .strokeBorder(isSelected ? tint : Theme.Palette.stroke, lineWidth: isSelected ? 1.5 : 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The name step: one field for what to call the user, saved to the
/// app-wide name as it is typed. Return moves on. The pet greets the user
/// beside it, so the first thing Tabbi shows is its cat, not a form.
private struct NameStep: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.statusPet) private var pet
    let submit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.l) {
                GreetingPet(profile: pet ?? .starter(.cat))
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("What should we call you?")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text("Friends see it in Party, and \(Edition.current.name) uses it to greet you.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                    }
                    field
                        .font(Theme.Typography.bodyEmphasis)
                        .padding(.horizontal, Theme.Spacing.s)
                        .frame(width: 220, height: 28, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                                .fill(Theme.Palette.surfaceHover)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                                .strokeBorder(focused ? Theme.Palette.secondaryText : Theme.Palette.stroke, lineWidth: 0.5)
                        )
                        .help("Your name, up to \(DisplayName.maxLength) characters")
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// `ImageRenderer` (used by `--snapshot`) can't draw a `TextField`, so
    /// snapshots get a static stand-in.
    @ViewBuilder private var field: some View {
        if RunMode.current.isSnapshot {
            let name = settings.settings.displayName
            Text(name.isEmpty ? "Your name" : name)
                .foregroundStyle(name.isEmpty ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
        } else {
            TextField("Your name", text: name, prompt: Text("Your name").foregroundStyle(Theme.Palette.tertiaryText))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.primaryText)
                .focused($focused)
                .onSubmit(submit)
                .onAppear { focused = true }
        }
    }

    /// Kept as typed, capped at the length every use allows, like the
    /// field in Settings > General.
    private var name: Binding<String> {
        Binding(
            get: { settings.settings.displayName },
            set: { settings.settings.displayName = String($0.prefix(DisplayName.maxLength)) }
        )
    }
}

/// The user's pet (the starter cat until they pick one), drawn large and
/// hopping hello once when the step appears.
private struct GreetingPet: View {
    let profile: PetProfile
    @StateObject private var player: PetPlayer

    /// Two points per sprite pixel: a 64 pt pet, crisp on every display.
    private static let pixelSize: CGFloat = 2

    init(profile: PetProfile) {
        self.profile = profile
        // A fixed seed keeps snapshots stable.
        _player = StateObject(wrappedValue: PetPlayer(profile: profile, seed: 7))
    }

    var body: some View {
        PetView(player: player, pixelSize: Self.pixelSize)
            .help("Hi! I'm \(profile.name).")
            .onAppear { if !RunMode.current.isSnapshot { player.send(.nudge) } }
            .onChange(of: profile) { _, profile in player.update(profile: profile) }
    }
}

/// Step 1: one card per kit with the tabs it turns on, and Start from Scratch.
private struct KitStep: View {
    @EnvironmentObject private var store: OnboardingStore
    let flow: OnboardingFlow

    var body: some View {
        let catalog = flow.catalog
        HStack(spacing: Theme.Spacing.s) {
            ForEach(store.settings.kits.kits) { kit in
                let tabs = kit.layout(catalog: catalog).enabled
                let tint = kit.accentModule(catalog: catalog).map { catalog.descriptor(for: $0).accentColor }
                    ?? Theme.Palette.primaryText
                OnboardingTile(isSelected: kit == flow.kit && !flow.startedFromScratch, tint: tint,
                               help: "\(kit.name): \(tabs.map { catalog.descriptor(for: $0).title }.joined(separator: ", "))",
                               action: { store.update { $0.choose(kit) } }) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Image(systemName: kit.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.background)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(tint))
                            .padding(.bottom, Theme.Spacing.xxs)
                        Text(kit.name)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .lineLimit(1)
                        Text(kit.summary)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        TabSymbols(modules: tabs, catalog: catalog)
                    }
                }
            }
            OnboardingTile(isSelected: flow.startedFromScratch,
                           help: "Start with one tab and turn on the ones you want",
                           action: { store.update { $0.startFromScratch() } }) {
                VStack(spacing: Theme.Spacing.s) {
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().strokeBorder(Theme.Palette.tertiaryText, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    Text("Start from Scratch")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 84)
        }
    }
}

/// A row of small tinted tab symbols.
private struct TabSymbols: View {
    let modules: [ModuleID]
    let catalog: ModuleCatalog

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(modules.map(catalog.descriptor(for:))) { module in
                Image(systemName: module.symbol)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(module.accentColor)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(module.accentColor.opacity(0.18)))
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// One of the kit's questions: a row of answer tiles, then the tabs the
/// answers turn on so far.
private struct QuestionStep: View {
    @EnvironmentObject private var store: OnboardingStore
    let flow: OnboardingFlow
    let question: KitQuestion

    var body: some View {
        let picked = flow.answers[question.id] ?? []
        let tint = flow.kit?.accentModule(catalog: flow.catalog).map { flow.catalog.descriptor(for: $0).accentColor }
            ?? Theme.Palette.primaryText
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(question.prompt)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(question.options) { option in
                    let isPicked = picked.contains(option.id)
                    OnboardingTile(isSelected: isPicked, tint: tint,
                                   help: isPicked && question.allowsMultiple ? "Clear \"\(option.label)\"" : option.label,
                                   action: { store.update { $0.answer(option.id) } }) {
                        VStack(spacing: Theme.Spacing.s) {
                            Image(systemName: option.symbol ?? "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isPicked ? tint : Theme.Palette.secondaryText)
                                .frame(height: 20)
                            Text(option.label)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.primaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 84)
            HStack(spacing: Theme.Spacing.s) {
                Text("Your tabs")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                TabSymbols(modules: flow.layout.enabled, catalog: flow.catalog)
            }
            .motion(Theme.Motion.snappy, value: flow.layout)
        }
    }
}

/// Every tab as a tile in tab bar order: click turns it on or off, drag
/// moves it. The number is the key that jumps to it.
private struct ModulesStep: View {
    @EnvironmentObject private var store: OnboardingStore
    let flow: OnboardingFlow
    @State private var dragging: ModuleID?

    /// The tallest a tile gets; shorter when more rows have to fit.
    private static let tileHeight: CGFloat = 52
    /// Below this height a tile trims its padding.
    private static let roomyTileHeight: CGFloat = 49
    /// Below this height a tile puts its symbol beside its title.
    private static let stackedTileHeight: CGFloat = 41
    private static let space = "onboardingTiles"
    private static let spacing = Theme.Spacing.s
    /// Five columns keep titles such as Claude Usage whole.
    private static let columns = 5

    private var rowCount: Int { max((flow.layout.order.count + Self.columns - 1) / Self.columns, 1) }

    /// Tiles share the step's height, so every row and the footer below
    /// stay inside the notch however many tabs there are.
    private func rowHeight(in size: CGSize) -> CGFloat {
        let fitted = (size.height - Self.spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
        return min(Self.tileHeight, fitted.rounded(.down))
    }

    var body: some View {
        // Sized during layout, not from a measured @State, so the first
        // frame (and a snapshot) already fits.
        GeometryReader { proxy in
            grid(size: proxy.size)
        }
    }

    private func grid(size: CGSize) -> some View {
        // A plain grid, not a lazy one: fifteen tiles at most, and snapshots
        // can draw it. Dragging is a SwiftUI gesture for the same reason.
        let rowHeight = rowHeight(in: size)
        let order = flow.layout.order
        let columns = Self.columns
        let rows = stride(from: 0, to: order.count, by: columns).map {
            Array(order[$0..<min($0 + columns, order.count)])
        }
        return Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row) { id in
                        tile(id, height: rowHeight)
                            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
                                .onChanged { drag(id, to: $0.location, in: size, rowHeight: rowHeight) }
                                .onEnded { _ in dragging = nil })
                    }
                    ForEach(row.count..<columns, id: \.self) { _ in Color.clear.frame(height: 1) }
                }
            }
        }
        .coordinateSpace(name: Self.space)
        .frame(width: size.width, height: size.height, alignment: .top)
        .motion(Theme.Motion.snappy, value: flow.layout)
    }

    /// Moves the dragged tile into the slot under the pointer, live.
    private func drag(_ id: ModuleID, to location: CGPoint, in size: CGSize, rowHeight: CGFloat) {
        dragging = id
        let order = flow.layout.order
        let columns = Self.columns
        let columnWidth = (size.width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        guard columnWidth > 0, let from = order.firstIndex(of: id) else { return }
        let column = min(max(Int(location.x / (columnWidth + Self.spacing)), 0), columns - 1)
        let row = max(Int(location.y / (rowHeight + Self.spacing)), 0)
        let to = min(row * columns + column, order.count - 1)
        guard to != from else { return }
        store.update { $0.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }

    private func tile(_ id: ModuleID, height rowHeight: CGFloat) -> some View {
        let module = flow.catalog.descriptor(for: id)
        let isOn = flow.layout.isEnabled(id)
        let canTurnOff = flow.layout.canDisable(id)
        let isStacked = rowHeight >= Self.stackedTileHeight
        return OnboardingTile(isSelected: isOn, tint: module.accentColor.opacity(0.7),
                              isCompact: rowHeight < Self.roomyTileHeight,
                              help: isOn ? (canTurnOff ? "Turn \(module.title) off" : "Keep at least one tab on")
                                         : "Turn \(module.title) on",
                              action: { store.update { $0.setEnabled(id, !isOn) } }) {
            let symbol = Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? module.accentColor : Theme.Palette.tertiaryText)
                .frame(height: 16)
            let title = Text(module.title)
                .font(Theme.Typography.caption)
                .foregroundStyle(isOn ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(10 / 10.5) // never below the 10pt floor
            let key = (flow.layout.shortcut(for: id).map(String.init) ?? flow.layout.headerKey(for: id)?.uppercased())
                .map { Text($0).font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.Palette.tertiaryText) }
            // The key sits beside the symbol, so the title gets the tile's
            // whole width.
            if isStacked {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) { symbol; Spacer(minLength: 0); key }
                    title
                }
            } else {
                HStack(spacing: Theme.Spacing.xs) { symbol; title; Spacer(minLength: 0); key }
            }
        }
        .frame(height: rowHeight)
        .scaleEffect(dragging == id ? 1.05 : 1)
        .opacity(dragging == id ? 0.8 : 1)
        .zIndex(dragging == id ? 1 : 0)
    }
}

/// A setup step whose module draws no view of its own: what it is for and
/// where to find it later.
private struct SetupFallback: View {
    let step: OnboardingSetupStep
    let owner: ModuleDescriptor?

    var body: some View {
        let tint = owner?.accentColor ?? Theme.Palette.primaryText
        Card {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: step.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(step.title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(owner.map { "You can set this up any time in the \($0.title) tab." }
                         ?? "You can set this up any time in Settings.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The last screen: each optional extra as a tile in one row, with a way
/// to sign in where an account is offered. Nothing here is required, so
/// the footer's Done ends setup whatever the user does.
private struct ExtrasStep: View {
    let extras: [OnboardingExtra]
    let catalog: ModuleCatalog
    let account: SyncStore?
    let signIn: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(extras) { extra in
                ExtraTile(extra: extra, tint: extra.module.map { catalog.descriptor(for: $0).accentColor },
                          account: extra == .sync ? account : nil, signIn: signIn)
            }
        }
    }
}

/// One extra: a tinted symbol, its title and its line, and for syncing a
/// Sign In button (or a check once signed in) beside the symbol. The
/// words sit at the bottom, like the kit tiles' tab symbols.
private struct ExtraTile: View {
    let extra: OnboardingExtra
    let tint: Color?
    let account: SyncStore?
    let signIn: () -> Void

    var body: some View {
        let tint = tint ?? Theme.Palette.secondaryText
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: extra.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let account { AccountBadge(account: account, signIn: signIn) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(extra.title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                Text(extra.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surfaceBackground(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        .help("\(extra.title): \(extra.detail)")
    }
}

/// Sign In while signed out (it opens Settings > General, where Apple's
/// button is); a check once the account syncs.
private struct AccountBadge: View {
    @ObservedObject var account: SyncStore
    let signIn: () -> Void
    @State private var hovering = false

    var body: some View {
        if account.isSignedIn {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.success)
                .help("Signed in. Your pet syncs across your Macs.")
                .accessibilityLabel("Signed in")
        } else {
            Button(action: signIn) {
                Text("Sign In")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .padding(.horizontal, Theme.Spacing.s)
                    .frame(height: 22)
                    .controlBackground(Capsule(), hovering: hovering)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Open Settings > General to sign in with Apple")
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
        }
    }
}
