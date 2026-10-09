import Foundation
import TabbiKitCore

/// What happens on launch with the report an earlier crash left: nothing,
/// the one-time prompt, or a quiet send when the person chose "always".
/// The prompt and the upload are injected, so tests can drive the opt-in
/// without a window or the network.
@MainActor
struct CrashReportFlow {
    /// The person's answer to the prompt.
    struct Answer: Equatable {
        var choice: CrashReportConsent.Choice
        var dontAskAgain: Bool
    }

    var consent: CrashReportConsentStore
    var ask: (CrashReport) -> Answer
    var send: (CrashReport) -> Void

    /// Offers `report`, if any, as the stored consent says, and keeps a
    /// "Don't ask again" answer as the new consent.
    func run(with report: CrashReport?) {
        switch consent.load().action(for: report) {
        case .nothing:
            return
        case .send(let report):
            send(report)
        case .ask(let report):
            let answer = ask(report)
            consent.save(CrashReportConsent.after(answer.choice, dontAskAgain: answer.dontAskAgain))
            if answer.choice == .send { send(report) }
        }
    }
}

extension CrashReportFlow {
    /// The real flow: the system prompt and the Tabbi server.
    static let live = CrashReportFlow(
        consent: CrashReportConsentStore(),
        ask: { CrashReportPrompt.ask(about: $0) },
        send: { report in
            Task.detached(priority: .utility) { _ = try? await CrashReportUploader().send(report) }
        }
    )
}
