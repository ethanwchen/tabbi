import SwiftUI
import NotchKitCore
import NotchKit

/// The Party tab: studying alongside friends. Shows a preview until
/// group sessions land.
struct PartyPanel: View {
    var body: some View {
        ModulePreview(
            module: .party,
            pitch: "Study alongside friends on one shared timer.",
            features: [
                .init(symbol: "person.2.fill", title: "Shared sessions",
                      detail: "Focus together, take breaks together"),
                .init(symbol: "circle.dotted.circle", title: "Who's studying",
                      detail: "Friends' focus status at a glance"),
                .init(symbol: "hand.thumbsup.fill", title: "Gentle accountability",
                      detail: "Check-ins and streaks, no leaderboards"),
            ]
        )
    }
}
