import SwiftUI
import NotchKitCore
import NotchKit

/// The Closet tab: the study pet and its wardrobe. Shows a preview until
/// the closet lands.
struct ClosetPanel: View {
    var body: some View {
        ModulePreview(
            module: .closet,
            pitch: "A pixel pet that keeps you company while you study.",
            features: [
                .init(symbol: "tshirt.fill", title: "Outfits and accessories",
                      detail: "Unlock new looks with focus time"),
                .init(symbol: "bubble.left.fill", title: "Pet coach",
                      detail: "Gentle nudges when you drift off task"),
                .init(symbol: "pawprint.fill", title: "Cats and dogs",
                      detail: "Pick a breed, name and colors"),
            ]
        )
    }
}
