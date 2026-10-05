import Foundation
import TabbiKitCore

extension Edition {
    /// The edition this process runs as: `--edition <id>` (for snapshots and
    /// `swift run`) wins, then the bundle's Info.plist, then Tabbi.
    /// Resolved once at first use, so it is safe to read from any thread.
    static let current: Edition = {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--edition"), arguments.indices.contains(flag + 1),
           let edition = Edition.named(arguments[flag + 1]) {
            return edition
        }
        return Edition.resolve(infoDictionary: Bundle.main.infoDictionary)
    }()
}
