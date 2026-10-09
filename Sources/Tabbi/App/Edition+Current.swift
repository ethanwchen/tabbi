import Foundation
import TabbiKitCore

extension Edition {
    /// The edition this process runs as: `--edition <id>` (for snapshots and
    /// `swift run`) wins, then the bundle's Info.plist, then Tabbi (the
    /// App Store edition in an App Store build).
    /// Resolved once at first use, so it is safe to read from any thread.
    static let current: Edition = {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--edition"), arguments.indices.contains(flag + 1),
           let edition = Edition.named(arguments[flag + 1]) {
            return edition
        }
        #if APPSTORE
        // An App Store build is the App Store edition even under `swift run`.
        let fallback = Edition.named("appstore") ?? .tabbi
        #else
        let fallback = Edition.tabbi
        #endif
        return Edition.resolve(infoDictionary: Bundle.main.infoDictionary, fallback: fallback)
    }()
}
