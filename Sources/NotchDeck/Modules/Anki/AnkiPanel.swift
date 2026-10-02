import SwiftUI
import NotchKitCore
import NotchKit

/// The Anki tab: today's due cards from Anki via AnkiConnect. Shows a
/// preview until the deck view lands.
struct AnkiPanel: View {
    var body: some View {
        ModulePreview(
            module: .anki,
            pitch: "Your due cards and streak, right under the notch.",
            features: [
                .init(symbol: "rectangle.stack.fill", title: "Due today",
                      detail: "New, learning and review counts per deck"),
                .init(symbol: "flame.fill", title: "Streak and retention",
                      detail: "Two weeks of reviews at a glance"),
                .init(symbol: "bolt.fill", title: "Card sprints",
                      detail: "Time a session by cards answered"),
            ]
        )
    }
}
