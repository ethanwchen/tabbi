import Foundation

/// The one-time disclosure shown before a provider that sends data off
/// the Mac is picked: who receives the data, what each AI feature sends,
/// and that the provider's own terms apply. App Store Guideline 5.1.2(i)
/// asks for this before personal data goes to a third-party AI, and it is
/// what the Privacy Policy promises.
extension AIProviderID {
    /// Whether requests leave this Mac. Ollama answers on localhost, so it
    /// needs no permission; every other provider is a third party.
    public var sendsDataOffMac: Bool { transport != .local }

    /// The company that receives requests, named in the disclosure. Nil for
    /// Ollama, which runs on this Mac.
    public var vendorName: String? {
        switch self {
        case .claudeCLI, .anthropic: "Anthropic"
        case .codexCLI, .openAI: "OpenAI"
        case .geminiCLI, .gemini: "Google"
        case .ollama: nil
        }
    }

    /// The disclosure's title, e.g. "Send your AI requests to Anthropic?".
    public var consentTitle: String {
        String(localized: "Send your AI requests to \(vendorName ?? displayName)?", bundle: .tabbi)
    }

    /// The disclosure's body: the provider, what each feature sends, and
    /// whose terms apply. `appName` is the edition's name. Each line is its
    /// own string, so a translation keeps the list's shape.
    public func consentMessage(appName: String) -> String {
        let vendor = vendorName ?? displayName
        let intro = isCommandLineTool
            ? String(localized: "With \(displayName), \(appName) sends these to \(vendor) through the \(displayName) command you signed in to when you use an AI feature:", bundle: .tabbi)
            : String(localized: "With \(displayName), \(appName) sends these to \(vendor) with your API key when you use an AI feature:", bundle: .tabbi)
        return [
            intro,
            String(localized: "Ask AI: your questions, the chat so far and any screenshot you attach.", bundle: .tabbi),
            String(localized: "Refine and AI day plans: your calendar event titles and times, tasks, goals and the plan.", bundle: .tabbi),
            String(localized: "Day review: today's focus and study minutes, sessions and points, your goal counts and the titles of the tasks you finished or are carrying over.", bundle: .tabbi),
            String(localized: "\(vendor) handles them under its own terms and privacy policy. \(appName)'s AI features send nothing else, and nothing until you allow it. You can switch to None in Connections at any time.", bundle: .tabbi),
        ].joined(separator: "\n")
    }
}
