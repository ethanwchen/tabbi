import Foundation

/// The steps of first-run onboarding inside the notch, as plain state so the
/// order and the skipping rules are testable without a window.
///
/// The user says what to call them (on the first run), picks a kit (or
/// starts from scratch), answers the kit's own questions, turns tabs on or
/// off and reorders them, and then sees only the
/// setup steps the enabled modules declare (`ModuleDescriptor.setup`), each
/// asked once, and then, when any apply, one screen of optional extras
/// (`OnboardingExtra`). Every step can be skipped and `finish()` ends the flow from
/// anywhere, so onboarding never stands between the user and the notch.
/// Settings starts the same flow again to re-run it.
public struct OnboardingFlow: Equatable, Sendable {
    /// Where the flow is.
    public enum Stage: Hashable, Sendable {
        /// Say what to call the user; the caller saves the name as it is typed.
        case name
        /// Pick a kit or start from scratch.
        case kit
        /// One of the chosen kit's onboarding questions, by id.
        case question(String)
        /// Turn tabs on or off and reorder them.
        case modules
        /// A module's just-in-time setup step, by id.
        case setup(String)
        /// One screen that mentions the optional extras, last.
        case extras
        /// Done; the caller applies `kit`, `answers` and `layout`.
        case finished
    }

    public let catalog: ModuleCatalog
    public private(set) var stage: Stage
    /// The chosen kit; nil before the first step and after Start from Scratch.
    public private(set) var kit: KitManifest?
    /// The answers to the chosen kit's questions.
    public private(set) var answers: KitAnswers
    /// The tabs onboarding will turn on, in tab bar order.
    public private(set) var layout: ModuleLayout
    /// True once the user picked Start from Scratch on the kit step.
    public private(set) var startedFromScratch = false
    /// True when the flow opens on the name step.
    public let asksName: Bool
    /// The extras the last screen can mention; `currentExtras` keeps the
    /// ones whose tab is on.
    public let extras: [OnboardingExtra]

    /// - Parameters:
    ///   - layout: the tabs to start from (the current ones when re-running).
    ///   - kit: the kit to preselect, such as the edition's or the active one.
    ///   - answers: the answers to preselect when re-running with that kit.
    ///   - asksName: open on the name step before the kit step.
    ///   - extras: the optional extras to mention on the last screen.
    public init(catalog: ModuleCatalog, layout: ModuleLayout, kit: KitManifest? = nil, answers: KitAnswers = [:],
                asksName: Bool = false, extras: [OnboardingExtra] = []) {
        self.catalog = catalog
        self.layout = layout
        self.kit = kit
        self.answers = answers
        self.asksName = asksName
        self.extras = extras
        stage = asksName ? .name : .kit
    }

    /// Every stage the flow will go through for the current choices, from
    /// the name (or kit) step to the last setup step. It changes as the user picks a
    /// kit or switches tabs, so the progress dots always count what is left.
    public var stages: [Stage] {
        (asksName ? [.name] : []) + [.kit] + (kit?.onboarding.map { .question($0.id) } ?? []) + [.modules] + setupSteps.map { .setup($0.id) }
            + (currentExtras.isEmpty ? [] : [.extras])
    }

    /// The extras that apply to the tabs that are on: app-wide ones always,
    /// a tab's own only while that tab is on.
    public var currentExtras: [OnboardingExtra] {
        let enabled = Set(layout.enabled)
        return extras.filter { $0.module.map(enabled.contains) ?? true }
    }

    /// The setup steps the enabled tabs need: each step once, by rank, ties
    /// in tab order.
    public var setupSteps: [OnboardingSetupStep] {
        var seen = Set<OnboardingSetupStep>()
        let steps = layout.enabled.flatMap { catalog.descriptor(for: $0).setup }.filter { seen.insert($0).inserted }
        return steps.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element)
    }

    /// The question the flow is on, if it is on one.
    public var currentQuestion: KitQuestion? {
        guard case .question(let id) = stage else { return nil }
        return kit?.onboarding.first { $0.id == id }
    }

    /// The setup step the flow is on, if it is on one.
    public var currentSetupStep: OnboardingSetupStep? {
        guard case .setup(let id) = stage else { return nil }
        return setupSteps.first { $0.id == id }
    }

    /// The current stage's position in `stages` (0-based), for progress dots.
    public var stageIndex: Int {
        stage == .finished ? stages.count : stages.firstIndex(of: stage) ?? 0
    }

    public var canGoBack: Bool { stage != stages.first && stage != .finished }

    /// Picks `kit` and moves on. Picking a different kit than before starts
    /// over from its tabs and clears earlier answers; picking the same one
    /// again keeps what the user already changed. It answers the kit step,
    /// so the flow moves on from there even if it was on the name step.
    public mutating func choose(_ kit: KitManifest) {
        if kit != self.kit || startedFromScratch {
            self.kit = kit
            answers = [:]
            layout = kit.layout(catalog: catalog)
        }
        startedFromScratch = false
        stage = .kit
        next()
    }

    /// Skips the kits: the next step starts with only the first tab on, so
    /// the user builds the notch from there.
    public mutating func startFromScratch() {
        if !startedFromScratch {
            kit = nil
            answers = [:]
            let ids = catalog.ids
            layout = ModuleLayout(order: ids, disabled: Set(ids.dropFirst()), catalog: catalog)
        }
        startedFromScratch = true
        stage = .kit
        next()
    }

    /// Picks `answerID` for the current question; the kit's answers decide
    /// which tabs are on, so this replaces any tab changes made since. A
    /// single-choice question moves on once answered, so it takes one tap.
    public mutating func answer(_ answerID: String) {
        guard let kit, let question = currentQuestion else { return }
        let picked = question.selecting(answerID, in: answers[question.id] ?? [])
        answers[question.id] = picked
        layout = kit.layout(catalog: catalog, answers: answers)
        if !question.allowsMultiple, !picked.isEmpty { next() }
    }

    /// Turns a tab on or off; refuses to turn off the last one.
    @discardableResult
    public mutating func setEnabled(_ module: ModuleID, _ isEnabled: Bool) -> Bool {
        layout.setEnabled(module, isEnabled)
    }

    /// Reorders tabs, with SwiftUI `onMove` semantics over `layout.order`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.move(fromOffsets: source, toOffset: destination)
    }

    /// Moves on to the next stage, or finishes after the last one. Skipping
    /// a step is the same move: nothing a step asks for is required.
    public mutating func next() {
        let all = stages
        guard let index = all.firstIndex(of: stage), index + 1 < all.count else {
            stage = .finished
            return
        }
        stage = all[index + 1]
    }

    /// Goes back one stage; does nothing on the first one or once finished.
    public mutating func back() {
        guard canGoBack, let index = stages.firstIndex(of: stage), index > 0 else { return }
        stage = stages[index - 1]
    }

    /// Ends onboarding with what has been chosen so far.
    public mutating func finish() {
        stage = .finished
    }
}
