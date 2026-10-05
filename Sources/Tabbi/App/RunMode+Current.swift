import Foundation
import TabbiKitCore

extension RunMode {
    /// How this process runs, read once from its environment and arguments.
    /// Modules get it from `ModuleContext.runMode`; this is for the few
    /// app-wide views and singletons that no context reaches.
    static let current = RunMode(environment: ProcessInfo.processInfo.environment,
                                 arguments: CommandLine.arguments)
}
