import os
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
    static let kind = WidgetState.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PetTimelineProvider()) { entry in
            PetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tabbi")
        .description(Text("Your pet, today's streak and the running timer.", bundle: .tabbi))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PetEntry: TimelineEntry {
    var date: Date
    var state: WidgetState
    /// True when there is no state of the app's to show, so the widget asks
    /// the user to open Tabbi instead of showing zeros.
    var isWaitingForApp = false
}

/// Reads the state the app shares and lays out entries only where what the
/// widget shows changes by itself (a countdown ending, midnight). The app
/// reloads the timeline when it writes a change and once each launch, so
/// nothing here polls.
///
/// Every path returns an entry: a missing, unreadable or newer file shows
/// the "Open Tabbi to start" state (and says why in the log), never an
/// error, since WidgetKit shows a blank widget for an extension that fails.
struct PetTimelineProvider: TimelineProvider {
    /// `log show --predicate 'subsystem == "dev.tabbi.widget"'` shows what
    /// the widget read and why (docs/widget.md, Troubleshooting).
    static let log = Logger(subsystem: "dev.tabbi.widget", category: "timeline")

    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: .now, state: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        // The gallery shows the sample, so it looks alive before first use.
        let now = Date()
        completion(context.isPreview ? PetEntry(date: now, state: .sample(at: now)) : Self.entry(at: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let now = Date()
        let current = Self.entry(at: now)
        let entries = [current] + current.state.changeDates(after: now).map {
            PetEntry(date: $0, state: current.state, isWaitingForApp: current.isWaitingForApp)
        }
        // The last entry is the next midnight; ask again then for the new day.
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// The app's latest state from the App Group container, or the waiting
    /// state when there is none to read.
    private static func entry(at now: Date) -> PetEntry {
        guard let folder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetState.appGroup
        ) else {
            log.error("No App Group container for \(WidgetState.appGroup, privacy: .public)")
            return PetEntry(date: now, state: .empty(at: now), isWaitingForApp: true)
        }
        switch WidgetStateFile(folder: folder).load() {
        case .state(let state):
            log.debug("Read the shared state")
            return PetEntry(date: now, state: state)
        case .missing:
            log.notice("No shared state yet; showing Open Tabbi to start")
            return PetEntry(date: now, state: .empty(at: now), isWaitingForApp: true)
        case .unreadable(let reason):
            log.error("Could not read the shared state: \(reason, privacy: .public)")
            return PetEntry(date: now, state: .empty(at: now), isWaitingForApp: true)
        }
    }
}

struct PetWidgetEntryView: View {
    var entry: PetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        PetWidgetView(state: entry.state, date: entry.date, size: family == .systemMedium ? .medium : .small,
                      rendering: rendering, isWaitingForApp: entry.isWaitingForApp)
    }

    private var rendering: PetWidgetRendering {
        switch renderingMode {
        case .accented: .accented
        case .vibrant: .vibrant
        default: .fullColor
        }
    }
}
