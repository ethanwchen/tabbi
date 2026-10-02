import Foundation

/// The user's onboarding answers: question id to the chosen answer ids.
public typealias KitAnswers = [String: Set<String>]

public extension KitManifest {
    /// The answers picked for `answers`, in question and option order, so
    /// later answers win when two disagree about a module.
    func chosenAnswers(_ answers: KitAnswers) -> [KitAnswer] {
        onboarding.flatMap { question in
            let picked = answers[question.id] ?? []
            let chosen = question.options.filter { picked.contains($0.id) }
            return question.allowsMultiple ? chosen : Array(chosen.prefix(1))
        }
    }

    /// The tab layout this kit produces: its modules in kit order, then every
    /// other module in `catalog` switched off (so Settings can still offer
    /// them). Onboarding answers then switch modules on or off. Modules
    /// `catalog` doesn't know are skipped.
    func layout(catalog: ModuleCatalog = .builtIn, answers: KitAnswers = [:]) -> ModuleLayout {
        let kitIDs = moduleIDs.filter(catalog.contains)
        let kitSet = Set(kitIDs)
        let order = kitIDs + catalog.ids.filter { !kitSet.contains($0) }
        var disabled = Set(catalog.ids.filter { !kitSet.contains($0) })
        for entry in modules where !entry.enabled {
            disabled.insert(entry.id)
        }
        for answer in chosenAnswers(answers) {
            disabled.subtract(answer.enables)
            disabled.formUnion(answer.disables)
        }
        return ModuleLayout(order: order, disabled: disabled, catalog: catalog)
    }

    /// The kit's starter tasks plus any the chosen answers add, without
    /// blanks or duplicates.
    func starterTasks(answers: KitAnswers = [:]) -> [String] {
        var seen = Set<String>()
        return (starterTasks + chosenAnswers(answers).flatMap(\.tasks))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
