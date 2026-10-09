import SwiftUI
import TabbiKitCore
import WidgetKit

/// The widget extension's entry point: one widget, in small and medium.
@main
struct TabbiWidgetBundle: WidgetBundle {
    var body: some Widget {
        TabbiPetWidget()
    }
}

/// The pet on the desktop and in Notification Center.
struct TabbiPetWidget: Widget {
    static let kind = "dev.tabbi.widget.pet"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PetTimelineProvider()) { entry in
            PetWidgetView(entry: entry)
        }
        .configurationDisplayName("Tabbi")
        .description("Your pet, today's streak and the running timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PetEntry: TimelineEntry {
    var date: Date
    var pet: PetProfile
}

struct PetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: .now, pet: .starter(.cat))
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

struct PetWidgetView: View {
    var entry: PetEntry

    var body: some View {
        VStack(spacing: 8) {
            if let image = PetRenderer.shared.image(
                for: entry.pet.sittingCanvas(), palette: entry.pet.palette, scale: 3
            ) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
            }
            Text(entry.pet.name)
                .font(.system(.headline, design: .rounded))
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
