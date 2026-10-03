import Foundation

/// What switching to a kit would change, so Settings can show an imported
/// kit's effect before it replaces the user's setup.
///
/// It compares the settings the kit produces for the user's onboarding
/// answers with the current ones: which tabs turn on or off, which
/// permissions the new tabs will ask for, the hosts off this Mac they
/// connect to, the starter tasks Today gets and
/// whether the closed-notch previews change.
public struct KitChangePreview: Equatable, Sendable {
    /// The tabs after the switch, in order.
    public var tabs: [ModuleID]
    /// Tabs that are off now and on after the switch, in their new order.
    public var turnsOn: [ModuleID]
    /// Tabs that are on now and off after the switch, in their old order.
    public var turnsOff: [ModuleID]
    /// Permissions the tabs that turn on need and no tab on now already
    /// needs, so the user knows which prompts to expect.
    public var newPermissions: [ModulePermission]
    /// Hosts off this Mac that the tabs turning on connect to and no tab on
    /// now already does, in tab order, so the user sees where data goes
    /// before switching. Local services (AnkiConnect) are left out.
    public var newNetworkAccess: [ModuleNetworkAccess]
    /// The starter tasks the switch adds to Today (Today skips titles it
    /// already lists).
    public var starterTasks: [String]
    /// True when the kit sets closed-notch previews that differ from the
    /// current ones.
    public var changesNotchPreviews: Bool

    public init(applying kit: KitManifest, answers: KitAnswers = [:], to current: AppSettings, catalog: ModuleCatalog) {
        var next = current
        next.apply(kit, answers: answers, catalog: catalog)
        let wasOn = Set(current.modules.enabled)
        let isOn = Set(next.modules.enabled)
        tabs = next.modules.enabled
        turnsOn = next.modules.enabled.filter { !wasOn.contains($0) }
        turnsOff = current.modules.enabled.filter { !isOn.contains($0) }
        let granted = Set(current.modules.enabled.flatMap { catalog[$0]?.permissions ?? [] })
        let needed = Set(turnsOn.flatMap { catalog[$0]?.permissions ?? [] })
        newPermissions = ModulePermission.allCases.filter { needed.contains($0) && !granted.contains($0) }
        let reached = Set(current.modules.enabled.flatMap { catalog[$0]?.network ?? [] }.map(\.host))
        var listed = Set<String>()
        newNetworkAccess = turnsOn.flatMap { catalog[$0]?.network ?? [] }.filter {
            !$0.isLocal && !reached.contains($0.host) && listed.insert($0.host).inserted
        }
        starterTasks = kit.starterTasks(answers: answers)
        changesNotchPreviews = next.notchPreview != current.notchPreview
    }

    /// True when switching changes neither tabs nor previews nor Today.
    public var isEmpty: Bool {
        turnsOn.isEmpty && turnsOff.isEmpty && starterTasks.isEmpty && !changesNotchPreviews
    }
}
