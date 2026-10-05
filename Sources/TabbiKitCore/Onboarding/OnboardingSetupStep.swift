/// A just-in-time question first-run onboarding asks only when a module
/// that needs it is turned on: naming the pet, connecting Anki, granting
/// calendar access. A module lists its steps in its descriptor's `setup`;
/// two modules that need the same thing list the same step, and onboarding
/// asks it once.
///
/// Like `ModuleCategory` it is open: a new module can declare a step of its
/// own beside itself. Two steps are equal when their ids are, so a title can
/// change without touching saved data.
public struct OnboardingSetupStep: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public let id: String
    /// What the step sets up, such as "Your pet"; shown in the progress
    /// tooltip and the Settings re-run menu.
    public let title: String
    /// SF Symbol for the step's header.
    public let symbol: String
    /// Where the step sits among the setup steps; lower runs first. Ties
    /// keep the order of the modules that asked for them.
    public let rank: Int

    public init(_ id: String, title: String, symbol: String, rank: Int = 100) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.rank = rank
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public var description: String { id }
}

public extension OnboardingSetupStep {
    /// The fun one first: pick a cat or a dog, its breed and its name.
    static let pet = OnboardingSetupStep("pet", title: "Your pet", symbol: "pawprint.fill", rank: 10)
    /// Check that Anki and AnkiConnect answer on this Mac.
    static let anki = OnboardingSetupStep("anki", title: "Connect Anki", symbol: "rectangle.stack.fill", rank: 20)
    /// Ask for calendar access, so Today can plan around events.
    static let calendar = OnboardingSetupStep("calendar", title: "Calendar access", symbol: "calendar", rank: 30)
    /// Pick the study rhythm the Study timer starts with.
    static let studyMethod = OnboardingSetupStep("studyMethod", title: "Study method", symbol: "timer", rank: 40)
    /// Pick a display name and the server study parties meet on.
    static let party = OnboardingSetupStep("party", title: "Study parties", symbol: "person.3.fill", rank: 50)
}
