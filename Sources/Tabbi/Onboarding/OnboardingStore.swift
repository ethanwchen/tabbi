import Combine
import Foundation
import TabbiKitCore

/// Runs first-run onboarding inside the notch: holds the `OnboardingFlow`
/// while it runs and applies what the user picked to `SettingsStore`.
///
/// The kit and tabs are applied as soon as the flow leaves the tab step, so
/// the setup steps after it (naming the pet, say) build on the picked kit
/// rather than being replaced by its defaults at the end.
@MainActor
final class OnboardingStore: ObservableObject {
    /// The running flow; nil while onboarding is not showing.
    @Published private(set) var flow: OnboardingFlow?

    let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isActive: Bool { flow != nil }

    /// Starts the flow from the current tabs and kit, so re-running it from
    /// Settings begins where the user is now. It opens on the name step on
    /// the first run, and on a re-run only while no name is set.
    func start() {
        let current = settings.settings
        flow = OnboardingFlow(catalog: settings.catalog, layout: current.modules, kit: settings.activeKit,
                              answers: current.hasChosenKit ? current.kitAnswers : [:],
                              asksName: !current.hasChosenKit || current.cleanedDisplayName == nil,
                              extras: OnboardingExtra.all)
    }

    /// Shows `flow` as it is, without applying anything; for snapshots.
    func show(_ flow: OnboardingFlow?) {
        self.flow = flow
    }

    /// Changes the flow (a pick, a toggle, Next or Back) and applies the
    /// choices once it reaches a setup step or the end.
    func update(_ change: (inout OnboardingFlow) -> Void) {
        guard var next = flow else { return }
        let before = next.stage
        change(&next)
        if next.stage.appliesChoices, !before.appliesChoices {
            apply(next)
        }
        flow = next.stage == .finished ? nil : next
    }

    /// Ends onboarding with what has been picked so far.
    func finish() {
        update { $0.finish() }
    }

    /// Records the kit, its answers and the tabs. The first run always
    /// records a kit (the preselected one after Start from Scratch), so
    /// onboarding does not come back; a re-run switches kits only when the
    /// pick changed, so going back and forth never adds starter tasks twice.
    private func apply(_ flow: OnboardingFlow) {
        let current = settings.settings
        if !current.hasChosenKit {
            settings.chooseKit(flow.kit?.id ?? current.kitID, answers: flow.kit == nil ? [:] : flow.answers)
        } else if let kit = flow.kit, kit.id != current.kitID || flow.answers != current.kitAnswers {
            settings.switchKit(to: kit.id, answers: flow.answers)
        }
        settings.settings.modules = flow.layout
    }
}

private extension OnboardingFlow.Stage {
    /// Past the kit, questions and tabs: what was picked should be in place.
    var appliesChoices: Bool {
        switch self {
        case .setup, .extras, .finished: true
        case .name, .kit, .question, .modules: false
        }
    }
}
