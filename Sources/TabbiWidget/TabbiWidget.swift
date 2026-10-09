import SwiftUI
import TabbiKitCore
import TabbiWidgetUI
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
            PetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tabbi")
        .description("Your pet, today's streak and the running timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PetEntry: TimelineEntry {
    var date: Date
    var state: WidgetState
}

/// Reads the state the app shares and lays out entries only where what the
/// widget shows changes by itself (a countdown ending, midnight). The app
/// reloads the timeline when it writes a change, so nothing here polls.
struct PetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: .now, state: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        // The gallery shows the sample, so it looks alive before first use.
        let now = Date()
        completion(PetEntry(date: now, state: context.isPreview ? .sample(at: now) : Self.sharedState(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let now = Date()
        let state = Self.sharedState(at: now)
        let entries = ([now] + state.changeDates(after: now)).map { PetEntry(date: $0, state: state) }
        // The last entry is the next midnight; ask again then for the new day.
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// The app's latest state from the App Group container, or the empty
    /// state before the app has written one.
    private static func sharedState(at now: Date) -> WidgetState {
        guard let folder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetState.appGroup
        ), let state = WidgetStateFile(folder: folder).read() else { return .empty(at: now) }
        return state
    }
}

struct PetWidgetEntryView: View {
    var entry: PetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        PetWidgetView(state: entry.state, date: entry.date, size: family == .systemMedium ? .medium : .small)
    }
}
