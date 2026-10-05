import SwiftUI
import TabbiKitCore
import TabbiKit

/// First-run onboarding as a `NotchTakeover`: the step's title left of the
/// hardware notch, progress and Skip Setup right of it, and the step itself
/// in the panel canvas.
enum OnboardingViews {
    @MainActor
    static func takeover(store: OnboardingStore, modules: ModuleRegistry) -> NotchTakeover {
        NotchTakeover(
            leading: { AnyView(OnboardingTitle().environmentObject(store)) },
            trailing: { AnyView(OnboardingProgress().environmentObject(store)) },
            body: { AnyView(OnboardingBody(modules: modules).environmentObject(store)) }
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
        case .kit, .finished: ("sparkles", "Welcome to \(Edition.current.name)")
        case .question: (flow.kit?.symbol ?? "sparkles", "Set up \(flow.kit?.name ?? "your kit")")
        case .modules: ("square.grid.2x2.fill", "Your tabs")
        case .setup: (flow.currentSetupStep?.symbol ?? "gearshape.fill", flow.currentSetupStep?.title ?? "Setup")
        }
    }
}

/// One dot per step (the current one long), then Skip Setup.
private struct OnboardingProgress: View {
    @EnvironmentObject private var store: OnboardingStore
    @State private var hovering = false

    var body: some View {
        if let flow = store.flow {
            HStack(spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(flow.stages.enumerated()), id: \.offset) { index, _ in
                        Capsule()
                            .fill(index <= flow.stageIndex ? Theme.Palette.primaryText : Theme.Palette.tertiaryText.opacity(0.5))
                            .frame(width: index == flow.stageIndex ? 12 : 5, height: 5)
                    }
                }
                .help("Step \(flow.stageIndex + 1) of \(flow.stages.count)")
                Button { store.finish() } label: {
                    Text("Skip Setup")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("Start using \(Edition.current.name) with what you picked so far. Settings can run setup again.")
            }
            .motion(Theme.Motion.snappy, value: flow.stageIndex)
        }
    }
}

/// The current step above a footer with Back and Skip or Continue.
private struct OnboardingBody: View {
    @EnvironmentObject private var store: OnboardingStore
    let modules: ModuleRegistry

    var body: some View {
        if let flow = store.flow {
            let setup = setupView(flow)
            VStack(spacing: Theme.Spacing.m) {
                step(flow, setup: setup)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(flow.stage)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
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
        case .modules: true
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
        case .kit, .finished: "Keep the \(flow.kit?.name ?? "suggested") kit"
        case .question: "Leave this question unanswered"
        case .modules: isLastStep ? "Start with these tabs" : "Keep these tabs and set up what they need"
        case .setup: hasSetupView ? (isLastStep ? "Finish setup" : "Keep this and go on") : "Set this up later from its tab"
        }
    }

    private var hint: String {
        switch flow.stage {
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
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(Theme.Spacing.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    @State private var gridWidth: CGFloat = 0

    private static let columns = 5
    private static let tileHeight: CGFloat = 52
    private static let space = "onboardingTiles"

    var body: some View {
        // A plain grid, not a lazy one: ten tiles at most, and snapshots
        // can draw it. Dragging is a SwiftUI gesture for the same reason.
        let order = flow.layout.order
        let rows = stride(from: 0, to: order.count, by: Self.columns).map {
            Array(order[$0..<min($0 + Self.columns, order.count)])
        }
        Grid(horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.s) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row) { id in
                        tile(id)
                            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
                                .onChanged { drag(id, to: $0.location) }
                                .onEnded { _ in dragging = nil })
                    }
                    ForEach(row.count..<Self.columns, id: \.self) { _ in Color.clear.frame(height: 1) }
                }
            }
        }
        .coordinateSpace(name: Self.space)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { gridWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { gridWidth = $1 }
        })
        .motion(Theme.Motion.snappy, value: flow.layout)
    }

    /// Moves the dragged tile into the slot under the pointer, live.
    private func drag(_ id: ModuleID, to location: CGPoint) {
        dragging = id
        let order = flow.layout.order
        let spacing = Theme.Spacing.s
        let columnWidth = (gridWidth - spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        guard columnWidth > 0, let from = order.firstIndex(of: id) else { return }
        let column = min(max(Int(location.x / (columnWidth + spacing)), 0), Self.columns - 1)
        let row = max(Int(location.y / (Self.tileHeight + spacing)), 0)
        let to = min(row * Self.columns + column, order.count - 1)
        guard to != from else { return }
        store.update { $0.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }

    private func tile(_ id: ModuleID) -> some View {
        let module = flow.catalog.descriptor(for: id)
        let isOn = flow.layout.isEnabled(id)
        let canTurnOff = flow.layout.canDisable(id)
        return OnboardingTile(isSelected: isOn, tint: module.accentColor.opacity(0.7),
                              help: isOn ? (canTurnOff ? "Turn \(module.title) off" : "Keep at least one tab on")
                                         : "Turn \(module.title) on",
                              action: { store.update { $0.setEnabled(id, !isOn) } }) {
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Image(systemName: module.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? module.accentColor : Theme.Palette.tertiaryText)
                        .frame(height: 16)
                    Text(module.title)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(isOn ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if let shortcut = flow.layout.shortcut(for: id).map(String.init) ?? flow.layout.headerKey(for: id)?.uppercased() {
                    Text(shortcut)
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
        }
        .frame(height: Self.tileHeight)
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
